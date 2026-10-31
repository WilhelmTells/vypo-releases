# Sourced by scripts/test.sh and scripts/glossary-benchmark.sh (not run on its own).
#
# Gives the test host a home of its own, so the Core ML (E5) cache it fills lands in
# build.noindex/test-home/Library/Caches/com.wilhelmtells.vypo/ and never in the installed vypo's
# ~/Library/Caches/com.wilhelmtells.vypo/. The test host is the real app with the same bundle ID, and the cache folder
# follows the bundle ID, so without this a test that loads the model could make your next real dictation recompile
# the encoder for 25 to 37 s. Only xcodebuild's test host sees the changed home (TEST_RUNNER_ prefix), not xcodebuild.
#
# The speech model and the benchmark recordings are still read from the real place: the scratch home links to
# ~/Library/Application Support/vypo. Tests only read there (see RunEnvironment); DEVELOPMENT.md has the check.
# The scratch cache stays between runs, so the first run that loads the model compiles it once (about 25 s).
vypo_test_home="$PWD/build.noindex/test-home"
mkdir -p "$vypo_test_home/Library/Application Support"
ln -sfn "$HOME/Library/Application Support/vypo" "$vypo_test_home/Library/Application Support/vypo"
export TEST_RUNNER_CFFIXED_USER_HOME="$vypo_test_home"
