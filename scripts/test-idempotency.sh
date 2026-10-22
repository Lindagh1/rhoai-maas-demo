#!/usr/bin/env bash
# test-idempotency.sh - Run bootstrap twice and confirm no duplicate/failed
# resources (make test-idempotency). Assumes bootstrap has already run at
# least once in this session (make bootstrap && make bootstrap && make
# test-idempotency).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
require_login

echo "=============================================="
echo "IDEMPOTENCY TEST"
echo "=============================================="

FAIL=0

MR_COUNT=$(oc get maasmodelref -n rhoai-maas-demo --no-headers 2>/dev/null | wc -l | tr -d ' ')
SUB_COUNT=$(oc get maassubscription -n models-as-a-service --no-headers 2>/dev/null | grep -c "^maas-demo-subscription" || true)
POLICY_COUNT=$(oc get maasauthpolicy -n models-as-a-service --no-headers 2>/dev/null | grep -c "^maas-demo-access" || true)
LLM_COUNT=$(oc get llminferenceservice -n rhoai-maas-demo --no-headers 2>/dev/null | grep -c "^demo-simulator" || true)
NS_COUNT=$(oc get namespace rhoai-maas-demo --no-headers 2>/dev/null | wc -l | tr -d ' ')
GW_COUNT=$(oc get gateway -n openshift-ingress --no-headers 2>/dev/null | grep -c "^maas-default-gateway" || true)

check_one() {
  local label="$1" val="$2"
  if [[ "$val" == "1" ]]; then
    ok "$label: exactly 1 (no duplicates)"
  else
    err "$label: found $val (expected exactly 1)"
    FAIL=1
  fi
}

check_one "Namespace rhoai-maas-demo" "$NS_COUNT"
check_one "LLMInferenceService demo-simulator" "$LLM_COUNT"
check_one "MaaSModelRef" "$MR_COUNT"
check_one "MaaSSubscription maas-demo-subscription" "$SUB_COUNT"
check_one "MaaSAuthPolicy maas-demo-access" "$POLICY_COUNT"
check_one "Gateway maas-default-gateway" "$GW_COUNT"

echo "=============================================="
if [[ "$FAIL" -eq 0 ]]; then
  echo "IDEMPOTENCY TEST: PASS"
else
  echo "IDEMPOTENCY TEST: FAIL"
fi
echo "=============================================="
exit "$FAIL"
