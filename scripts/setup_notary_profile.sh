#!/usr/bin/env bash

set -euo pipefail

PROFILE_NAME="${1:-PortPilotNotary}"

echo "==> Storing notary credentials in Keychain profile: $PROFILE_NAME"
echo "You will be prompted for Apple ID / app-specific password / team ID if omitted."

xcrun notarytool store-credentials "$PROFILE_NAME" --validate

echo
echo "Done. Use profile '$PROFILE_NAME' with scripts/package_notarized_release.sh"
