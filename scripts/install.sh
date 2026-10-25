#!/bin/zsh
# Builds vypo (Release), quits every running copy, replaces /Applications/vypo.app and launches only that.
set -euo pipefail
cd "$(dirname "$0")/.."

# .noindex keeps Spotlight from listing the build products as more copies of vypo.
BUILD_DIR="$PWD/build.noindex"
xcodegen generate
xcodebuild -project vypo.xcodeproj -scheme vypo -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD_DIR" build

# Every running copy, wherever it was launched from (Xcode, DerivedData, an old build).
osascript -e 'quit app id "com.wilhelmtells.vypo"' 2>/dev/null || true
for _ in {1..10}; do pgrep -f '/vypo.app/Contents/MacOS/vypo' >/dev/null || break; sleep 0.5; done
pkill -f '/vypo.app/Contents/MacOS/vypo' 2>/dev/null || true

rm -rf /Applications/vypo.app
cp -R "$BUILD_DIR/Build/Products/Release/vypo.app" /Applications/vypo.app
# Only /Applications stays registered with Launch Services, so “Open with” and login start this copy.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$BUILD_DIR/Build/Products/Release/vypo.app" 2>/dev/null || true
"$LSREGISTER" -f /Applications/vypo.app
open -a /Applications/vypo.app
echo "Installed /Applications/vypo.app"
