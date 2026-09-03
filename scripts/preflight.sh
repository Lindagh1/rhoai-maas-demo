#!/usr/bin/env bash
# preflight.sh - READ-ONLY inspection of RHOAI 3.5 MaaS prerequisites.
# Never creates, patches, or deletes anything. Safe to run repeatedly.
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { printf "%-28s ${GREEN}PASS${NC} %s\n" "$1" "${2:-}"; }
fail() { printf "%-28s ${RED}%s${NC} %s\n" "$1" "${3:-FAIL}" "${2:-}"; }
warn() { printf "%-28s ${YELLOW}%s${NC} %s\n" "$1" "${3:-WARN}" "${2:-}"; }

BLOCKERS=()
MISSING=()

echo "=========================================="
echo "RHOAI 3.5 MAAS PREFLIGHT"
echo "=========================================="

# --- OpenShift / RHOAI versions ---
OCP_VER=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
pass "OpenShift" "$OCP_VER"

RHOAI_CSV=$(oc get csv -A --no-headers 2>/dev/null | grep -i rhods-operator | awk '{print $2}' | sort -u | head -1)
RHOAI_VER=$(echo "$RHOAI_CSV" | sed -E 's/rhods-operator\.//')
if [[ -n "$RHOAI_VER" ]]; then pass "RHOAI" "$RHOAI_VER"; else fail "RHOAI" "" "MISSING"; BLOCKERS+=("RHOAI operator not found"); fi

