#!/usr/bin/env bash
# Deploy native LLMInferenceService (llm-d) for Publier.
# Real GPU model by default; explicit CPU simulation for rehearsal.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login
assert_sandbox

echo "=============================================="
echo "Publier — Stage: deploy native LLMInferenceService"
echo "=============================================="

MODEL_MODE="${MODEL_MODE:-real}"
case "$MODEL_MODE" in
  real) MODEL_MANIFEST=manifests/model/llm.yaml ;;
  simulator) MODEL_MANIFEST=manifests/model/llm-simulator.yaml
    warn "SIMULATION: synthetic completions, no Hugging Face weights loaded." ;;
  *) err "MODEL_MODE must be real or simulator"; exit 2 ;;
esac
if [[ "$MODEL_MODE" == real ]]; then
  EXISTING_GPU=$(oc get llminferenceservice demo-llm -n maas-demo -o jsonpath='{.spec.template.containers[0].resources.requests.nvidia\.com/gpu}' 2>/dev/null || true)
  if [[ "$EXISTING_GPU" != 1 && "$(gpu_free_count)" == 0 ]]; then
    err "No free GPU. Free one explicitly or select MODEL_MODE=simulator for a labelled rehearsal."
    exit 1
  fi
fi

oc apply -f manifests/model/hardware-profile.yaml
info "Ensuring demo namespace"
oc apply -f manifests/model/namespace.yaml

info "Validating LLMInferenceService manifest (server dry-run)"
oc apply --server-side=true --dry-run=server -f "$MODEL_MANIFEST" >/dev/null
ok "Server dry-run accepted"

info "Applying LLMInferenceService demo-llm"
oc apply --server-side=true -f "$MODEL_MANIFEST"

info "Waiting for LLMInferenceService Ready and current rollout (up to 15 min)..."
READY=""
for _ in $(seq 1 90); do
  READY=$(oc get llminferenceservice demo-llm -n maas-demo \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  OBSERVED=$(oc get llminferenceservice demo-llm -n maas-demo -o jsonpath='{.status.observedGeneration}')
  GENERATION=$(oc get llminferenceservice demo-llm -n maas-demo -o jsonpath='{.metadata.generation}')
  if [[ "$READY" == True && "$OBSERVED" == "$GENERATION" ]]; then
    oc rollout status deployment/demo-llm-kserve -n maas-demo --timeout=900s
    break
  fi
  sleep 10
done

oc get llminferenceservice demo-llm -n maas-demo -o wide || true
oc get pods -n maas-demo -o wide || true

if [[ "$READY" == "True" && "$OBSERVED" == "$GENERATION" ]]; then
  ok "LLMInferenceService Ready=True"
else
  err "LLMInferenceService not Ready and no Running pods"
  oc describe llminferenceservice demo-llm -n maas-demo | tail -40 || true
  oc get events -n maas-demo --sort-by=.lastTimestamp | tail -30 || true
  exit 1
fi

echo ""
ok "Native model stage complete. Next: scripts/publish/40-publish.sh"
