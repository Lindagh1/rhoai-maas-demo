#!/usr/bin/env bash
# demo-auth.sh - Access-control demo (make demo-auth).
#
# Official RHOAI 3.5 behavior: a MaaSSubscription without a matching
# MaaSAuthPolicy returns 403 Forbidden even with a valid subscription and API
# key. This script deletes ONLY the demo MaaSAuthPolicy, proves the 403, then
# idempotently restores it from manifests/maas/maas-auth-policy.yaml. A 403
# here is the expected, successful outcome of this test -- not an error.
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
    -d '{"model": "facebook/opt-125m", "messages": [{"role": "user", "content": "ping"}], "max_tokens": 5}' \
    "${HOST}/v1/chat/completions" 2>/dev/null || echo "000"
}

echo "=============================================="
echo "MaaS access-control demo"
echo "=============================================="

echo "Step 1: baseline call with subscription + authorization policy in place"
CODE=$(call_model)
echo "  HTTP $CODE"

echo ""
echo "Step 2: removing MaaSAuthPolicy/maas-demo-access (subscription stays in place)"
oc delete maasauthpolicy maas-demo-access -n models-as-a-service --ignore-not-found=true

echo "Waiting for Authorino cache to expire and retrying until we observe 403 (up to 90s)..."
DENIED=false
for i in $(seq 1 18); do
  CODE=$(call_model)
  echo "  attempt $i: HTTP $CODE"
  if [[ "$CODE" == "403" ]]; then DENIED=true; break; fi
  sleep 5
done

if [[ "$DENIED" == true ]]; then
  ok "Access correctly denied (HTTP 403) once the authorization policy was removed"
else
  warn "Did not observe HTTP 403 within the retry window (last: $CODE)"
fi

echo ""
echo "Step 3: restoring MaaSAuthPolicy/maas-demo-access"
oc apply --server-side=true -f manifests/maas/maas-auth-policy.yaml

echo "Waiting for access to be restored (up to 90s)..."
RESTORED=false
for i in $(seq 1 18); do
  CODE=$(call_model)
  echo "  attempt $i: HTTP $CODE"
  if [[ "$CODE" == "200" ]]; then RESTORED=true; break; fi
  sleep 5
done

if [[ "$RESTORED" == true ]]; then
  ok "Access restored (HTTP 200)"
else
  warn "Access not yet restored within the retry window (last: $CODE). It should converge shortly after the Authorino cache refreshes."
fi

echo "=============================================="
echo "RESULT: 403-on-remove = $DENIED, 200-on-restore = $RESTORED"
echo "=============================================="
