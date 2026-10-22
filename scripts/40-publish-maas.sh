#!/usr/bin/env bash
# Declarative MaaS publication: MaaSModelRef -> LLMInferenceService (same namespace).
# This is CLI/GitOps publication — equivalent outcome to dashboard "Publish as MaaS",
# but the dashboard did not create this CR.
# Demo 2 objects (MaaSSubscription / MaaSAuthPolicy) are intentionally NOT applied.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login
assert_sandbox

echo "=============================================="
echo "Demo 1 — Stage: publish MaaSModelRef"
echo "=============================================="

if ! oc get crd maasmodelrefs.maas.opendatahub.io &>/dev/null; then
  err "MaaSModelRef CRD missing — run scripts/20-enable-maas.sh first"
  exit 1
fi

if ! oc get llminferenceservice demo-simulator -n rhoai-maas-demo &>/dev/null; then
  err "Backend LLMInferenceService demo-simulator missing — run scripts/30-deploy-native-model.sh first"
  exit 1
fi

info "Validating MaaSModelRef schema"
oc explain maasmodelref.spec.modelRef >/dev/null
oc apply --server-side=true --dry-run=server -f manifests/maas/maas-model-ref.yaml >/dev/null
ok "Server dry-run accepted"

info "Applying MaaSModelRef (declarative publication)"
oc apply --server-side=true -f manifests/maas/maas-model-ref.yaml

info "Waiting for MaaSModelRef Ready (up to 3 min)..."
PHASE=""
for i in $(seq 1 18); do
  PHASE=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.phase}' 2>/dev/null || true)
  READY=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$PHASE" == "Ready" || "$READY" == "True" ]] && break
  sleep 10
done

oc get maasmodelref demo-simulator -n rhoai-maas-demo -o wide || true
oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.spec}{"\n"}{.status}{"\n"}' || true

PHASE=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.phase}' 2>/dev/null || true)
READY=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)

if [[ "$PHASE" == "Ready" || "$READY" == "True" ]]; then
  ok "MaaSModelRef Ready (phase=${PHASE:-n/a})"
else
  warn "MaaSModelRef not Ready yet (phase=${PHASE:-n/a} ready=${READY:-n/a})"
  oc describe maasmodelref demo-simulator -n rhoai-maas-demo | tail -40 || true
  exit 1
fi

echo ""
ok "Publication complete (declarative CLI/GitOps). Next: scripts/50-verify.sh"
ok "Dashboard: Models → demo project should list the model; Publish-as-MaaS is already done via CR."
