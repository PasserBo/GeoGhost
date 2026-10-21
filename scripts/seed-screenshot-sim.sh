#!/bin/sh
# Fresh-installs the Debug build on a simulator, seeds it from a curated GeoGhost export in the given
# language, and waits until series matching has settled. Used for App Store screenshots.
# Usage: scripts/seed-screenshot-sim.sh <simulator-udid> <seed-dir> <lang> <locale>
#   e.g. scripts/seed-screenshot-sim.sh EA409F29-… AppStoreScreenshots/seed ja ja_JP
set -e
U=$1; SEED=$(cd "$2" && pwd); LANG_CODE=$3; LOCALE=$4
APP="$(dirname "$0")/../build/DerivedData/Build/Products/Debug-iphonesimulator/GeoGhost.app"
LOG=$(mktemp -t geoghost-seed)
xcrun simctl terminate "$U" com.passerbo.geoghost 2>/dev/null || true
xcrun simctl uninstall "$U" com.passerbo.geoghost
xcrun simctl install "$U" "$APP"
xcrun simctl privacy "$U" grant location com.passerbo.geoghost
xcrun simctl launch --console-pty "$U" com.passerbo.geoghost -seedExport "$SEED" -AppleLanguages "($LANG_CODE)" -AppleLocale "$LOCALE" > "$LOG" 2>&1 &
until grep -q "imported" "$LOG" 2>/dev/null; do sleep 2; done
STORE=$(find "$(xcrun simctl get_app_container "$U" com.passerbo.geoghost data)/Library/Application Support" -name GeoGhost.store)
prev=""; same=0
# Settled = series count, pieces in series and feature count unchanged for 30 s.
until [ $same -ge 6 ]; do
  cur=$(sqlite3 "$STORE" "select count(*) from ZARTSERIES; select count(*) from ZARTWORK where ZSERIES is not null; select sum(ZLOCALFEATURES is not null) from ZARTWORK;" | tr '\n' ' ')
  if [ "$cur" = "$prev" ]; then same=$((same+1)); else same=0; prev="$cur"; fi
  sleep 5
done
echo "settled: series, pieces in series, pieces with features = $prev"
