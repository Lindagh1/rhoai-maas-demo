#!/usr/bin/env bash
# Demo 2 — reusable, secret-safe helper: verify an API key's live status
# against the gateway without ever printing or embedding its value.
#
# Usage: scripts/demo2/30-verify-key-status.sh <path-to-keyfile>
#
# Reads the key value only via `cat` into a local shell variable (never
# appears as a literal in this script's source, and is not printed).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

KEY_FILE="${1:?usage: $0 <path-to-keyfile>}"
[[ -f "$KEY_FILE" ]] || { err "No such file: $KEY_FILE"; exit 1; }
API_KEY="$(cat "$KEY_FILE")"
[[ -z "$API_KEY" ]] && { err "Key file is empty: $KEY_FILE"; exit 1; }

HOST="$(maas_host_url)"
RESP=$(curl -sSk --connect-timeout 10 --max-time 20 \
  -H "Authorization: Bearer ${API_KEY}" \
  -w '\n%{http_code}' \
  "${HOST}/v1/models" 2>/dev/null || echo -e "\n000")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

echo "Key file: $KEY_FILE"
echo "HTTP status: $CODE"
case "$CODE" in
  200) ok "Key is ACTIVE (200 on /v1/models)." ;;
  401) ok "Key is REVOKED/INVALID as expected (401 Unauthorized)." ;;
  403) warn "403 Forbidden (no authpolicy?) — not the expected revoke signature." ;;
  429) warn "429 Too Many Requests (no subscription/quota?) — not the expected revoke signature." ;;
  *)   warn "Unexpected status $CODE" ;;
esac
echo "Body (first 200 chars): $(echo "$BODY" | head -c 200)"
