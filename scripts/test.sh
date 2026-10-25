#!/bin/zsh
# Runs the unit tests (extra xcodebuild arguments pass through, e.g. -only-testing:vypoTests/LevelTests)
# and fails if a vypo other than /Applications/vypo.app is still running afterwards: a test host
# must never linger, since it would hold the microphone or the Dock.
set -uo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
# build.noindex keeps Spotlight from listing the test host as another vypo.
xcodebuild -project vypo.xcodeproj -scheme vypo -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build.noindex/dd test "$@"
result=$?

# Tests keep their preferences in suites called vypo.<name>.<id> (one plist each in ~/Library/Preferences); the app's
# own are com.wilhelmtells.vypo. Thousands piled up, so they go after every run.
find "$HOME/Library/Preferences" -maxdepth 1 -name 'vypo.*.plist' -delete 2>/dev/null

# The runner ends the test host itself; give it a moment.
# By executable path, so a shell whose command line mentions vypo doesn't count.
strays() { ps -axo pid=,comm= | awk '$2 ~ /\/vypo\.app\/Contents\/MacOS\/vypo$/ && $2 !~ /^\/Applications\//' | grep . }
for _ in {1..10}; do strays >/dev/null || break; sleep 0.5; done
if strays >/dev/null; then
  echo "error: vypo processes left after the tests:" >&2
  strays >&2
  strays | awk '{print $1}' | xargs kill 2>/dev/null
  exit 1
fi
exit $result
