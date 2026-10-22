#!/usr/bin/env bash
# Readiness / idempotence verification for Demo 1. Safe to re-run.
# Distinguishes Demo 1 publication proof from Demo 2 governance Ready gate.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login

PASS=0
FAIL=0
BLOCK=0
check() {
  local name="$1" cond="$2"
  if eval "$cond"; then
    ok "$name"
    PASS=$((PASS + 1))
  else
    err "$name"
    FAIL=$((FAIL + 1))
  fi
}

echo "=============================================="
echo "Demo 1 — verify ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
echo "Server: $(oc whoami --show-server 2>/dev/null || true)"
echo "=============================================="

check "RHCL / Kuadrant Ready" \
  "oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"

check "Gateway maas-default-gateway Programmed" \
  "oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type==\"Programmed\")].status}' | grep -q True"

check "ModelsAsAServiceReady=True" \
  "oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type==\"ModelsAsAServiceReady\")].status}' | grep -q True"

INFRA_NS=$(infra_namespace)
check "maas-db-config secret exists in infra ns ($INFRA_NS)" \
  "oc get secret maas-db-config -n '$INFRA_NS' -o name >/dev/null"

check "LLMInferenceService demo-simulator Ready" \
  "[[ \$(oc get llminferenceservice demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}') == True ]]"

check "MaaSModelRef exists with kind=LLMInferenceService" \
  "[[ \$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.spec.modelRef.kind}') == LLMInferenceService ]]"

check "MaaSModelRef name matches backend" \
  "[[ \$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.spec.modelRef.name}') == demo-simulator ]]"

check "MaaSModelRef RuntimeReady=True (backend healthy)" \
  "[[ \$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.conditions[?(@.type==\"RuntimeReady\")].status}') == True ]]"

MR_READY=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
MR_PHASE=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.phase}' 2>/dev/null || true)
GOV_MSG=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo \
  -o jsonpath='{.status.conditions[?(@.type=="GovernanceAttached")].message}' 2>/dev/null || true)

if [[ "$MR_READY" == "True" || "$MR_PHASE" == "Ready" ]]; then
  ok "MaaSModelRef Ready (unexpected without Demo 2 — still OK)"
  PASS=$((PASS + 1))
else
  warn "MaaSModelRef Ready=$MR_READY phase=$MR_PHASE — expected until Demo 2"
  warn "GovernanceAttached: ${GOV_MSG:-n/a}"
  warn "Platform requires MaaSSubscription + MaaSAuthPolicy pairing for Ready (Demo 2). Not a silent failure of publication."
  BLOCK=$((BLOCK + 1))
fi

check "Dashboard modelAsService=true" \
  "[[ \$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.modelAsService}') == true ]]"

check "Legacy my-first-model InferenceService still Ready (untouched)" \
  "[[ \$(oc get isvc llama-32-3b-instruct -n my-first-model -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}') == True ]]"

info "vLLMDeploymentOnMaaS=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.vLLMDeploymentOnMaaS}' 2>/dev/null || echo unset)"
info "Free GPU ≈ $(gpu_free_count 2>/dev/null || echo unknown)"
info "MaaS URL: $(maas_host_url)"
info "Dashboard: https://rhods-dashboard-redhat-ods-applications.$(cluster_domain)"

echo ""
echo "Result: $PASS passed, $FAIL failed, $BLOCK expected-Demo2-blockers"
[[ "$FAIL" -eq 0 ]] || exit 1
ok "Demo 1 verification passed (publication + runtime healthy; full MaaSModelRef Ready deferred to Demo 2)"
exit 0
