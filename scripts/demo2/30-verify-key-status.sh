#!/usr/bin/env bash
# Demo 2 — reusable, secret-safe helper: verify an API key's live status
# against the gateway without ever printing or embedding its value.
#
# Usage:
#   scripts/demo2/30-verify-key-status.sh <path-to-keyfile> [active|revoked|any]
# Default expectation: active
#
# Reads the key value only via `cat` into a local shell variable (never
# appears as a literal in this script's source, and is not printed).
# NOTE: -e is deliberately omitted. This script evaluates HTTP status codes
# (200, 401, 403, 429…) from curl and classifies them — every non-200 is an
# expected branch to report, not an error.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

KEY_FILE="${1:?usage: $0 <path-to-keyfile> [active|revoked|any]}"
EXPECT="${2:-${EXPECT_STATUS:-active}}"
[[ -f "$KEY_FILE" ]] || { err "No such file: $KEY_FILE"; exit 1; }
API_KEY="$(read_api_key_file "$KEY_FILE" 2>/dev/null || true)"
[[ -z "$API_KEY" ]] && { err "Key file is empty: $KEY_FILE"; exit 1; }

HOST="$(maas_host_url)"
# Resolve gateway IP for clusters where DNS hasn't propagated to this shell
GATEWAY_ADDR=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
RESOLVE_OPT=()
if [[ -n "$GATEWAY_ADDR" ]] && echo "$GATEWAY_ADDR" | grep -qE '[a-zA-Z]'; then
  GATEWAY_IP=$(dig +short "$GATEWAY_ADDR" 2>/dev/null | head -1 || true)
  [[ -n "$GATEWAY_IP" ]] && RESOLVE_OPT=(--resolve "$(maas_hostname):443:${GATEWAY_IP}")
fi
RESP=$(curl -sSk --connect-timeout 10 --max-time 20 \
  "${RESOLVE_OPT[@]}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -w '\n%{http_code}' \
  "${HOST}/v1/models" 2>/dev/null || echo -e "\n000")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

echo "Key file: $KEY_FILE"
echo "Expected state: $EXPECT"
echo "HTTP status: $CODE"
RC=0
case "$CODE" in
  200)
    if [[ "$EXPECT" == "revoked" ]]; then
      err "Key is ACTIVE, but a revoked key was expected."
      RC=1
    else
      ok "Key is ACTIVE (200 on /v1/models)."
    fi
    ;;
  # Verified real behavior of this installed MaaS version (not the docs'
  # stated 401): revoked/invalid keys return 403 Forbidden. Confirmed
  # repeatedly across multiple revoked keys in this sandbox.
  403)
    if [[ "$EXPECT" == "active" ]]; then
      err "Key is REVOKED/INVALID (403 Forbidden), but an active key was expected."
      RC=1
    else
      ok "Key is REVOKED/INVALID (403 Forbidden — the actual observed signature for this MaaS version, not the documented 401)."
    fi
    ;;
  401)
    if [[ "$EXPECT" == "active" ]]; then
      err "Key is REVOKED/INVALID (401 Unauthorized), but an active key was expected."
      RC=1
    else
      ok "Key is REVOKED/INVALID (401 Unauthorized, as the docs state)."
    fi
    ;;
  429)
    warn "429 Too Many Requests (no subscription/quota?) — not the expected revoke signature."
    [[ "$EXPECT" != "any" ]] && RC=1
    ;;
  *)
    warn "Unexpected status $CODE"
    [[ "$EXPECT" != "any" ]] && RC=1
    ;;
esac
echo "Body (first 200 chars): $(echo "$BODY" | head -c 200)"
exit "$RC"
