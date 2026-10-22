#!/usr/bin/env bash
# Removes ONLY resources owned by this Demo 1 (labeled app.kubernetes.io/part-of=rhoai-maas-demo).
# Does NOT uninstall RHCL/RHOAI, delete shared Gateways you did not create, or touch my-first-model.
# Usage: CONFIRM=yes bash scripts/99-cleanup.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login

if [[ "${CONFIRM:-}" != "yes" ]]; then
  err "Refusing to clean up without CONFIRM=yes"
  echo "Example: CONFIRM=yes bash scripts/99-cleanup.sh"
  exit 2
fi

warn "Deleting Demo 1 owned resources (MaaSModelRef, LLMIS, demo ns, demo postgres, maas-default-gateway if labeled)..."

oc delete maasmodelref demo-simulator -n rhoai-maas-demo --ignore-not-found
oc delete llminferenceservice demo-simulator -n rhoai-maas-demo --ignore-not-found
oc delete namespace rhoai-maas-demo --ignore-not-found

oc delete deployment postgres -n redhat-ods-applications --ignore-not-found
oc delete svc postgres -n redhat-ods-applications --ignore-not-found
oc delete pvc postgres-data -n redhat-ods-applications --ignore-not-found
oc delete secret postgres-creds -n redhat-ods-applications --ignore-not-found

if oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}' 2>/dev/null | grep -q rhoai-maas-demo; then
  oc delete gateway maas-default-gateway -n openshift-ingress --ignore-not-found
  oc delete configmap maas-gateway-options -n openshift-ingress --ignore-not-found
else
  warn "Leaving maas-default-gateway (not labeled as demo-owned or missing label)"
fi

warn "Leaving RHCL, Kuadrant, GatewayClass, DSC aigateway, and UWM in place (shared platform)."
warn "Leaving my-first-model untouched."
ok "Demo 1 cleanup requested resources deleted (platform shared pieces retained)"
