# Releases

Each release is a git tag `vX.Y.Z` and a folder `release/vX.Y.Z/`.

- `destructiveChanges.xml`: components this release deletes from orgs upgrading from an older version (often empty).
  The kicksaw-uat skill deploys it, after the main deploy, only when the org's stamped version is older.
- To cut a release: bump `version` in `skills/kicksaw-uat/install-versions.json` and `sfdx-project.json`, add
  `release/vX.Y.Z/`, update `manifest/uat-app.xml` if components were added (`sf project generate manifest
  --source-dir force-app`, then remove `CustomMetadata`), commit, tag `vX.Y.Z`, push the tag and create a GitHub release.
