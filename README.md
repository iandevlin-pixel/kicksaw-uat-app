# Kicksaw UAT Testing Application

> **Kicksaw UAT App 0.4.0 (UAT App v2).** Source of truth for installs is the tagged release in
> [iandevlin-pixel/kicksaw-uat-app](https://github.com/iandevlin-pixel/kicksaw-uat-app), based on Kicksaw's original
> repo [Kicksaw-Consulting/internal-uat-application](https://github.com/Kicksaw-Consulting/internal-uat-application)
> (v1 and its install links live there, unchanged). Install with the `kicksaw-uat` skill (see "Install UAT App v2").

## Components 

* UAT Feedback Custom Object 
* Kicksaw UAT Application 
* UAT Reports
* UAT Dashboard 
* Kicksaw_UAT_App permission set
* Create UAT Feedback Item Flow 

# v2 (UAT feedback + AI triage + Jira)

v2 is built for projects that run UAT from scenarios outside Salesforce: testers log UAT Feedback from the utility
bar, an AI triage run checks it against the story's acceptance criteria, and Kicksaw pushes bugs and enhancements to Jira.
Test cases and test runs (v1) are still included and unchanged.

* **UAT Feedback**: tester section (type, severity, tested story, steps / expected / actual, files, captured page and
  record), triage (proposed resolution, repro steps, classification reasoning, last run), Kicksaw decision
  (determination incl. Training, needs Jira ticket, duplicate of, final resolution) and Jira (ticket URL, status, sync).
* **UAT Story**: the project's Jira stories, acceptance criteria and smoke test steps, loaded by the skill. Testers can
  pick one on the feedback form (optional); if they don't, triage suggests one (Story Suggested by Triage) and the
  reviewer confirms or changes it on UAT Review. A bug needs a story before it goes to Jira.
* **Kicksaw_UAT_Setting__mdt.Default**: Jira site, project, Story JQL, labels, Future Phase sprint, status mapping,
  Triage Schedule, Instant Runs. Set these per project.
* **Flows**: Create UAT Feedback Item (form), Before Save (fills the story's Jira URL), Request Triage (5 min after any
  new item), Request Work, Work Request Fire (calls the triage routine when Instant Runs is on), Create Jira Ticket.
* **Skill**: `skills/kicksaw-uat` runs the whole UAT process for any project: setup, story sync, triage, Jira, status sync and reporting. Name the project and it finds the rest. See its SKILL.md.
* **UAT Review** (tab, `uatReview` LWC + `UatReviewController`): Kicksaw reviewers go through feedback one item at a time ("3 of 15"), see the tester's report and the triage proposal, and decide: Create Jira ticket (Bug / Enhancement), Resolve without Jira (Training, Not a Bug, Duplicate, Won't Do, with a Final Resolution), or Needs info (back to the tester). No "mark all": every item gets its own decision. Needs the UAT_Kicksaw_Reviewer custom permission (Kicksaw_UAT_App).
  * Everything a Jira ticket needs is on the card: determination, tested story, severity and the proposed resolution (a text box that grows with its text). The record page's Create Jira Ticket action still works but isn't needed for review.
  * The card fills the window; on small screens it falls back to normal page scrolling.
  * Moving: **Back** (←), **Skip** (S, no save), **Next** (→, saves the card's story / severity / proposal / determination and moves on; the item stays in To review until it's acted on). **J** creates the Jira ticket, **Enter** saves the decision. Keys work when the cursor isn't in a text box.
  * Mouse wheel over the blue header, progress bar or item header flips to the previous / next item (one flick = one item, like Skip). If the card has unsaved edits the wheel stops and asks for Next or Skip.
* **Dashboard**: UAT Feedback Dashboard (KicksawUAT folder), shown on the app home page: waiting for triage, needs Kicksaw decision, in Jira, ready for retest, open items by status / severity / story, determinations and Jira sync.
* **App navigation**: Home, UAT Review, UAT Feedback, UAT Stories, Dashboards, Reports. Test cases and test runs (v1) are still in the package but off the navigation and utility bar; add their tabs back for projects that use them.

Deploy: `sf project deploy start -d force-app -o <alias>` (API 62). Assign Kicksaw_UAT_App (Kicksaw reviewers),
Kicksaw_UAT_App_End_User (testers) and Kicksaw_UAT_App_Integration (the integration user for routine runs); the skill's
setup asks which users are which and assigns them. Put the **New UAT Feedback** utility item (flow
`Create_UAT_Feedback_Item`) on the utility bar of every app the testers test in, so they can report from where they are.
The form has Type, Severity, Tested Story (optional), Expected / Actual, Steps, files, and captures the current page and record.

**AI-agnostic:** nothing users see names an AI product. Some API names still contain `Claude` (renaming them needs a
data migration): fields `Claude_Proposed_Resolution__c`, `Claude_Classification_Reasoning__c`, `Claude_Repro_Steps__c`,
`Has_Claude_Proposal__c`, `Story_Suggested_by_Claude__c`; list view and report `UAT_Waiting_for_Claude`; named and
external credential `Claude_UAT_Triage` (principal `Claude_Principal`); external service `ClaudeUATTriage`; flow element
`Set_Has_Claude_Proposal`. The triage skill works from Claude Code or Codex (`AGENTS.md` / `CLAUDE.md` point to it).

**Version 0.4.0 (Nov 2026):** easier for other projects. Testers record a retest themselves with **Retest Result** on the item (flow `UAT_Retest_Result`): *It works now* closes it as Resolved; *It is still wrong* reopens the same item (In Progress, Jira Sync Status = Reopen Requested, the note goes to Retest Notes) and the next skill run reopens the Jira ticket. New fields `Retest_Notes__c`, `Retest_Failed_At__c`. Skill: readiness check (`/kicksaw-uat <project> check`), acceptance criteria read from the Jira Acceptance Criteria field, Status Mapping built from the project's own Jira statuses, fallbacks (no future-phase sprint, no Sub-task type, unmapped statuses), Needs Info recheck.
**Version 0.3.2 (Nov 2026):** tester notifications: email by address and skipped when there is none (no flow error emails); setup sets the channel (App).
**Version 0.3.1 (Nov 2026):** two flow fixes found installing over v1 (Test Run - After Save, UAT Feedback - Notify Tester).
**Version 0.3 (Nov 2026):** UAT Review fills the window, auto-growing text boxes, Back / Skip / Next (saves) with
← / S / →, mouse-wheel flipping, severity on the card; skill setup asks who tests and who reviews; AGENTS.md for Codex.

**Future ideas (not built):** group duplicate feedback from several testers under one Jira ticket.
Settings ship blank: the `kicksaw-uat` skill fills `Kicksaw_UAT_Setting.Default` for each project (Jira project, Story JQL, Future Phase sprint).

# Install UAT App v2

**Easiest:** run the skill and say install: `/kicksaw-uat <project>` → "install the UAT app in <org alias>". It checks
whether the org is a sandbox or production, whether the app is already there (and which version), then deploys the
latest tagged release from this repo, stamps the version in the org, and walks through settings and asks which users
are testers and reviewers. Production always needs an explicit yes first. It deploys only at setup and when a newer
release exists, never on routine runs.

**By hand** (same steps the skill runs; `<tag>` = `latest.tag` in `skills/kicksaw-uat/install-versions.json`):
```bash
git clone --depth 1 --branch <tag> https://github.com/iandevlin-pixel/kicksaw-uat-app.git && cd kicksaw-uat-app
sf project deploy validate -o <alias> --manifest manifest/uat-app.xml --test-level RunSpecifiedTests \
  --tests UatReviewControllerTest --tests TestManagementControllerTest --tests NavigationServiceControllerTest --tests multiselectToCollection_Test
sf project deploy quick -o <alias> --job-id <validated id>
sf project deploy start -o <alias> --manifest manifest/first-install.xml   # first install only (blank settings)
```
Then set `Installed_Version__c` on Kicksaw UAT Setting `Default` to "<version> (<tag>)".

- `manifest/uat-app.xml` leaves out profiles and the settings records, so a redeploy never overwrites a project's
  settings or the client's profiles. Access comes from the app's permission sets.
- `release/<tag>/destructiveChanges.xml` lists what a release removes (empty for v0.3.0). See `release/README.md`.
- An unlocked package (one-click install links for sandbox and production) is optional for later; its IDs would go in
  `install-versions.json` under `package`.

# Share this skill with the Kicksaw team

The `kicksaw-uat` skill is for any Kicksaw project; nothing client-specific is in it (each project's values live in
that org's Kicksaw UAT Setting). The folder `skills/kicksaw-uat/` is self-contained (`SKILL.md` +
`install-versions.json`). To use it:
- **Claude Code:** copy `skills/kicksaw-uat` into `~/.claude/skills/`, then `/kicksaw-uat <project>`.
- **Codex** (or another agent that reads `AGENTS.md`): open this repo; `AGENTS.md` points to the skill.
- **Whole company:** an org admin can add the folder as an organization skill in claude.ai so every consultant has it.

# Scratch Org/Development 

## Setup 
* Install [VSCode](https://code.visualstudio.com/) and the  [Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.208.0.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm) if you haven't already done so

 * Git Clone this repo

 * Spin up new scratch org and deploy metadata by running the following in terminal: 

    ```sh scripts/Initial_Deploy.sh```

Wait for the prompt and then enter the alias of the scratch org you want to create and press ```Enter```

The Kicksaw_UAT_Permission set should automatically be assigned to the scratch org user. 

# v1 install (legacy, Kicksaw-Consulting repo)
v2 installs with the `kicksaw-uat` skill from this repo (see "Install UAT App v2"); the button below deploys the old v1
from Kicksaw's original repo. Use the following instructions for v1 in client orgs for UAT testing. 
 ### Instructions 
 * Click the install button below below. 
 * Assign the Kicksaw_UAT_App permission set to the users who should have access to objects/application
 * Add the Create UAT Feedback Item flow as a utility item in the customers primary App
 


<a href="https://githubsfdeploy-sandbox.herokuapp.com/app/githubdeploy/Kicksaw-Consulting/internal-uat-application">
  Deploy to Sandbox
</a>


