#!/usr/bin/env python3
"""Create one UAT Story list view per Jira sprint in a project's UAT org.

Used by the kicksaw-uat skill after the story sync (SKILL.md step 2.1b). Sprint names come from Jira: pass them with
--sprints (the skill reads them from the project's stories and board), or use --from-org to take the sprint names the
story sync already wrote to UAT_Story__c.Sprint__c. Nothing project-specific lives in the app source: the list views
are generated here and deployed to that one org.

  python3 scripts/sprint_list_views.py --org <alias> --sprints "Sprint 1 - Foundation" "Sprint 2 - Email"
  python3 scripts/sprint_list_views.py --org <alias> --from-org            # plan only
  python3 scripts/sprint_list_views.py --org <alias> --from-org --deploy   # create the missing views
  python3 scripts/sprint_list_views.py --org <alias> --sprints ... --deploy --prune   # also remove stale views

It only ever writes views named UAT_Sprint_*. Views whose sprint is no longer in Jira (renamed, or closed with no story
left in it) are listed as "stale"; they are removed only with --deploy --prune, which a person approves. A renamed sprint
gets a new view under its new name, so a rename is: create the new view, prune the old one.
--rewrite also redeploys the views that already exist (to repair their filters).
After a deploy it checks every view returns the same number of stories as a direct count for that sprint.
No sprints: it says so and does nothing.
"""
import argparse, json, os, re, subprocess, sys, tempfile
from xml.sax.saxutils import escape

PREFIX = 'UAT_Sprint_'
COLUMNS = ['NAME', 'Summary__c', 'Jira_Status__c', 'Epic__c', 'Sprint__c', 'Last_Synced__c']


def sf(*args, cwd=None):
    r = subprocess.run(['sf', *args, '--json'], capture_output=True, text=True, cwd=cwd)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        sys.exit('sf did not return JSON: ' + (r.stderr or r.stdout)[:400])
    if d.get('status') not in (0, None):
        sys.exit('sf error: ' + str(d.get('message'))[:400])
    return d['result']


def natural(name):
    return [int(p) if p.isdigit() else p.lower() for p in re.split(r'(\d+)', name)]


def dev_name(name, taken):
    slug = re.sub(r'_+', '_', re.sub(r'[^A-Za-z0-9]+', '_', name)).strip('_')
    if slug.lower().startswith('sprint_'):
        slug = slug[7:]
    base = (PREFIX + slug)[:40].rstrip('_') or PREFIX + 'X'
    cand, n = base, 2
    while cand.lower() in taken:
        suffix = f'_{n}'; cand = base[:40 - len(suffix)] + suffix; n += 1
    taken.add(cand.lower())
    return cand


def filter_value(sprint):
    # A comma in a list view filter value means OR ("a, b" = a OR b), so a sprint name with a comma must be quoted.
    return '"' + sprint.replace('"', '') + '"' if ',' in sprint else sprint


