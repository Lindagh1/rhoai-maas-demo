#!/usr/bin/env bash
# status.sh - Read-only readiness report for the whole MaaS stack + demo.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
require_login

INFRA_NS=$(infra_namespace)

echo "=============================================="
echo "RHOAI 3.5 MaaS demo — status"
echo "=============================================="
printf "%-30s %s\n" "Infra namespace" "$INFRA_NS"
printf "%-30s %s\n" "MaaS URL" "$(maas_host_url)"
echo ""

check() {
  local label="$1"; shift
  local val
  val=$("$@" 2>/dev/null || echo "")
  if [[ -n "$val" ]]; then printf "%-30s ${GREEN}%s${NC}\n" "$label" "$val"; else printf "%-30s ${RED}%s${NC}\n" "$label" "MISSING"; fi
}

echo "--- Platform ---"
check "GatewayClass" oc get gatewayclass openshift-default -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'
check "MaaS Gateway Programmed" oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
GW_RESTARTS=$(oc get pods -n openshift-ingress -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway" \
  -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")
printf "%-30s %s\n" "MaaS Gateway pod restarts" "$GW_RESTARTS"
check "Kuadrant Ready" oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
check "Authorino Available" oc get deployment authorino -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
check "Authorino TLS" oc get authorino authorino -n kuadrant-system -o jsonpath='{.spec.listener.tls.enabled}'
check "PostgreSQL Available" oc get deployment postgres -n redhat-ods-applications -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
check "maas-db-config" oc get secret maas-db-config -n "$INFRA_NS" -o jsonpath='{.metadata.name}'
check "maas-api ready replicas" oc get deployment maas-api -n "$INFRA_NS" -o jsonpath='{.status.readyReplicas}'
check "maas-controller ready replicas" oc get deployment maas-controller -n "$INFRA_NS" -o jsonpath='{.status.readyReplicas}'

echo ""
echo "--- MaaS config ---"
check "kserve.modelsAsService" oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}'
check "DSC ModelsAsServiceReady" oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="ModelsAsServiceReady")].status}'
check "default-tenant Ready" oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

echo ""
echo "--- Demo resources ---"
check "Namespace rhoai-maas-demo" oc get namespace rhoai-maas-demo -o jsonpath='{.metadata.name}'
check "LLMInferenceService" oc get llminferenceservice demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
POD_STATUS=$(oc get pods -n rhoai-maas-demo --no-headers 2>/dev/null | awk '{print $2, $3}')
printf "%-30s %s\n" "Simulator pod" "${POD_STATUS:-MISSING}"
check "MaaSModelRef phase" oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.phase}'
check "MaaSSubscription" oc get maassubscription maas-demo-subscription -n models-as-a-service -o jsonpath='{.metadata.name}'
check "MaaSAuthPolicy" oc get maasauthpolicy maas-demo-access -n models-as-a-service -o jsonpath='{.metadata.name}'

echo "=============================================="
