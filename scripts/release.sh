#!/bin/sh
# Builds, uploads and (optionally) submits an App Store release of the version in project.yml.
# Usage: scripts/release.sh [--submit] [--skip-tests]
#   1. tests (simulator $GEOGHOST_TEST_SIM, default the iPhone 17 Pro CDB94C9B…)
#   2. Release archive into Xcode's Archives folder, so it also shows in Organizer
#   3. upload with cloud signing, using the release API key
#   4. App Store Connect: wait for processing, create the version, What's New, attach the build
#   5. with --submit: submit for review
# What's New comes from scripts/release-notes/<version>.json ({ "<locale>": "<text>", … }, every locale
# the version has). Key and issuer: ~/.config/geoghost-release/config.json (see asc-release.mjs).
# App Privacy answers have no API: update them in App Store Connect before --submit when collected data changes.
set -e
cd "$(dirname "$0")/.."

SUBMIT=0; TESTS=1
for arg in "$@"; do
  case $arg in
    --submit) SUBMIT=1 ;;
    --skip-tests) TESTS=0 ;;
    *) echo "usage: scripts/release.sh [--submit] [--skip-tests]" >&2; exit 2 ;;
  esac
done

VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
BUILD=$(git rev-list --count HEAD)   # same as the build-number script in project.yml
NOTES=scripts/release-notes/$VERSION.json
CONFIG=$HOME/.config/geoghost-release/config.json
KEY_ID=$(plutil -extract keyId raw "$CONFIG")
ISSUER_ID=$(plutil -extract issuerId raw "$CONFIG")
KEY_PATH=$HOME/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%F)/GeoGhost $VERSION ($BUILD).xcarchive"

[ -f "$NOTES" ] || { echo "Missing $NOTES (What's New per locale)." >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Uncommitted changes; the build number must match a commit." >&2; exit 1; }
echo "Releasing GeoGhost $VERSION ($BUILD) from $(git rev-parse --short HEAD)"

xcodegen generate

if [ $TESTS = 1 ]; then
  xcodebuild test -project GeoGhost.xcodeproj -scheme GeoGhost -quiet \
    -destination "platform=iOS Simulator,id=${GEOGHOST_TEST_SIM:-CDB94C9B-15A9-4BFF-B2AE-0E069417B4F9}"
fi

mkdir -p "$(dirname "$ARCHIVE")"
xcodebuild archive -project GeoGhost.xcodeproj -scheme GeoGhost -configuration Release -quiet \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates

EXPORT=$(mktemp -d -t geoghost-export)
cat > "$EXPORT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>J95TRWHWYM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT/ExportOptions.plist" \
  -exportPath "$EXPORT" -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID"

node scripts/asc-release.mjs prepare "$VERSION" "$BUILD" "$NOTES"

if [ $SUBMIT = 1 ]; then
  node scripts/asc-release.mjs submit "$VERSION"
else
  echo "Uploaded and prepared $VERSION ($BUILD). Submit with: node scripts/asc-release.mjs submit $VERSION"
fi
