---
name: kicksaw-uat
description: Runs the whole Kicksaw UAT process for any Kicksaw client project with the Kicksaw UAT App - install and set up the app in the client's org, load the project's Jira stories, triage tester feedback against the acceptance criteria, push bugs and enhancements to Jira, sync status back, and report readiness. Use whenever someone names a project and says "set up UAT", "check UAT readiness", "run UAT triage", "sync UAT stories", "push UAT items to Jira", "UAT status" or runs /kicksaw-uat <project>.
---

# Kicksaw UAT

One skill for the whole UAT process on any Kicksaw project. The person only names the project (client name, Jira
project key or org alias). You find everything else. Nothing about a particular client lives in this skill: every
project value is asked for or discovered, and stored in the org's **Kicksaw UAT Setting** (`Default` record).

## Where the app and this skill live

- **Source repo (public):** https://github.com/iandevlin-pixel/kicksaw-uat-app (`source.repo` below means
  `https://github.com/iandevlin-pixel/kicksaw-uat-app.git`). Releases are tags `v*`; the current release is `latest.tag` in `install-versions.json`.
- **Install settings:** `install-versions.json` next to this file. If it isn't there (for example the skill was
  saved on its own), read it from
  https://raw.githubusercontent.com/iandevlin-pixel/kicksaw-uat-app/main/skills/kicksaw-uat/install-versions.json
  (`latest.tag`, `latest.version`, `source.repo`, manifests and test classes).
- **This skill's latest copy:** `skills/kicksaw-uat/SKILL.md` in that repo. If it's newer than this copy, follow it.
- The original v1 app is in Kicksaw's older repo Kicksaw-Consulting/internal-uat-application; never install v2 from there.

## Starting a new project

Prerequisites (check them; ask for what's missing):
1. **Salesforce CLI** (`sf`) logged in to the client's UAT org (usually a sandbox): `sf org login web --alias <alias>`.
2. **Jira access** to the client's Jira project: the Atlassian connector (MCP) or API access.
3. **git** installed, to download the app's source from https://github.com/iandevlin-pixel/kicksaw-uat-app. The repo is public,
   so no GitHub login is needed. Only used to install or upgrade the app.
4. **The client's AI approval** to have an AI assistant read their UAT records (many clients need this, government
   and health clients especially). Don't triage until it's confirmed.

Then run one line: `/kicksaw-uat <project>` and say "set up UAT" (or "install the UAT app in <alias>").
Setup asks for or discovers everything a project has to supply:

| Value | Where it comes from | Stored in |
| --- | --- | --- |
| UAT org alias | `sf org list`, confirm with the person | (your CLI) |
| Sandbox vs production, commercial vs Government Cloud | `Organization` query | - |
| Jira site and project key | Atlassian connector lookup, confirm | `Jira_Site__c`, `JIRA_ProjectID__c` |
| Which Jira issues are the stories | default `project = <KEY> AND issuetype = Story`, confirm | `Story_JQL__c` |
| Where the acceptance criteria are on a story | look at 2 or 3 stories: an "Acceptance Criteria" field, the description, or both (step 2.1); say what you found | the run report |
| Future Phase sprint (for enhancements) | the project's board, confirm; none: backlog + `future-phase` label | `Future_Phase_Sprint_ID__c` (blank = fallback) |
| Jira status → UAT status mapping | the project's Jira workflow, confirm | `Status_Mapping__c` |
| Bugs as Sub-tasks of the story, or linked Tasks | ask the project lead (default Sub-task) | the run report |
| Testers and Kicksaw reviewers | user picker (setup step 3) | permission sets |
| Apps the testers test in (utility bar) | list of the org's Lightning apps, the person picks | the apps' utility bars |
| Triage schedule | ask (start with Manual) | `Triage_Schedule__c` |

## 0. Find the project context (always first)

1. **Jira project:** search Jira for the project by key or name (Atlassian MCP `getVisibleJiraProjects` /
   `searchJiraIssuesUsingJql`). Confirm the key with the person if more than one matches.
2. **Salesforce org:** `sf org list`. Pick the UAT org for this client (usually the sandbox where UAT runs, e.g. an
   alias containing the client name and `UAT`, `Partial` or `Full`). **Never use a production org unless the person
   says so explicitly.** Confirm the alias if it isn't obvious.
3. **App and settings:** check the app is there and read the settings record:
   ```bash
   sf data query -o <alias> -q "SELECT Jira_Site__c, JIRA_ProjectID__c, Story_JQL__c, UAT_Label__c, Subtask_Prefix__c, Future_Phase_Sprint_ID__c, Status_Mapping__c, Triage_Schedule__c, Instant_Runs_Enabled__c, Routine_Trigger_Id__c FROM Kicksaw_UAT_Setting__mdt WHERE DeveloperName = 'Default'"
   ```
   If the query fails (no app) or the Jira project / Story JQL is blank, go to **Setup**. Otherwise go to **Run**.
