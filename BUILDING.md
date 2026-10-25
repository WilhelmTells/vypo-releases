# Building vypo

vypo is a macOS menu bar app, built with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Requirements

- Apple silicon Mac, macOS 26 or later
- Xcode 26 or later
- Homebrew and XcodeGen: `brew install xcodegen`

## Build and test

```sh
scripts/test.sh          # generates the Xcode project, builds vypo and runs the unit tests
scripts/install.sh       # builds a Release copy and installs it as /Applications/vypo.app
```

`xcodegen generate` creates `vypo.xcodeproj` from `project.yml`; the project file is not checked in.

## Signing

Put your own Apple Developer team ID in `Config/Local.xcconfig` (git ignores it):

```sh
echo 'DEVELOPMENT_TEAM = ABCDE12345' > Config/Local.xcconfig
```

`security find-identity -v -p codesigning` shows it as the OU of your “Apple Development” certificate.

## Official builds

Official builds come from [wilhelmtells.com/vypo](https://wilhelmtells.com/vypo). Build this source yourself
if you want to read, check or change what runs on your Mac.

## Forks

If you distribute your own version:

- Change the bundle ID (`PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, currently `com.wilhelmtells.vypo`).
- Set your own `SUFeedURL` and `SUPublicEDKey` (Sparkle updates) in `project.yml`, or remove the update
  settings. The values in this repository belong to the official builds; an app that points at them would
  update to the official one.
- Use your own artwork, name and icon. See `LICENSE-ARTWORK.md`.

The code is under the GPL-3.0 (`LICENSE`). Third-party components are listed in `THIRD_PARTY_NOTICES.md`.
