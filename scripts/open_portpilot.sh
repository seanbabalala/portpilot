#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/PortPilot.xcodeproj"
XCODE_APP="/Applications/Xcode.app"

if [[ ! -d "$XCODE_APP" ]]; then
  echo "Xcode not found at $XCODE_APP"
  echo "Please finish installing Xcode first."
  exit 1
fi

sudo xcode-select -s "$XCODE_APP/Contents/Developer"

if ! /usr/bin/xcodebuild -license check >/dev/null 2>&1; then
  echo "Please open Xcode once and accept the license agreement, then rerun this script."
  exit 1
fi

open "$PROJECT_PATH"

echo "Opened: $PROJECT_PATH"
echo "In Xcode, choose scheme 'PortPilot' and press ⌘R."
