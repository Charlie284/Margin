# Release checklist

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the app and Quick Look targets.
2. Run the unit suite, UI smoke test, and static analyzer on the release commit. On macOS, grant
   Xcode UI-automation permission if the runner reports that it timed out enabling automation mode.
3. Confirm the universal Release contains both `arm64` and `x86_64` slices.
4. Store notarization credentials with `notarytool store-credentials` in the release keychain.
5. Run `scripts/release.sh` with `DEVELOPMENT_TEAM` and `NOTARY_PROFILE` set.
6. Install the resulting ZIP on a clean macOS 15 account and verify opening, saving, PDF export, Quick Look, workspace search, and the installed CLI.
7. Verify an upgrade from the previous release without removing documents, bookmarks, or preferences.
8. Keep the signed archive, notarization log, checksums, and rollback ZIP with the release record.
