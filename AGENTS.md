# Kicksaw UAT App: agent instructions

This file is for any coding agent (Codex, Claude Code, others). `CLAUDE.md` points here, so both read the same thing.

## Running UAT for a project
Follow **`skills/kicksaw-uat/SKILL.md`**: setup, story sync, triage, Jira, status sync and reporting. The person
names the project; the skill finds the Jira project, the Salesforce org and the settings.

## Rules
- Work only in the sandbox the person names. **Never change a production org** (metadata, data, settings, users)
  without the person's explicit yes for that change.
- Validate before deploying: `sf project deploy validate ...` (or `--dry-run`), then deploy.
- Install / upgrade the app from a tagged release with `manifest/uat-app.xml` (no profiles, no settings records),
  running only the app's tests; deploy only at setup or when a newer release exists. Releases: `release/README.md`.
- Don't put client data, org IDs, usernames, record IDs or sandbox URLs in this repo or in Jira; link to records.
- Nothing users see should name an AI product: write "triage". Legacy API names containing `Claude` stay as they are
  (see README).

## Repo
- Salesforce source: `force-app/main/default` (API 62). Review UI: `lwc/uatReview` + `classes/UatReviewController`.
- LWC tests: `npx sfdx-lwc-jest` (needs a current `@salesforce/sfdx-lwc-jest`; the pinned 0.10 can't compile
  `lwc:if`). Apex tests: `UatReviewControllerTest`.
