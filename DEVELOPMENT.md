# Development

## Signing

`build.sh` signs with a self-signed code signing certificate named **ISOFix Signing** when your keychain has one, and ad-hoc otherwise. With the certificate, macOS keeps the Input Monitoring grant across rebuilds. To make it: **Keychain Access → Certificate Assistant → Create a Certificate**, Identity Type **Self Signed Root**, Certificate Type **Code Signing**.

## Release

Push an annotated tag that matches `CFBundleShortVersionString` in `Info.plist`, for example `git tag -a v1.1 -m "<release notes>"`. The tag message becomes the release notes. The Release workflow builds `ISOFix.zip` and publishes it as a GitHub release. To sign release builds with the same certificate, export it as a `.p12` and add two repository secrets: `SIGNING_CERT_P12` (the file, base64) and `SIGNING_CERT_PASSWORD`. Then update `version` and `sha256` in [spacecakes/homebrew-tap](https://github.com/spacecakes/homebrew-tap).