# --- Cluster health ---
CRASHLOOPS=$(oc get pods -A --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || true)
OOMKILLS=$(oc get pods -A -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
n=0
for p in d['items']:
    for cs in p['status'].get('containerStatuses', []):
        term = cs.get('lastState', {}).get('terminated', {})
        if term.get('reason') == 'OOMKilled':
            n+=1
print(n)
" 2>/dev/null || echo 0)
PENDING=$(oc get pods -A --no-headers 2>/dev/null | awk '$4=="Pending"' | wc -l | tr -d ' ')
if [[ "$CRASHLOOPS" == "0" && "$OOMKILLS" == "0" ]]; then
  pass "Cluster health" "no CrashLoopBackOff, no OOMKilled"
else
  fail "Cluster health" "CrashLoops=$CRASHLOOPS OOMKilled=$OOMKILLS" "FAIL"
  BLOCKERS+=("Cluster unhealthy: CrashLoops=$CRASHLOOPS OOMKilled=$OOMKILLS")
fi

NODE_CPU_PCT=$(oc adm top nodes --no-headers 2>/dev/null | awk '{gsub("%","",$3); print $3}' | sort -n | tail -1)
NODE_MEM_PCT=$(oc adm top nodes --no-headers 2>/dev/null | awk '{gsub("%","",$5); print $5}' | sort -n | tail -1)
pass "Node CPU" "${NODE_CPU_PCT:-?}% (max across nodes)"
pass "Node memory" "${NODE_MEM_PCT:-?}% (max across nodes)"

echo ""
echo "--- MaaS prerequisites ---"

# KServe managed
KSERVE_STATE=$(oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.managementState}' 2>/dev/null)
[[ "$KSERVE_STATE" == "Managed" ]] && pass "KServe" "Managed" || fail "KServe" "$KSERVE_STATE" "FAIL"

# modelsAsService state
#
# The official RHOAI 3.5 docs describe spec.components.kserve.modelsAsService,
# but this cluster's live admission webhook has deprecated that field in favor
# of spec.components.aigateway.modelsAsAService (see docs/TROUBLESHOOTING.md
# #2). Check the documented field first, then fall back to the field this
# cluster's schema actually uses -- never assume, always verify live.
MAAS_STATE_DOCUMENTED=$(oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}' 2>/dev/null)
MAAS_STATE_LIVE_SCHEMA=$(oc get dsc default-dsc -o jsonpath='{.spec.components.aigateway.modelsAsAService.managementState}' 2>/dev/null)
if [[ "$MAAS_STATE_DOCUMENTED" == "Managed" ]]; then
  pass "Models-as-a-Service" "Managed (kserve.modelsAsService)"
elif [[ "$MAAS_STATE_LIVE_SCHEMA" == "Managed" ]]; then
  pass "Models-as-a-Service" "Managed (aigateway.modelsAsAService -- this cluster's schema; see docs/TROUBLESHOOTING.md #2)"
else
  warn "Models-as-a-Service" "${MAAS_STATE_LIVE_SCHEMA:-${MAAS_STATE_DOCUMENTED:-unset}} (will enable)" "MISSING"
  MISSING+=("aigateway.modelsAsAService.managementState=Managed")
fi

# Connectivity Link / Kuadrant
if oc get crd kuadrants.kuadrant.io &>/dev/null; then
  KUADRANT_READY=$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [[ "$KUADRANT_READY" == "True" ]]; then pass "Connectivity Link" "Kuadrant Ready"; else warn "Connectivity Link" "CRD present, not Ready" "PARTIAL"; MISSING+=("Kuadrant CR"); fi
else
  warn "Connectivity Link" "not installed" "MISSING"
  MISSING+=("rhcl-operator + Kuadrant CR")
fi

# Authorino
if oc get authorino authorino -n kuadrant-system &>/dev/null; then
  AUTH_TLS=$(oc get authorino authorino -n kuadrant-system -o jsonpath='{.spec.listener.tls.enabled}' 2>/dev/null)
  [[ "$AUTH_TLS" == "true" ]] && pass "Authorino" "Ready, TLS enabled" || warn "Authorino" "present, TLS not enabled" "PARTIAL"
else
  warn "Authorino" "no instance yet" "MISSING"
  MISSING+=("Authorino CR + TLS")
fi

# Limitador
if oc get crd limitadors.limitador.kuadrant.io &>/dev/null; then
  pass "Limitador" "CRD present"
else
  warn "Limitador" "not installed (arrives with Kuadrant)" "MISSING"
fi

# UWM
if oc get namespace openshift-user-workload-monitoring &>/dev/null; then
  pass "User Workload Monitoring" "namespace present"
else
  warn "User Workload Monitoring" "missing" "MISSING"
  MISSING+=("User Workload Monitoring")
fi

# GatewayClass actually backing our MaaS Gateway (preferred: openshift-default).
# Multiple Accepted GatewayClasses can legitimately exist on this cluster
# (e.g. RHOAI's own data-science-gateway-class for the dashboard) -- report
# the one that maas-default-gateway itself references, not just any match.
MAAS_GWC_NAME=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)
if [[ -n "$MAAS_GWC_NAME" ]]; then
  GWC_ACCEPTED=$(oc get gatewayclass "$MAAS_GWC_NAME" -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
  if [[ "$GWC_ACCEPTED" == "True" ]]; then pass "GatewayClass" "$MAAS_GWC_NAME (Accepted)"; else warn "GatewayClass" "$MAAS_GWC_NAME not Accepted" "PARTIAL"; fi
else
  GWC=$(oc get gatewayclass -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i in d['items']:
    ctrl = i['spec'].get('controllerName','')
    accepted = any(c.get('type')=='Accepted' and c.get('status')=='True' for c in i.get('status',{}).get('conditions',[]))
    if ctrl == 'openshift.io/gateway-controller/v1' and accepted:
        print(i['metadata']['name'])
" 2>/dev/null | head -1)
  if [[ -n "$GWC" ]]; then pass "GatewayClass" "$GWC (Accepted)"; else warn "GatewayClass" "none accepted" "MISSING"; MISSING+=("GatewayClass"); fi
fi

# MaaS Gateway
if oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
  GW_PROG=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
  [[ "$GW_PROG" == "True" ]] && pass "MaaS Gateway" "Programmed" || warn "MaaS Gateway" "not Programmed" "PARTIAL"
else
  warn "MaaS Gateway" "maas-default-gateway not found" "MISSING"
  MISSING+=("maas-default-gateway")
fi

# Authorino TLS annotation on gateway (only if gateway exists)
if oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
  TLS_ANNO=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}' 2>/dev/null)
  [[ "$TLS_ANNO" == "true" ]] && pass "Authorino TLS bootstrap" "annotated" || warn "Authorino TLS bootstrap" "not annotated" "MISSING"
fi

# PostgreSQL
INFRA_NS=$(oc get maastenantconfig default-tenant -n models-as-a-service -o jsonpath='{.status.infraNamespace}' 2>/dev/null)
INFRA_NS="${INFRA_NS:-redhat-ai-gateway-infra}"
if oc get deployment postgres -n redhat-ods-applications &>/dev/null; then
  pass "PostgreSQL" "deployment present in redhat-ods-applications"
else
  warn "PostgreSQL" "not deployed" "MISSING"
  MISSING+=("PostgreSQL")
fi

if oc get secret maas-db-config -n "$INFRA_NS" &>/dev/null; then
  pass "maas-db-config" "present in $INFRA_NS"
else
  warn "maas-db-config" "not present (infra ns: $INFRA_NS)" "MISSING"
  MISSING+=("maas-db-config secret")
fi

echo ""
echo "--- MaaS CRDs / Tenant ---"
CRD_COUNT=$(oc get crd 2>/dev/null | grep -cE 'maas\.opendatahub\.io|aitenants\.')
if [[ "$CRD_COUNT" -ge 6 ]]; then pass "MaaS CRDs" "$CRD_COUNT found"; else warn "MaaS CRDs" "$CRD_COUNT found (expect 6+)" "MISSING"; fi

# On this cluster's schema, the reconciled tenant is exposed as AITenant +
# MaaSTenantConfig (the "tenants.maas.opendatahub.io" CRD exists but this
# build never instantiates it -- see docs/TROUBLESHOOTING.md #2 for the same
# kserve->aigateway divergence pattern). Check the documented kind first,
# then fall back to what this cluster actually reconciles.
if oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service &>/dev/null; then
  TENANT_READY=$(oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [[ "$TENANT_READY" == "True" ]] && pass "Default Tenant" "Ready (Tenant kind)" || warn "Default Tenant" "not Ready" "PARTIAL"
else
  AITENANT_READY=$(oc get aitenant -n ai-tenants -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  MTC_READY=$(oc get maastenantconfig default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [[ "$AITENANT_READY" == "True" && "$MTC_READY" == "True" ]]; then
    pass "Default Tenant" "Ready (AITenant + MaaSTenantConfig -- this cluster's schema)"
  else
    warn "Default Tenant" "AITenant=${AITENANT_READY:-absent} MaaSTenantConfig=${MTC_READY:-absent}" "MISSING"
  fi
fi

echo ""
echo "--- Dashboard flags ---"
DC=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o json 2>/dev/null)
for flag in modelAsService genAiStudio maasAuthPolicies vLLMDeploymentOnMaaS; do
  val=$(echo "$DC" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('spec',{}).get('dashboardConfig',{}).get('$flag','unset'))" 2>/dev/null)
  echo "  $flag = $val"
done

echo ""
echo "--- GPU / Technology Preview ---"
echo "  GPU: NOT REQUIRED for this demo (CPU simulator only)"
echo "  vLLM on MaaS: DISABLED (Technology Preview, out of scope)"

echo ""
echo "------------------------------------------"
if [[ ${#BLOCKERS[@]} -gt 0 ]]; then
  echo "SAFE TO CONTINUE             NO (cluster health blocker)"
  printf 'BLOCKER: %s\n' "${BLOCKERS[@]}"
  exit 1
else
  echo "SAFE TO CONTINUE             YES"
  if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Missing prerequisites (to be installed):"
    printf '  - %s\n' "${MISSING[@]}"
  fi
fi
echo "=========================================="
