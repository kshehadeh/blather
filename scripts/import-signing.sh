#!/usr/bin/env bash
# Import a Developer ID Application .p12 and store notarytool credentials.
#
# Intended for a Mac that does not yet have the cert (it was created / exported
# on a different computer). Reads CSC_LINK + CSC_KEY_PASSWORD from the
# environment or from gitignored .env.signing (see .env.signing.example).
#
# Usage:
#   bun run signing:import
#   ./scripts/import-signing.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=signing-env.sh
source "$ROOT/scripts/signing-env.sh"
load_signing_env

if [[ -z "${CSC_LINK:-}" || -z "${CSC_KEY_PASSWORD:-}" ]]; then
	cat <<EOF >&2
error: CSC_LINK and CSC_KEY_PASSWORD are required.

On the Mac that already has "Developer ID Application" in Keychain Access:
  1. Keychain Access → login → My Certificates
  2. Select "Developer ID Application: …"
  3. File → Export Items… → save as a .p12 (set a password)
  4. base64 -i /path/to/developer-id-application.p12 | tr -d '\\n' | pbcopy

On this Mac, copy .env.signing.example to .env.signing and paste:
  CSC_LINK=<that base64>
  CSC_KEY_PASSWORD=<the .p12 password>
  APPLE_ID=${APPLE_ID:-your-apple-id@example.com}
  APPLE_TEAM_ID=${APPLE_TEAM_ID:-SFK76D5YXM}
  APPLE_APP_SPECIFIC_PASSWORD=<app-specific password for notarytool>

Then re-run: bun run signing:import
EOF
	exit 1
fi

keychain="${HOME}/Library/Keychains/login.keychain-db"
cert_path="$(mktemp -t blather-developer-id.XXXXXX.p12)"
cleanup() { rm -f "$cert_path"; }
trap cleanup EXIT

echo "Decoding Developer ID .p12"
if ! echo "$CSC_LINK" | base64 --decode >"$cert_path"; then
	echo "error: CSC_LINK is not valid base64" >&2
	exit 1
fi
if [[ ! -s "$cert_path" ]]; then
	echo "error: decoded .p12 is empty" >&2
	exit 1
fi

echo "Importing into login keychain"
security unlock-keychain "$keychain" || true
set +e
import_output="$(security import "$cert_path" \
	-P "$CSC_KEY_PASSWORD" \
	-A \
	-t cert \
	-f pkcs12 \
	-k "$keychain" \
	-T /usr/bin/codesign \
	-T /usr/bin/security \
	-T /usr/bin/xcodebuild \
	-T /usr/bin/productsign 2>&1)"
import_status=$?
set -e
echo "$import_output"
if [[ $import_status -ne 0 ]]; then
	if [[ "$import_output" == *"already exists"* ]] && [[ -n "$(developer_id_identity)" ]]; then
		echo "  ok  certificate already in the keychain"
	else
		echo "error: security import failed (wrong CSC_KEY_PASSWORD?)" >&2
		exit 1
	fi
fi

# Allow codesign to use the private key without a GUI prompt.
security set-key-partition-list \
	-S apple-tool:,apple:,codesign: \
	-s \
	-k "" \
	"$keychain" >/dev/null 2>&1 || true

identity="$(developer_id_identity)"
if [[ -z "$identity" ]]; then
	echo "error: imported the .p12 but no Developer ID Application identity is visible." >&2
	echo "Check Keychain Access → login → My Certificates for a private-key disclosure triangle." >&2
	exit 1
fi
echo "  ok  $identity"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
	profile="${NOTARY_KEYCHAIN_PROFILE:-blather}"
	echo "Storing notarytool profile '$profile'"
	xcrun notarytool store-credentials "$profile" \
		--apple-id "$APPLE_ID" \
		--team-id "$APPLE_TEAM_ID" \
		--password "$APPLE_APP_SPECIFIC_PASSWORD"
	echo "  ok  notarytool profile '$profile'"
	echo
	echo "You can remove APPLE_APP_SPECIFIC_PASSWORD and CSC_* from .env.signing now;"
	echo "the certificate and notary profile live in your login keychain."
else
	echo "  warn  APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID not set;"
	echo "        skipped notarytool store-credentials."
	echo "        bun run build:release will still try to staple an existing Apple ticket."
fi

echo
echo "Local release builds will now sign with Developer ID and notarize:"
echo "  bun run build:release"
echo "  bun run build:dmg"
