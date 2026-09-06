#!/usr/bin/env bash
# Staple an existing Apple notarization ticket if one exists (including tickets
# submitted from another computer / CI), otherwise submit with notarytool.
#
# Usage:
#   ./scripts/notarize.sh dist/Blather.app
#   ./scripts/notarize.sh dist/Blather.dmg
#
# Auth (first match wins):
#   1. notarytool keychain profile (NOTARY_KEYCHAIN_PROFILE, default "blather")
#   2. APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID
# Also reads gitignored .env.signing.
#
# BLATHER_NOTARIZE=false skips submit+staple entirely.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=signing-env.sh
source "$ROOT/scripts/signing-env.sh"
load_signing_env

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
	echo "Usage: $0 <path-to-app-or-dmg>" >&2
	exit 1
fi
if [[ ! -e "$TARGET" ]]; then
	echo "error: $TARGET not found" >&2
	exit 1
fi

if [[ "${BLATHER_NOTARIZE:-}" == "false" ]]; then
	echo "Skipping notarization (BLATHER_NOTARIZE=false)"
	exit 0
fi

if xcrun stapler validate "$TARGET" >/dev/null 2>&1; then
	echo "Already stapled: $TARGET"
	xcrun stapler validate "$TARGET"
	exit 0
fi

echo "Looking up an existing notarization ticket for $TARGET"
if xcrun stapler staple "$TARGET" >/dev/null 2>&1; then
	echo "Stapled an existing Apple ticket (submitted from this or another computer)"
	xcrun stapler validate "$TARGET"
	exit 0
fi

if ! resolve_notary_auth; then
	if [[ "${BLATHER_NOTARIZE:-}" == "true" ]]; then
		echo "error: notarization required (BLATHER_NOTARIZE=true) but no notarytool profile or APPLE_* credentials were found." >&2
		echo "Run bun run signing:import after filling in .env.signing (see .env.signing.example)." >&2
		exit 1
	fi
	echo "No existing ticket and no notarytool credentials; $TARGET is signed but not notarized."
	echo "Import credentials from the other Mac with bun run signing:import, or set BLATHER_NOTARIZE=false."
	exit 0
fi

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

submit_path="$TARGET"
if [[ -d "$TARGET" ]]; then
	submit_path="$tmp/notary.zip"
	echo "Zipping $TARGET for notarytool"
	ditto -c -k --keepParent "$TARGET" "$submit_path"
fi

echo "Submitting $TARGET to Apple notary service"
set +e
submit_output="$(xcrun notarytool submit "$submit_path" "${NOTARY_AUTH[@]}" --wait 2>&1)"
submit_status=$?
set -e
echo "$submit_output"

if [[ $submit_status -ne 0 ]]; then
	echo "error: notarytool submit failed" >&2
	exit 1
fi

submission_id="$(echo "$submit_output" | grep -m1 'id:' | awk '{print $2}')"
status="$(echo "$submit_output" | grep 'status:' | tail -1 | awk '{print $2}')"
echo "Notarization status: $status"

if [[ "$status" != "Accepted" ]]; then
	echo "Notarization was NOT accepted. Fetching log..." >&2
	if [[ -n "$submission_id" ]]; then
		xcrun notarytool log "$submission_id" "${NOTARY_AUTH[@]}" >&2 || true
	fi
	exit 1
fi

echo "Stapling notarization ticket"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "Notarized $TARGET"
