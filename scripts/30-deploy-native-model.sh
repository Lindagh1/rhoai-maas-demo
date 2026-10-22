#!/usr/bin/env bash
# Deploy native LLMInferenceService (llm-d) for Demo 1.
# Uses CPU llm-d-inference-sim because the single L4 is allocated to the legacy ISVC.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login
assert_sandbox

echo "=============================================="
echo "Demo 1 — Stage: deploy native LLMInferenceService"
echo "=============================================="

FREE_GPU=$(gpu_free_count || echo 0)
info "Free nvidia.com/gpu count ≈ $FREE_GPU"
if [[ "${FREE_GPU}" == "0" ]]; then
  warn "No free GPU — deploying CPU llm-d-inference-sim (not a real GPU instruct model)."
  warn "Legacy my-first-model/llama-32-3b-instruct holds the L4; left untouched."
fi

info "Ensuring demo namespace"
oc apply -f manifests/model/namespace.yaml

info "Validating LLMInferenceService manifest (server dry-run)"
oc apply --server-side=true --dry-run=server -f manifests/model/llminferenceservice.yaml >/dev/null
ok "Server dry-run accepted"

info "Applying LLMInferenceService demo-simulator"
oc apply --server-side=true -f manifests/model/llminferenceservice.yaml

info "Waiting for LLMInferenceService Ready / pods Running (up to 5 min)..."
READY=""
for _ in $(seq 1 30); do
  READY=$(oc get llminferenceservice demo-simulator -n rhoai-maas-demo \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  RUNNING=$(oc get pods -n rhoai-maas-demo --no-headers 2>/dev/null | grep -c 'Running' || true)
  if [[ "$READY" == "True" ]] || [[ "${RUNNING:-0}" -ge 1 ]]; then
    break
  fi
  sleep 10
done

oc get llminferenceservice demo-simulator -n rhoai-maas-demo -o wide || true
oc get pods -n rhoai-maas-demo -o wide || true

if [[ "$READY" == "True" ]]; then
  ok "LLMInferenceService Ready=True"
elif [[ "${RUNNING:-0}" -ge 1 ]]; then
  warn "Pods Running but Ready condition not True yet — check events"
  oc get events -n rhoai-maas-demo --sort-by=.lastTimestamp | tail -20 || true
else
  err "LLMInferenceService not Ready and no Running pods"
  oc describe llminferenceservice demo-simulator -n rhoai-maas-demo | tail -40 || true
  oc get events -n rhoai-maas-demo --sort-by=.lastTimestamp | tail -30 || true
  exit 1
fi

echo ""
ok "Native model stage complete. Next: scripts/40-publish-maas.sh"