4. **Compliance:** reading client records with an AI assistant can need the client's AI approval (government and health
   clients especially). Ask once per project whether it's approved for this org; record the answer in the report.

## 0b. Readiness check (read only)

Run it when the person says "check", "is <project> ready for UAT?" or `/kicksaw-uat <project> check`, and always as
the first thing in Setup. It **changes nothing** in Salesforce or Jira: queries and Jira reads only. Its job is to tell
a project team what is ready, what the skill will work around, and what they must do first.

Check each line, then print the table. Status is one of **Ready**, **Will work around** (a fallback applies; say
which) or **Needed first** (setup stops until it's done). Never guess a value: say what you looked at.

| # | Check | How | If it isn't there |
| --- | --- | --- | --- |
| 1 | Jira project found, and you can read it | search by key or name | Needed first: Jira access for the person running the skill |
| 2 | Stories found | run the Story JQL (default `project = <KEY> AND issuetype = Story`); give the count | Needed first if 0: ask which issue type or JQL holds the stories |
| 3 | Acceptance criteria | on a sample of 10 stories (all if fewer), count those with an "Acceptance Criteria" field filled, those with only a description, those with neither (step 2.1) | Will work around: triage uses the description. Neither on most stories: say triage will be weak, and feedback collection and Jira push still work |
| 4 | Test steps | same sample: a "Test Steps" field or similar | Optional: say so |
| 5 | Jira statuses | list the project's statuses and their categories; show the Status Mapping you would propose | Will work around: default mapping by category (see Fallbacks) |
| 6 | Bug tickets | does the project have a Sub-task issue type? | Will work around: linked Tasks |
| 7 | Enhancement tickets | is there a board with a future-phase or backlog sprint? | Will work around: backlog with a `future-phase` label |
| 8 | Salesforce org | `sf org list`: an alias for the UAT org, logged in; `Organization` query: sandbox or production, Government Cloud | Needed first: `sf org login web --alias <alias>`. Production: say so and that it needs an explicit yes |
| 9 | App | read `Installed_Version__c`: not installed, older build, or current | Setup installs or upgrades it |
| 10 | Testers and reviewers | count active standard users; who already has the `Kicksaw_UAT_App*` permission sets | Setup asks who they are |
| 11 | Where testers test | list the org's Lightning apps; which already have New UAT Feedback | Setup adds it to the apps picked |
| 12a | Slack alerts | `Slack_Alerts_Enabled__c`; does named credential `Kicksaw_UAT_Slack` exist and point at a real webhook (not `REPLACE_WITH_WEBHOOK_PATH`)? | Optional: setup step 5 |
| 12 | Client AI approval | ask the person: is AI reading UAT records approved for this client? | Needed first for triage (install and feedback collection can go ahead) |

Output, in this shape (plain words, one line each, worst first inside each group):

```
UAT readiness: <project> (<Jira key>, <org alias>)        <date>
Result: READY | READY WITH WORKAROUNDS | NOT READY (<n> things needed first)

Needed first
  - <check>: <what is missing> -> <who does what>
Will work around
  - <check>: <what is missing> -> <what the skill does instead>
Ready
  - <check>: <what was found>
Next step: <one line, e.g. "say 'set up UAT' to install and configure">
```

### Fallbacks (so a missing piece never blocks a project)
- **No Acceptance Criteria field:** use the description (step 2.1).
- **No future-phase sprint, or no board:** leave `Future_Phase_Sprint_ID__c` blank; enhancements are created as Stories
  in the backlog with the labels `UAT_Label__c` and `future-phase`.
- **No Sub-task issue type** (team-managed projects often have none), or the project lead prefers it: bugs are created
  as Tasks (or Bugs, if the project has that type and the lead picks it) linked to the tested story with "relates to".
- **No status mapping agreed, or a Jira status the mapping doesn't list:** map by Jira status category: a status in the
  Done category = Ready for Retest, everything else = In Progress. Exception: a Done-category status that means the
  work was dropped (Cancelled, Won't Do, Rejected, Duplicate) never becomes Ready for Retest: leave the UAT status as
  it is and list the item in the report for a reviewer. Show the mapping and let the person edit it; in the
  readiness check, list every project status the saved mapping doesn't cover.
- **No story on an item and none fits:** a Bug still needs a story for a Sub-task; with linked Tasks it is created
  unlinked and the report lists it.
Record each fallback used in the setup report, so the next run does the same.

## 1. Setup (once per project)

0. Run the **readiness check** (0b). Stop on anything under "Needed first" and tell the person what to do.

1. **Install the app (one step).** The person can just say "install the UAT app in <alias>"; you work out the rest.
   The app is installed from the source of a tagged GitHub release (see `install-versions.json`, next to this file).
   Deploy only here (first install) and when a newer release exists (step 2.0); never on routine runs.
   1. **Which org:** use the alias from step 0, or ask for it.
   2. **Sandbox or production, commercial or Government Cloud:**
      ```bash
      sf data query -q "SELECT Id, Name, IsSandbox, InstanceName, OrganizationType FROM Organization" --target-org <alias> --json
      ```
      `IsSandbox = true` → sandbox. Government Cloud: the person says so, or the instance is a Government Cloud
      instance (check trust.salesforce.com if unsure); source deploys work the same there. Say what you found
      ("<alias> is a production org, <name>") before going on.
   3. **Already installed?** Read the stamp:
      ```bash
      sf data query -o <alias> -q "SELECT Installed_Version__c FROM Kicksaw_UAT_Setting__mdt WHERE DeveloperName = 'Default'"
      ```
      - Query fails (no object): **first install**.
      - Stamp equals `latest.version`: already current; skip to step 2.
      - Stamp older, or blank but `UAT_Feedback__c` exists (installed before stamping): **upgrade**; say from what to
        what, and ask.
   4. **Get the release:** clone the tag into a temporary folder (public repo, no login needed; if the clone fails,
      say so and stop):
      ```bash
      git clone --depth 1 --branch <latest.tag> <source.repo> "$TMPDIR/kicksaw-uat-app"
      cd "$TMPDIR/kicksaw-uat-app"
      ```
   5. **Production gate.** If `IsSandbox = false`, stop and ask: "Deploy Kicksaw UAT App <version> into PRODUCTION org
      <alias> (<org name>, <Id>)? yes/no". Go on only on an explicit yes naming that org. Never on your own initiative.
   6. **Validate, then deploy** the app manifest. It leaves out profiles and the settings records, so nothing a project
      configured is overwritten. Run the app's own tests (`source.testClasses`), never all the org's tests:
      ```bash
      sf project deploy validate -o <alias> --manifest manifest/uat-app.xml --test-level RunSpecifiedTests \
        --tests UatReviewControllerTest --tests TestManagementControllerTest --tests NavigationServiceControllerTest --tests multiselectToCollection_Test --tests UatSlackAlertTest --wait 30
      sf project deploy quick -o <alias> --job-id <validated id> --wait 30
      ```
      If validation fails, report the errors and stop; nothing was changed.
   7. **First install only:** deploy the settings records that don't exist yet (they're blank; setup fills them
      next). Check first: `sf data query -o <alias> -q "SELECT DeveloperName FROM Kicksaw_UAT_Setting__mdt"`. An org
      that had v1 usually already has `UAT_Settings`: deploy only `Default` then
      (`sf project deploy start -o <alias> -m "CustomMetadata:Kicksaw_UAT_Setting.Default"`), otherwise
      `--manifest manifest/first-install.xml`. Never redeploy a record that exists, and never on an upgrade.
      If v1 was installed, its flows are already active: the deploy activates the fixed versions shipped here.
   8. **Upgrade only:** for each release newer than the org's stamp, if `release/<tag>/destructiveChanges.xml` lists
      anything, show it, ask, then deploy it (`sf project deploy start -o <alias> --manifest <empty package.xml>
      --post-destructive-changes release/<tag>/destructiveChanges.xml`).
   9. **Stamp the version** in the settings record without touching its other values: in the release folder, retrieve
      `sf project retrieve start -o <alias> -m "CustomMetadata:Kicksaw_UAT_Setting.Default"`, set the
      `Installed_Version__c` value in that file to "<version> (<tag>)" (add the `<values>` block if it's missing),
      then `sf project deploy start -o <alias> -d force-app/main/default/customMetadata/Kicksaw_UAT_Setting.Default.md-meta.xml --ignore-conflicts`.
   10. Say what was installed (version, tag, deploy IDs), delete the temporary folder, then carry on: settings (2),
       access with the user picker (3), stories (4).

   Optional later: if `install-versions.json` has a `package.commercial.packageVersionId` (not `TBD`) and the person
   prefers a package, install it instead with `sf package install --package <id> --target-org <alias> --wait 20
   --security-type AdminsOnly --no-prompt` (same production gate).
2. **Fill the settings record** (`Kicksaw_UAT_Setting.Default`, deploy the edited custom metadata file):
   - `Jira_Site__c` (the Jira site the project uses, Kicksaw's or the client's: `<site>.atlassian.net`), `JIRA_ProjectID__c` (project key)
   - `Story_JQL__c`: default `project = <KEY> AND issuetype = Story`
   - `Future_Phase_Sprint_ID__c`: the id of the project's "Future Phase" sprint (find it on the project's board)
   - `Status_Mapping__c`: built from **this project's own Jira statuses**, never copied from another project.
     1. Read every status the project's story, sub-task, task and bug types can be in, with its category (To Do,
        In Progress, Done).
     2. Propose one line per status: Done category = Ready for Retest; a dropped status (Cancelled, Won't Do,
        Rejected, Duplicate) = no change, a reviewer looks; everything else = In Progress.
     3. Show the whole table and let the person change any line (the choices per Jira status are: In Progress,
        Ready for Retest, or "leave it, tell a reviewer"). Ask plainly which status means "fixed and ready for
        the tester": some projects use Done, others Ready for UAT or Deployed to UAT.
     4. Save it in the field's format, e.g.
        `New,Build Ready,In Progress,On Hold,Ready for QA=In Progress; Done=Ready for Retest`. Statuses the person
        chose to leave are simply not listed. Every other project status must be listed: read the saved value back
        and check none is missing.
   - `UAT_Label__c` (`UAT`), `Subtask_Prefix__c` (`UAT -`), `Triage_Schedule__c` (start with `Manual`)
   - `New_Test_Run_Notification_Settings__c` (labelled **Tester Notification Channel**): how testers hear about Needs Info, Ready for Retest and closed items:
     `App` (bell notification, the default to use), `Email` or `Both`. Always set it: left out of the settings file,
     the field's default is `Email`, and then testers get no bell. Email needs the sandbox's deliverability set to
     All email.
