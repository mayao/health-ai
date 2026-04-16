#!/bin/bash
set -euo pipefail

MODE=${1:-testflight}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAM_ID=${DEVELOPMENT_TEAM:-J32AD5KDR3}
ARCHIVE_PATH=${ARCHIVE_PATH:-build/VC.xcarchive}
EXPORT_PATH=${EXPORT_PATH:-build/ipa}
PROJECT_PATH=${PROJECT_PATH:-VitalCommandIOS.xcodeproj}
SCHEME=${SCHEME:-VitalCommandIOS}

usage() {
  cat <<'EOF'
Usage:
  ./build-ipa.sh [mode]

Modes:
  testflight         Archive and upload to App Store Connect (default)
  testflight-upload  Same as testflight
  testflight-export  Archive and export an .ipa locally for manual upload
  appstore-export    Same as testflight-export
  adhoc              Archive and export an ad-hoc build locally

Environment overrides:
  DEVELOPMENT_TEAM
  ARCHIVE_PATH
  EXPORT_PATH
  PROJECT_PATH
  SCHEME
  EXPORT_OPTIONS_PLIST
EOF
}

case "$MODE" in
  testflight|testflight-upload)
    EXPORT_OPTIONS_PLIST=${EXPORT_OPTIONS_PLIST:-ExportOptions-testflight.plist}
    ;;
  testflight-export|appstore-export)
    EXPORT_OPTIONS_PLIST=${EXPORT_OPTIONS_PLIST:-ExportOptions-appstore-export.plist}
    ;;
  adhoc)
    EXPORT_OPTIONS_PLIST=${EXPORT_OPTIONS_PLIST:-ExportOptions-adhoc.plist}
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    echo "" >&2
    usage >&2
    exit 1
    ;;
esac

cd "$SCRIPT_DIR"

echo "=== Archiving VitalCommandIOS ==="
echo "Project: $PROJECT_PATH"
echo "Scheme:  $SCHEME"
echo "Mode:    $MODE"
echo "Team:    $TEAM_ID"
echo "Archive: $ARCHIVE_PATH"
echo "Export:  $EXPORT_PATH"
echo "Options: $EXPORT_OPTIONS_PLIST"

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo ""
echo "=== Exporting archive ==="
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

echo ""
echo "✅ Export completed"
echo "Archive: $SCRIPT_DIR/$ARCHIVE_PATH"
echo "Export:  $SCRIPT_DIR/$EXPORT_PATH"

if [ "$MODE" = "testflight" ] || [ "$MODE" = "testflight-upload" ]; then
  echo ""
  echo "Upload request has been handed to xcodebuild/App Store Connect."
  echo "After processing finishes in App Store Connect, add the build to an external group"
  echo "and submit that group for TestFlight App Review."
elif [ "$MODE" = "testflight-export" ] || [ "$MODE" = "appstore-export" ]; then
  echo ""
  echo "Local export only. You can upload the generated .ipa using Xcode Organizer or Transporter."
fi
