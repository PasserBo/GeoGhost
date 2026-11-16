#!/bin/sh
# Renders the UI snapshots (ui/screen.yaml → ui/snapshots/) once per language.
#
#   scripts/ui-snapshots.sh verify   compare the app with the committed images; fails on any difference
#   scripts/ui-snapshots.sh record   throw the images away, render them again, then verify once
#
# The images depend on the simulator model and iOS version, so they are recorded and verified on
# the device named in ui/screen.yaml. Set SIMULATOR to a UDID to pick a specific one.
set -e
MODE=${1:-verify}
case "$MODE" in verify|record) ;; *) echo "usage: $0 verify|record" >&2; exit 2 ;; esac
cd "$(dirname "$0")/.."

DEVICE=$(ruby -ryaml -e 'puts YAML.load_file("ui/screen.yaml")["matrix"]["device"]["name"]')
LOCALES=$(ruby -ryaml -e 'puts YAML.load_file("ui/screen.yaml")["matrix"]["locales"]')
if [ -n "$SIMULATOR" ]; then DESTINATION="platform=iOS Simulator,id=$SIMULATOR"; else DESTINATION="platform=iOS Simulator,name=$DEVICE"; fi

region() {
  ruby -ryaml -e 'puts YAML.load_file("ui/screen.yaml")["matrix"]["regions"].fetch(ARGV[0])' "$1"
}

run() { # run <language> [extra xcodebuild settings…]
  lang=$1; shift
  xcodebuild test-without-building -quiet -project GeoGhost.xcodeproj -scheme GeoGhost \
    -destination "$DESTINATION" -derivedDataPath build/DerivedData \
    -only-testing:GeoGhostTests/UISnapshotTests -testLanguage "$lang" -testRegion "$(region "$lang")" "$@"
}

xcodegen generate >/dev/null
xcodebuild build-for-testing -quiet -project GeoGhost.xcodeproj -scheme GeoGhost \
  -destination "$DESTINATION" -derivedDataPath build/DerivedData

if [ "$MODE" = record ]; then
  mkdir -p ui/snapshots
  rm -f ui/snapshots/*.png
  for lang in $LOCALES; do
    echo "== recording $lang"
    # Recording reports every image as a failure; the verify pass below is what counts.
    TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all run "$lang" >/dev/null 2>&1 || true
  done
  echo "recorded $(ls ui/snapshots/*.png 2>/dev/null | wc -l | tr -d ' ') images"
fi

failed=0
for lang in $LOCALES; do
  echo "== verifying $lang"
  run "$lang" || failed=1
done
if [ $failed -ne 0 ]; then
  echo "UI snapshots differ from ui/snapshots/. If the change is intended, run: scripts/ui-snapshots.sh record" >&2
  exit 1
fi
echo "UI snapshots match."
