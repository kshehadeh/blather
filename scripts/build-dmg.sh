#!/usr/bin/env bash
# Build a drag-and-drop DMG containing Blather.app and an /Applications symlink.
#
# Usage:
#   ./scripts/build-dmg.sh
#
# Requires: dist/Blather.app already built (run scripts/build-release.sh first).
# Produces: dist/Blather.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="${DIST}/Blather.app"
DMG="${DIST}/Blather.dmg"

if [[ ! -d "${APP}" ]]; then
	echo "Error: ${APP} not found. Run scripts/build-release.sh first." >&2
	exit 1
fi

echo "Building DMG: ${DMG}"
rm -f "${DMG}"

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

cp -R "${APP}" "${STAGING}/Blather.app"
ln -s /Applications "${STAGING}/Applications"

SIZE_BYTES=$(du -sk "${STAGING}" | awk '{print $1 * 1024}')
SIZE_BYTES=$((SIZE_BYTES + 10 * 1024 * 1024))

hdiutil create \
	-volname "Blather" \
	-srcfolder "${STAGING}" \
	-ov \
	-format UDZO \
	-size "${SIZE_BYTES}"b \
	"${DMG}"

echo "Built ${DMG}"