3. **Access: ask, don't assume.** Find out who tests and who reviews, then assign the permission sets.
   1. List the active people in the org (and who already has the app):
      ```bash
      sf data query -o <alias> -q "SELECT Id, Name, Username, Profile.Name FROM User WHERE IsActive = true AND UserType = 'Standard' ORDER BY Name"
      sf data query -o <alias> -q "SELECT AssigneeId, Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'Kicksaw_UAT_App%'"
      ```
   2. Ask two questions, each as a pick list of those users (a multi-select question tool if your client has one,
      otherwise a numbered list the person answers with numbers). Show name, username and profile; mark who already
      has access.
      - **Which users are UAT testers?** (client testers who submit feedback) → `Kicksaw_UAT_App_End_User`
      - **Which users are Kicksaw reviewers?** (decide items on UAT Review; gets the `UAT_Kicksaw_Reviewer`
        custom permission) → `Kicksaw_UAT_App`
      Ask separately whether routines will run and, if so, which user is the integration user →
      `Kicksaw_UAT_App_Integration`. Nobody is assigned anything they weren't picked for.
   3. Read the plan back (user → permission set), wait for a yes, then assign only the missing ones:
      `sf org assign permset -o <alias> --name <PermissionSet> --on-behalf-of <username>` (repeat
      `--on-behalf-of` for several users). Report what was assigned and what was already there.
   4. **Utility bar.** Testers submit feedback from the **New UAT Feedback** utility item (flow
      `Create_UAT_Feedback_Item`), and it should be in every app they test in, not only the Kicksaw UAT app. List the
      org's Lightning apps and let the person pick:
      ```bash
      sf data query -o <alias> -q "SELECT DeveloperName, Label, NavType FROM AppDefinition WHERE UiType = 'Lightning' ORDER BY Label"
      ```
      For each app picked: retrieve the app (`CustomApplication:<DeveloperName>`) to find its `<utilityBar>`, retrieve
      that FlexiPage, keep a copy as the rollback, add a `flowruntime:interview` item with `flowName`
      `Create_UAT_Feedback_Item` and label `New UAT Feedback` (copy the item from `Kicksaw_UAT_UtilityBar`), validate,
      then deploy. If the app has no utility bar, say so and ask before creating one. This changes the client's app
      metadata: confirm the plan first, never in production without an explicit yes, and tell the person that the
      client project's own deploys of that utility bar will remove the item unless it's added to their source too.
      **Record the apps** that got the item (label and DeveloperName) in the setup report, and give the person that
      list to keep with the project's UAT notes: the Run step's utility bar check uses it. (The settings record has
      no field for it; don't add metadata fields for this without asking.)
4. **Load the stories:** run step 2.1.
5. **Slack alerts (optional): ask.** "Should the team get a Slack message for each new feedback item?" A message has
   a color bar for the priority, then "New UAT feedback <item number>" linked to the record, then type, severity, Jira
   story and submitter one per line in a code block; never the tester's text. If yes:
   - Ask which Slack channel, and whether the client approves a call from their org to Slack (Government Cloud and
     health clients may need this first; record the answer).
   - Deploy the named credential once: `sf project deploy start -o <alias> -d slack-alerts` from the release folder.
     Never redeploy it on an upgrade (it holds the project's webhook).
   - Create the webhook. No Slack admin needed: in Slack, Workflow Builder > New workflow > start "From a webhook",
     variables `text`, `bar`, `name`, `details` and `link` (all Text); one step "Send a message to a channel" (the
     project's channel) whose message is: line 1 `{bar}`; line 2 the words `New UAT feedback` made a link with the link
     button (Link = the `{link}` variable), a space, then `{name}`; line 3 `{details}` inside a code block (the
     code-block button). Name it "Kicksaw UAT Alerts - <client>", "Workflow managers only", Publish. Markup sent in a
     variable shows literally and link text can't be a variable, so the layout has to be set in the workflow. (A Slack
     app incoming webhook also works, using `text`, but installing an app usually needs a Slack admin.)
   - The person copies the web request URL (workflow > "Starts with a webhook") and pastes it into Setup > Named
     Credentials > Kicksaw UAT Slack (legacy) > URL themselves. Never ask for the URL in chat or paste it for them:
     anyone who has it can post to the channel.
   - Check **Slack Alerts Enabled** on the settings record (deploy the edited custom metadata file), then create one
     test item to see the message arrive, and delete it.
   If no: leave Slack Alerts Enabled unchecked; nothing posts. To stop alerts later, uncheck it.
6. Tell the person what's left by hand: share the UAT report and dashboard
   folders with the testers' group, and (if wanted) create the scheduled routine (section 4).

## 2. Run (each UAT cycle, or on the Triage Schedule)

### 2.0 Version check (no deploy unless asked)
Read the org's stamp (`Installed_Version__c` on `Kicksaw_UAT_Setting.Default`) and compare it with `latest.version` in
`install-versions.json` (or the newest `v*` tag: `git ls-remote --tags <source.repo>`). Same: say nothing. Older:
tell the person ("<alias> has 0.3.0, 0.4.0 is out: <notes>") and offer the upgrade (setup step 1 from 1.4, same
production gate). Never upgrade without their yes, and never in a scheduled run: just report it.

### 2.0b Utility bar check
Project deploys can overwrite an app's utility bar and drop the **New UAT Feedback** item, and then testers can't
report. Before triage, check it is still there:
1. Get the list of apps that should have it: from the setup report or the person. If neither has it, ask which apps
   the testers test in (offer the org's Lightning apps, as in setup).
2. For each app, retrieve it to find its utility bar, retrieve that FlexiPage, and check for a `flowruntime:interview`
   item with `flowName` `Create_UAT_Feedback_Item`:
   ```bash
   sf project retrieve start -o <alias> -m "CustomApplication:<DeveloperName>" --output-dir .uat-check
   sf project retrieve start -o <alias> -m "FlexiPage:<utilityBar>" --output-dir .uat-check
   grep -l "Create_UAT_Feedback_Item" .uat-check/**/flexipages/*.flexipage-meta.xml
   ```
3. All present: say so in one line and go on. Missing from an app: tell the person which app lost it (likely the
   last deploy of that app's utility bar) and offer to re-add it exactly as in setup step 3.4: keep the retrieved
   file as the rollback copy, add the item, validate, then deploy. Only with their yes, and never in a production org
   without an explicit yes naming the org. Suggest they also add the item to the project's own source so the next
   deploy keeps it. Delete `.uat-check` afterwards.

### 2.1 Sync stories
Run `Story_JQL__c` in Jira (all pages). Upsert `UAT_Story__c` on `Jira_Key__c`: `Name` = "KEY summary" (80 chars),
`Summary__c`, `Jira_URL__c`, `Acceptance_Criteria__c` (see below), `Jira_Status__c`, `Epic__c`,
`Sprint__c` (a story carried over from a closed sprint lists several sprints: use its open sprint, else the last
one), `Smoke_Test_Steps__c` (the story's test steps from Jira if it has them, e.g. a Test Steps field; leave
what's there if Jira has none), `Last_Synced__c` = now. Use a bulk upsert from a CSV with LF line endings. Report stories that left the JQL;
don't delete them.

### 2.1b Sprint list views (after every story sync)
Testers and reviewers browse stories by sprint, so each Jira sprint gets a UAT Story list view.
1. **Check Jira for sprints.** Collect the sprint names from the stories the Story JQL returned (the sprint field on
   each story), plus the active and future sprints on the project's own board that belong to this project. A board can
   show other projects' sprints: leave those out. Use the sprint's name exactly as Jira has it; it is the value the
   sync writes to `Sprint__c`.
2. **No sprints** (a Kanban project, or none created yet): say so in the report and do nothing.
3. **Sprints found:** from the release folder (or a fresh clone of the release), run
   ```bash
   python3 scripts/sprint_list_views.py --org <alias> --sprints "<sprint 1>" "<sprint 2>" ...
   ```
   It prints the plan and changes nothing: the views to create (one per sprint, named after the sprint, filter
   "Sprint equals <name>", API name `UAT_Sprint_*`), the ones already there, and stale ones. In setup, or when a
   person runs the skill, show the plan and add `--deploy` after their yes (production: an explicit yes naming the
   org). A scheduled run only reports new sprints; it never deploys.
   After a deploy the script checks every view: `check` lists, per sprint, the stories in that sprint and what the
   list view returns, and `all_views_correct` must be true. If it is false, say which view is wrong and run it again
   with `--rewrite --deploy` (a sprint name with a comma has to be quoted in the filter; the script does that).
4. **Stale views** (a sprint renamed in Jira, or closed with no story left in it): a rename shows up as a new view to
   create plus the old name as stale. The script removes nothing unless asked. List them in the report; when a person
   runs the skill, ask, and on their yes run the same command with `--deploy --prune` (creates the new views, removes
   the stale ones, then checks every view). A scheduled run only reports them.
The views live in the project's org only. Never add them to the app source: sprint names differ per project.


**Acceptance criteria.** Projects keep them in different places, so read both and never assume:
1. Look for a Jira field named "Acceptance Criteria" (or close: "AC", "Acceptance criteria / DoD") on the stories. It is
   a custom field, so its id differs per Jira site: find it by name in the fields the search returns (ask for all
   fields on 2 or 3 stories first), then request that field id on every page.
2. Build `Acceptance_Criteria__c` as plain text (tables as rows of text), up to the field's 131,072 characters:
   - Field filled: the field's text first, then a blank line, "Story description:" and the description. The
     description stays in as context (background, out-of-scope notes, decisions); triage treats the field as the
     criteria.
   - No such field, or it is empty on this story: the description alone, as before.
   - Both empty: leave it blank and list the story in the report as "no acceptance criteria"; triage can't check
     feedback against it.
3. In the report say where the criteria came from (field name, description, or both) and how many stories had none.

### 2.2 Triage new feedback
```sql
SELECT Id, Name, Type__c, Priority__c, Status__c, Description__c, Steps__c, ExpectedBehavior__c, Actual_Behavior__c,
       ObjectName__c, RecordURL__c, PageReferenceInfo__c, Tested_Story__c, Tested_Story__r.Jira_Key__c,
       Tested_Story__r.Acceptance_Criteria__c, Kicksaw_Determination__c, Last_Triage_Run__c, Triage_Requested_At__c
FROM UAT_Feedback__c
WHERE Status__c = 'New' AND (Last_Triage_Run__c = null OR Triage_Requested_At__c > Last_Triage_Run__c)
```
For every item (Bug, Enhancement or Training):
1. **Story.** If the tester picked one, read its acceptance criteria. Where the text has a "Story description:" part
   (step 2.1), the text above it is the criteria and the description is context. If not, match the item to the likeliest UAT Story
   (description, steps, expected/actual, captured object and page against each story's summary and ACs). If one fits
   clearly, set `Tested_Story__c` to it and tick **Story Suggested by Triage** (`Story_Suggested_by_Claude__c = true`),
   and say why in the reasoning (quote the AC it matches). If none fits well, leave it blank and say so (often a sign
   of an Enhancement). The story is optional on the form: never overwrite a story a person picked (tester or
   reviewer; a reviewer's pick clears the box).
2. Look for duplicates among open feedback on the same story or object.
3. If it helps, read the captured record and related configuration in the org (read only).
4. Propose one of: **Bug** (misses an AC), **Enhancement** (beyond the ACs), **Training** (works as built; the tester
   needs to know how), **Not a Bug** (works as designed), **Duplicate** (name it), **Needs Info** (say what's missing).
5. Write, and never touch `Kicksaw_Determination__c`, `Status__c` or `Needs_Jira_Ticket__c` (Kicksaw decides):
   - `Claude_Proposed_Resolution__c`: "Proposed: <classification>" then what to do
   - `Claude_Repro_Steps__c`: numbered steps
   - `Claude_Classification_Reasoning__c`: why, with sources; if you suggested the story, start with
     "Story suggested by triage: <KEY> ..." (quote the AC, the story key, the duplicate item, the configuration
     checked). Rewrite it each run.
   - **Wording in records:** never name the AI tool or model in anything you write to Salesforce or Jira
     ("Triage", "triage suggests", not a product name). The `Claude_*` API names are legacy; the labels are neutral.
   - `Last_Triage_Run__c` = now

### 2.2b Recheck Needs Info items the tester answered
Items a reviewer sent back stay `Status__c = 'New'` with `Kicksaw_Determination__c = 'Needs Info'` (the reviewer's
question is in `Resolution__c`). When the tester edits the item, look at it again:
```sql
SELECT Id, Name, Description__c, Steps__c, ExpectedBehavior__c, Actual_Behavior__c, Resolution__c, Tested_Story__c,
       Tested_Story__r.Acceptance_Criteria__c, Last_Triage_Run__c, LastModifiedDate, LastModifiedById, SubmittedBy__c, CreatedById
FROM UAT_Feedback__c
WHERE Status__c = 'New' AND Kicksaw_Determination__c = 'Needs Info'
```
Take the ones where `LastModifiedDate > Last_Triage_Run__c` (or it was never triaged) and the last change was made by
the tester (`LastModifiedById` is `SubmittedBy__c` or `CreatedById`), not by a reviewer or the integration user.
For each, triage it again as in 2.2 with the new detail, and start `Claude_Proposed_Resolution__c` with
"Tester replied <date>." then "Proposed: <classification>" (still Needs Info if the question isn't answered: say what
is still missing). Rewrite the reasoning and repro steps, set `Last_Triage_Run__c`. **Leave `Kicksaw_Determination__c`
and `Resolution__c` alone:** the item stays on the UAT Review **Needs info** tab, and the reviewer decides it there.
In the report, list these items as "Needs Info: tester replied", so reviewers know to look. This is also what an
instant run does for the `Recheck Needs Info` work request.

### 2.3 Push to Jira
Kicksaw reviewers decide each item on the **UAT Review** tab (Create Jira ticket / Resolve without Jira / Needs info);
that sets the fields below. Point reviewers there after a triage run. On the card they can also set the tested story,
severity and proposed resolution. **Next** (→) saves those edits and a Bug / Enhancement / Training / Not a Bug
determination *without* requesting Jira, so an item can have `Kicksaw_Determination__c` set and
`Needs_Jira_Ticket__c = false`: it is still waiting for a decision; don't push it.

Pick up `Needs_Jira_Ticket__c = true AND JIRA_Ticket_URL__c = null AND Kicksaw_Determination__c IN ('Bug','Enhancement')`.
Only bugs and enhancements go to Jira; everything else is resolved in Salesforce with a Final Resolution.
- Bug → Sub-task of the tested story, summary `<Subtask_Prefix__c> <item summary>`. A bug needs a tested story first
  (UAT Review enforces it). If the project lead chose linked Tasks instead (setup table), create a Task linked to the
  story.
- Enhancement → Story in the project, in the Future Phase sprint. If `Future_Phase_Sprint_ID__c` is blank: in the
  backlog, with the extra label `future-phase` (Fallbacks, 0b).
- If the project has no Sub-task type, use the linked-Task fallback for bugs without asking again.
- Label `UAT_Label__c`. Description: item number, link to the Salesforce record, reasoning and repro steps.
  **Never copy client record data into Jira**; link to it.
- Set `JIRA_Ticket_URL__c`, `Jira_Status__c`, `Jira_Sync_Status__c = Created`, `Status__c = In Progress`.
  On failure: `Jira_Sync_Status__c = Failed` and report it.

### 2.3b Reopen Jira tickets after a failed retest
When a tester records **Retest Result > It is still wrong** (app 0.4.0 and later), the same item is reopened: `Status__c =
In Progress`, `Jira_Sync_Status__c = 'Reopen Requested'`, `Retest_Failed_At__c` = when, and the tester's words are
added to `Retest_Notes__c`. Pick up `Jira_Sync_Status__c = 'Reopen Requested' AND JIRA_Ticket_URL__c != null`:
1. Add a comment on the Jira ticket: "UAT retest failed on <date>." then one or two sentences in your own words on
   what is still wrong, and the link to the Salesforce record. **Never paste the tester's note or client record data.**
2. Move the ticket back to a working status: list its transitions and take the one that leads to a status mapped to
   In Progress (prefer one named Reopen, In Progress or To Do). If the workflow has no way back, leave the ticket,
   say so in the comment, and list it in the report for the project lead.
3. Set `Jira_Status__c` to the ticket's status now and `Jira_Sync_Status__c = Created`. On failure:
   `Jira_Sync_Status__c = Failed` and report it. Leave `Status__c` at In Progress.
An item with no Jira ticket (rare): just set `Jira_Sync_Status__c` back to blank and list it for a reviewer.

### 2.4 Sync status and comments back
For items with a Jira ticket that aren't closed: store the Jira status in `Jira_Status__c`, set `Status__c` from
`Status_Mapping__c` (a status the mapping doesn't list: always store it in `Jira_Status__c`, apply the category
fallback in 0b, and list the item and the status in the report under "Jira status not in the Status Mapping", with
the line to add; never skip it silently), and copy the ticket's latest comment into `Jira_Latest_Comment__c` as
"<author>, <date>: <text>" (plain text). Moving to Ready for Retest notifies the tester (flow).
**After a failed retest** (`Retest_Failed_At__c` is filled): only move the item to Ready for Retest again when the
ticket reached its done status *after* `Retest_Failed_At__c` (compare Jira's status-category change date). A ticket
that is still Done from before the failed retest keeps the item In Progress. Never touch an item whose
`Jira_Sync_Status__c` is `Reopen Requested`; 2.3b handles it first.
Closing after a retest is the tester's own step: **Retest Result > It works now** sets Resolved with a Final
Resolution line. Reviewers can use the same action for a tester.

## 3. Report
End every run with a short summary: app version (current / upgrade available), utility bar check (apps OK / re-added / still missing), stories synced, items triaged by proposed classification, Needs Info items the tester replied to, items waiting for a
Kicksaw decision, Jira tickets created (keys) and failures, items ready for retest, retests that failed and their Jira tickets reopened, Jira statuses not in the Status Mapping, and open Blocker/High items
(go-live risk). Point to the **UAT Feedback Dashboard** for the live view. At the end of UAT, list anything still open;
the contract's acceptance window covers unraised issues.

## 4. Scheduling (Triage_Schedule__c)
| Setting | How it runs |
| --- | --- |
| Manual | Someone runs `/kicksaw-uat <project>` (e.g. after each UAT session). |
| On request | Tick `Instant_Runs_Enabled__c` and set `Routine_Trigger_Id__c`; new items and Needs Jira Ticket fire the routine through `UAT_Work_Request__e` and the `Claude_UAT_Triage` named credential. |
| Hourly / Every 4 hours / Daily | A Claude Code routine running this skill with cron `0 * * * *`, `0 */4 * * *` or `0 7 * * 1-5`. Turn it up during UAT and down after. |

**Setting up a routine** (when the person asks, or the schedule isn't Manual). Walk them through it one step at a
time and check each one. Never ask for or accept the login value or token in chat.
1. Integration user with `Kicksaw_UAT_App_Integration`; check its profile's login IP ranges. Needs the client's
   security sign-off on logins from Anthropic's cloud first.
2. On their machine: `sf org login web --instance-url <UAT org login URL> --alias uat-integration`, then
   `sf org display --target-org uat-integration --verbose --json`; they copy `sfdxAuthUrl` themselves.
3. claude.ai cloud environment `UAT triage - <project>`: setup script installs `@salesforce/cli` with npm if `sf` is
   missing; network allowlist `registry.npmjs.org`, the sandbox domain, `test.salesforce.com` (and the Jira site if
   not using the connector); secret `SF_AUTH_URL`.
4. Routine on that environment, owned by a named person, with the Atlassian connector and this skill, the cron from
   the table, and this prompt (fill in the key):
   ```
   /kicksaw-uat <KEY>
   Salesforce org: the UAT sandbox, logged in from $SF_AUTH_URL as alias "uat".
   Run steps 2.0 to 2.4 and the report (in 2.0 and 2.0b only report a new version or a missing utility bar item; don't deploy anything). Do not change any org other than alias "uat". Do not touch Production.
   ```
   In a routine run, log in first: `echo "$SF_AUTH_URL" > /tmp/auth && sf org login sfdx-url -f /tmp/auth -a uat && rm /tmp/auth`.
5. On request: add an API trigger; the person pastes the token into Setup > Named Credentials > External Credentials >
   UAT Triage > Principals (parameter `Token`), sets the UAT Work Request subscription's running user to the
   integration user, then sets `Routine_Trigger_Id__c` and ticks `Instant_Runs_Enabled__c`.
6. Run it once by hand and check an item got triaged.

## Install for the team
The skill is plain instructions and works in any coding agent that can run `sf` and reach Jira (Atlassian MCP or API).
- **Claude Code:** copy `skills/kicksaw-uat` from https://github.com/iandevlin-pixel/kicksaw-uat-app to `~/.claude/skills/` (or save this skill to your claude.ai account), then `/kicksaw-uat <project>`.
- **Codex (or another agent that reads `AGENTS.md`):** open the kicksaw-uat-app repo; `AGENTS.md` points to this file. Ask it to
  "run the kicksaw-uat skill for <project>", or copy the folder into that agent's skills directory if it has one.
Authenticate `sf` to the client org and have Jira access first.

## Future ideas (not built)
- **Group duplicate feedback under one Jira ticket:** when several testers report the same problem,
  link their items to one ticket instead of one ticket each (today: mark the others Duplicate of the first).
