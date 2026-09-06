#!/usr/bin/env bash
# Build a Release Blather.app into dist/ (same layout as .github/workflows/release.yml).
#
# Usage:
#   ./scripts/build-release.sh
#   BLATHER_VERSION=0.2.0 BLATHER_BUILD_NUMBER=12 ./scripts/build-release.sh
#
# Signs with Developer ID when a certificate is in the keychain unless
# BLATHER_SIGNING=false. CI imports the cert before calling this script.
#
# After a signed export, notarizes (or staples a ticket already submitted from
# another computer / CI) unless BLATHER_NOTARIZE=false. Import credentials from
# another Mac with: bun run signing:import

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=signing-env.sh
source "$ROOT/scripts/signing-env.sh"
load_signing_env

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
	VERSION="${BLATHER_VERSION:-${GITHUB_REF_NAME#v}}"
else
	VERSION="${BLATHER_VERSION:-$(bun -e "console.log(JSON.parse(await Bun.file('package.json').text()).version)")}"
fi
BUILD="${BLATHER_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
TEAM="${APPLE_TEAM_ID:-$(bun -e "console.log(JSON.parse(await Bun.file('release.json').text()).development_team)")}"

echo "Blather ${VERSION} (${BUILD})"

bun scripts/set-versions.ts "$VERSION" "$BUILD"

if ! command -v xcodegen >/dev/null; then
	echo "Installing xcodegen..."
	brew install xcodegen
fi
xcodegen generate

mkdir -p dist
ARCHIVE="${ROOT}/dist/Blather.xcarchive"
EXPORT_DIR="${ROOT}/dist/export"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "${ROOT}/dist/Blather.app"

identity=""
if [[ "${BLATHER_SIGNING:-}" != "false" ]]; then
	identity="$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi

xcodebuild_common=(
	archive
	-project Blather.xcodeproj
	-scheme Blather
	-configuration Release
	-destination "generic/platform=macOS"
	-archivePath "$ARCHIVE"
	"MARKETING_VERSION=${VERSION}"
	"CURRENT_PROJECT_VERSION=${BUILD}"
)

if [[ -n "$identity" ]]; then
	echo "Archiving with ${identity}"
	xcodebuild "${xcodebuild_common[@]}" \
		"DEVELOPMENT_TEAM=${TEAM}" \
		CODE_SIGN_STYLE=Manual \
		"CODE_SIGN_IDENTITY=Developer ID Application"

	cat > dist/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>${TEAM}</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
</dict>
</plist>
EOF

	echo "Exporting Developer ID app"
	xcodebuild -exportArchive \
		-archivePath "$ARCHIVE" \
		-exportPath "$EXPORT_DIR" \
		-exportOptionsPlist dist/ExportOptions.plist
	mv "${EXPORT_DIR}/Blather.app" dist/Blather.app
	echo "Notarizing dist/Blather.app"
	bash "$ROOT/scripts/notarize.sh" "${ROOT}/dist/Blather.app"
else
	echo "Archiving unsigned (no Developer ID identity, or BLATHER_SIGNING=false)"
	xcodebuild "${xcodebuild_common[@]}" \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_ALLOWED=NO
	cp -R "${ARCHIVE}/Products/Applications/Blather.app" dist/Blather.app
fi

plutil -extract CFBundleShortVersionString raw dist/Blather.app/Contents/Info.plist
plutil -extract CFBundleVersion raw dist/Blather.app/Contents/Info.plist
echo "Release app ready at dist/Blather.app"
