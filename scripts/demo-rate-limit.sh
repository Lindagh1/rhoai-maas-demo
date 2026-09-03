#!/usr/bin/env bash
# demo-rate-limit.sh - Quota / rate-limit demo (make demo-rate-limit).
#
# The demo subscription (manifests/maas/maas-subscription.yaml) grants only
# 100 tokens/minute. This script sends small, SEQUENTIAL requests (never
# parallel/load-testing) until the quota is exceeded, proving governance
# without stressing the cluster. A 429 here is the expected, successful
# outcome, not an error. After the test, it waits for the 1-minute token
# window to reset and confirms service returns to normal.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
source scripts/api_key.sh
require_login

HOST="$(maas_host_url)"
API_KEY="$(get_or_create_api_key)" || exit 1

GATEWAY_ADDR=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
RESOLVE_OPT=()
if [[ -n "$GATEWAY_ADDR" ]] && echo "$GATEWAY_ADDR" | grep -qE '[a-zA-Z]'; then
  GATEWAY_IP=$(dig +short "$GATEWAY_ADDR" 2>/dev/null | head -1 || true)
  [[ -n "$GATEWAY_IP" ]] && RESOLVE_OPT=(--resolve "$(maas_hostname):443:${GATEWAY_IP}")
fi

call_model() {
  curl -sSk "${RESOLVE_OPT[@]}" --connect-timeout 10 --max-time 30 \
    -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model": "facebook/opt-125m", "messages": [{"role": "user", "content": "Write a short sentence"}], "max_tokens": 40}' \
    "${HOST}/v1/chat/completions" 2>/dev/null || echo "000"
}

echo "=============================================="
echo "MaaS quota / rate-limit demo (subscription: 100 tokens/min)"
echo "=============================================="

SUCCESSES=0
RATE_LIMITED=0
MAX_REQUESTS=8
for i in $(seq 1 "$MAX_REQUESTS"); do
  CODE=$(call_model)
  echo "  request $i: HTTP $CODE"
  if [[ "$CODE" == "200" ]]; then
    SUCCESSES=$((SUCCESSES + 1))
  elif [[ "$CODE" == "429" ]]; then
    RATE_LIMITED=$((RATE_LIMITED + 1))
    ok "Quota exceeded — received HTTP 429 after $SUCCESSES successful request(s)"
    break
  fi
  sleep 1
done

if [[ "$RATE_LIMITED" -eq 0 ]]; then
  warn "No HTTP 429 observed within $MAX_REQUESTS sequential requests ($SUCCESSES succeeded). Quota may need more requests or the window just reset."
fi

echo ""
echo "Waiting 65s for the 1-minute token window to reset..."
sleep 65

echo "Retrying after window reset:"
CODE=$(call_model)
echo "  HTTP $CODE"
if [[ "$CODE" == "200" ]]; then
  ok "Service available again after token window reset"
else
  warn "Unexpected status after window reset: $CODE"
fi

echo "=============================================="
echo "RESULT: successes=$SUCCESSES rate-limited=$RATE_LIMITED"
echo "=============================================="
