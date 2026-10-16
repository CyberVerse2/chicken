# Release Process

Chicken ships as one App Store app (universal purchase) for macOS, iPadOS, and iOS, bundle ID `cyberverse.Chicken`, team `V6Y7WXX6Z5`. The widget is `cyberverse.Chicken.widget`; both share the App Group `group.cyberverse.Chicken`. The app syncs through the iCloud container `iCloud.cyberverse.Chicken` (CloudKit for the database, iCloud Documents for book files and covers).

## Versioning

`MARKETING_VERSION` in `Chicken.xcodeproj` is the user-facing version (semantic, e.g. `2.0.0`). Bump `CURRENT_PROJECT_VERSION` for every upload to App Store Connect.

## App Store

1. In App Store Connect, create the app record for `cyberverse.Chicken` with iOS and macOS platforms.
2. In Xcode, select the **Chicken** scheme and archive once per platform: **Any Mac** and **Any iOS Device**. Automatic signing creates the provisioning profiles, the App Group, and the widget's identifiers on first archive.
3. Distribute each archive with **App Store Connect › Upload**, then submit both platform versions for review.

Before the first submission:

- Check the sandbox entitlements in `Config/Chicken-macOS.entitlements`. `network.client` is there because WebKit's EPUB renderer needs it; Chicken's only network use is iCloud sync. Say so in the review notes if asked.
- Privacy details: no data collected. Books and reading data sync through the user's own iCloud account, which Apple doesn't count as collection by the developer.
- In the [CloudKit Console](https://icloud.developer.apple.com), deploy the development schema for `iCloud.cyberverse.Chicken` to production. Debug builds create and update the schema as they sync; release builds can't, so do this again whenever a model or a property is added (most recently: `ReadingPosition`, `BookCollection`, `Book.positions`, `Book.collections`, `ReadingDay.device`).
- Test the Mac upgrade path by installing a signed build on a machine that has a Chicken 1.x library. The first launch should show "Brought over N books…" in the library.

## GitHub Releases

Version tags (`v2.0.0`) trigger `.github/workflows/release.yml`. It runs the core tests, archives the Mac app, and publishes **unsigned** `.zip` and `.dmg` files with SHA-256 checksums. These are for testing only. A Developer ID–signed, notarized DMG would need these repository secrets:

- Developer ID Application certificate (`.p12`) and its password
- App Store Connect API key ID, issuer ID, and private key (for `notarytool`)

```sh
git tag v2.0.0
git push origin v2.0.0
```

The tag must match `MARKETING_VERSION`.
