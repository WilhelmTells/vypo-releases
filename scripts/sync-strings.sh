#!/bin/sh
# Builds vypo and merges every string the compiler found into vypo/Localizable.xcstrings
# (Xcode does this itself; xcodebuild doesn't). New strings then need a German translation:
# LocalizationTests fails until each has one.
set -e
cd "$(dirname "$0")/.."
xcodebuild -project vypo.xcodeproj -scheme vypo -destination 'platform=macOS,arch=arm64' build -quiet
objroot=$(xcodebuild -project vypo.xcodeproj -scheme vypo -showBuildSettings 2>/dev/null | awk -F' = ' '/ OBJROOT /{print $2; exit}')
set --
for f in $(find "$objroot" -path '*/vypo.build/Objects-normal/*' -name '*.stringsdata'); do
    set -- "$@" --stringsdata "$f"
done
xcrun xcstringstool sync vypo/Localizable.xcstrings "$@"
echo "Synced vypo/Localizable.xcstrings"
