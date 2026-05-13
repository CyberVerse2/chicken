# Release Process

Chicken releases are published from version tags. The release workflow builds the macOS app, packages a `.zip` and `.dmg`, writes SHA-256 checksums, and publishes a GitHub Release with generated notes.

## Versioning

Use semantic version tags:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The tag version must match `MARKETING_VERSION` in `Chicken.xcodeproj/project.pbxproj`. For example, `v1.0.0` requires `MARKETING_VERSION = 1.0.0`.

## Release Artifacts

The current GitHub release workflow publishes unsigned Mac Catalyst artifacts:

- `Chicken-<version>-macOS-unsigned.zip`
- `Chicken-<version>-macOS-unsigned.dmg`
- `Chicken-<version>-checksums.txt`

These are useful for source-driven open source releases and internal testing. Public end-user distribution should use a signed and notarized build.

## Signing And Notarization

Before using GitHub Releases as the primary public distribution channel, add Apple Developer signing and notarization secrets to the release workflow. Required production dependencies:

- Apple Developer certificate exported as a password-protected `.p12`
- Certificate password
- App-specific provisioning profile, if the target requires one
- App Store Connect API key ID
- App Store Connect issuer ID
- App Store Connect private key
- Apple Developer Team ID

Do not publish a signed release until the workflow verifies code signing, notarization, and stapling successfully.