def view_xml(full_name, sprint):
    cols = ''.join(f'    <columns>{c}</columns>\n' for c in COLUMNS)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<ListView xmlns="http://soap.sforce.com/2006/04/metadata">\n'
            f'    <fullName>{full_name}</fullName>\n{cols}    <filterScope>Everything</filterScope>\n'
            f'    <filters>\n        <field>Sprint__c</field>\n        <operation>equals</operation>\n        <value>{escape(filter_value(sprint))}</value>\n    </filters>\n'
            f'    <label>{escape(sprint[:40])}</label>\n</ListView>\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--org', required=True)
    ap.add_argument('--sprints', nargs='*', help='sprint names from Jira')
    ap.add_argument('--from-org', action='store_true', help='use the sprint names already on UAT Stories')
    ap.add_argument('--deploy', action='store_true', help='create the missing list views (default: plan only)')
    ap.add_argument('--prune', action='store_true', help='with --deploy: remove the stale UAT_Sprint_* views')
    ap.add_argument('--rewrite', action='store_true', help='also redeploy the UAT_Sprint_* views that already exist')
    a = ap.parse_args()

    if a.sprints:
        sprints = a.sprints
    elif a.from_org:
        rows = sf('data', 'query', '-o', a.org, '-q', 'SELECT Sprint__c FROM UAT_Story__c WHERE Sprint__c != null GROUP BY Sprint__c')['records']
        sprints = [r['Sprint__c'] for r in rows]
    else:
        sys.exit('Give --sprints <names...> or --from-org')
    sprints = sorted({s.strip() for s in sprints if s and s.strip()}, key=natural)

    existing = sf('data', 'query', '-o', a.org, '-q',
                  f"SELECT DeveloperName, Name FROM ListView WHERE SobjectType = 'UAT_Story__c' AND DeveloperName LIKE '{PREFIX}%'")['records']
    have = {r['Name']: r['DeveloperName'] for r in existing}
    taken = {r['DeveloperName'].lower() for r in existing}
    missing = [s for s in sprints if s[:40] not in have]
    stale = sorted(n for n in have if n not in {s[:40] for s in sprints})
    plan = {'org': a.org, 'sprints_in_jira': sprints, 'already_there': sorted(have, key=natural) if not stale else sorted(set(have) - set(stale), key=natural),
            'to_create': [], 'stale_views_for_a_person_to_review': stale, 'deployed': False}

    if a.prune and not a.deploy:
        plan['note_prune'] = '--prune does nothing without --deploy: the stale views above would be removed.'
    if not sprints:
        plan['note'] = 'No sprints found: no list views created.'
        print(json.dumps(plan, indent=2)); return
    work = tempfile.mkdtemp(prefix='uat-sprint-views-')
    lv_dir = os.path.join(work, 'force-app/main/default/objects/UAT_Story__c/listViews')
    os.makedirs(lv_dir)
    json.dump({'packageDirectories': [{'path': 'force-app', 'default': True}], 'sourceApiVersion': '62.0'}, open(os.path.join(work, 'sfdx-project.json'), 'w'))
    targets = [(s, dev_name(s, taken)) for s in missing]
    if a.rewrite:
        targets += [(s, have[s[:40]]) for s in sprints if s[:40] in have]
        plan['rewritten'] = [s[:40] for s in sprints if s[:40] in have]
    for s, dn in targets:
        open(os.path.join(lv_dir, dn + '.listView-meta.xml'), 'w').write(view_xml(dn, s))
        if s in missing:
            plan['to_create'].append({'list_view': s[:40], 'api_name': dn, 'filter': f'Sprint equals "{s}"'})
    plan['source_dir'] = work
    if a.deploy and targets:
        res = sf('project', 'deploy', 'start', '-o', a.org, '-d', os.path.join(work, 'force-app'), '--wait', '20', '--ignore-conflicts', cwd=work)
        plan['deployed'] = res.get('status') == 'Succeeded' or res.get('success') is True
        plan['deploy_id'] = res.get('id')
    if a.deploy and a.prune and stale:
        pdir = os.path.join(work, 'prune'); os.makedirs(pdir)
        members = ''.join(f'        <members>UAT_Story__c.{have[n]}</members>\n' for n in stale)
        head = '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        open(os.path.join(pdir, 'package.xml'), 'w').write(head + '    <version>62.0</version>\n</Package>\n')
        open(os.path.join(pdir, 'destructiveChanges.xml'), 'w').write(
            head + f'    <types>\n{members}        <name>ListView</name>\n    </types>\n    <version>62.0</version>\n</Package>\n')
        res = sf('project', 'deploy', 'start', '-o', a.org, '--manifest', os.path.join(pdir, 'package.xml'),
                 '--post-destructive-changes', os.path.join(pdir, 'destructiveChanges.xml'), '--wait', '20', cwd=work)
        plan['pruned'] = [{'list_view': n, 'api_name': have[n]} for n in stale]
        plan['prune_deploy_id'] = res.get('id')
        plan['stale_views_for_a_person_to_review'] = []
    # Check: each view must return what a direct count for that sprint returns.
    views = sf('data', 'query', '-o', a.org, '-q',
               f"SELECT Id, Name FROM ListView WHERE SobjectType = 'UAT_Story__c' AND DeveloperName LIKE '{PREFIX}%'")['records']
    by_label = {v['Name']: v['Id'] for v in views}
    check = []
    for s in sprints:
        if s[:40] not in by_label:
            continue
        want = sf('data', 'query', '-o', a.org, '-q', "SELECT COUNT() FROM UAT_Story__c WHERE Sprint__c = '" + s.replace("\\", "\\\\").replace("'", "\\'") + "'")['totalSize']
        q = sf('api', 'request', 'rest', f"/services/data/v62.0/sobjects/UAT_Story__c/listviews/{by_label[s[:40]]}/describe", '-o', a.org)
        q = q.get('body', q) if isinstance(q, dict) else json.loads(q)
        q = json.loads(q) if isinstance(q, str) else q
        where = q['query'][q['query'].index('FROM'):]
        where = where[:where.index('ORDER BY')] if 'ORDER BY' in where else where
        got = sf('data', 'query', '-o', a.org, '-q', 'SELECT COUNT() ' + where)['totalSize']
        check.append({'list_view': s[:40], 'stories_in_sprint': want, 'list_view_returns': got, 'ok': want == got})
    plan['check'] = check
    plan['all_views_correct'] = all(c['ok'] for c in check)
    print(json.dumps(plan, indent=2))


if __name__ == '__main__':
    main()
