#!/usr/bin/env bash
# Shared signing / notarytool helpers. Source from other scripts; do not execute.

SIGNING_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT:=$(cd "$SIGNING_ENV_DIR/.." && pwd)}"
: "${NOTARY_KEYCHAIN_PROFILE:=blather}"

NOTARY_AUTH=()

load_signing_env() {
	local file="${1:-$ROOT/.env.signing}"
	local line key val
	[[ -f "$file" ]] || return 0
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		case "$line" in
			"" | \#*) continue ;;
		esac
		if [[ "$line" == export\ * ]]; then
			line="${line#export }"
		fi
		key="${line%%=*}"
		val="${line#*=}"
		[[ "$key" == "$line" ]] && continue
		[[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
		if [[ "$val" == \"*\" && "$val" == *\" ]]; then
			val="${val:1:${#val}-2}"
		elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
			val="${val:1:${#val}-2}"
		fi
		if [[ -z "${!key+x}" ]]; then
			export "$key=$val"
		fi
	done <"$file"
}

resolve_notary_auth() {
	NOTARY_AUTH=()
	local profile="${NOTARY_KEYCHAIN_PROFILE:-blather}"
	if xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
		NOTARY_AUTH=(--keychain-profile "$profile")
		return 0
	fi
	if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
		NOTARY_AUTH=(
			--apple-id "$APPLE_ID"
			--password "$APPLE_APP_SPECIFIC_PASSWORD"
			--team-id "$APPLE_TEAM_ID"
		)
		return 0
	fi
	return 1
}

developer_id_identity() {
	security find-identity -v -p codesigning 2>/dev/null |
		awk -F '"' '/Developer ID Application/ { print $2; exit }'
}
