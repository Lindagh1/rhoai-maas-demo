#!/usr/bin/env bash
# Idempotent MaaS infrastructure: Gateway, Postgres, DSC aigateway, dashboard flags, DB secret.
# Does NOT deploy models or Demo 2 governance CRs.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login
assert_sandbox

echo "=============================================="
echo "Demo 1 — Stage: enable MaaS"
echo "=============================================="

# --- Gateway ---
info "Ensuring maas-default-gateway (will not overwrite foreign gateways)"
oc apply -f manifests/platform/06-gateway-resources.yaml

CLUSTER_DOMAIN=$(cluster_domain)
CERT_NAME=$(cert_name)
MAAS_HOSTNAME=$(maas_hostname)
info "CLUSTER_DOMAIN=$CLUSTER_DOMAIN CERT_NAME=$CERT_NAME MAAS_HOSTNAME=$MAAS_HOSTNAME"

export CLUSTER_DOMAIN CERT_NAME MAAS_HOSTNAME
if oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
  EXISTING_CLASS=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.gatewayClassName}')
  if [[ "$EXISTING_CLASS" != "openshift-default" ]]; then
    err "maas-default-gateway exists with unexpected gatewayClassName=$EXISTING_CLASS — refusing to overwrite"
    exit 1
  fi
  ok "Gateway maas-default-gateway exists — re-applying template idempotently"
fi
envsubst '${MAAS_HOSTNAME} ${CERT_NAME}' < manifests/platform/07-gateway.yaml.tmpl | oc apply -f -

info "Waiting for Gateway Programmed (up to 3 min)..."
oc wait --for=condition=Programmed gateway/maas-default-gateway -n openshift-ingress --timeout=180s
ok "Gateway maas-default-gateway Programmed"

# --- PostgreSQL (demo-scoped in redhat-ods-applications) ---
info "Ensuring PostgreSQL for MaaS API-key storage"
if oc get secret postgres-creds -n redhat-ods-applications &>/dev/null; then
  EXISTING_PG_PASSWORD=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
  if [[ -z "$EXISTING_PG_PASSWORD" ]]; then
    warn "postgres-creds password empty — regenerating"
    PG_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(20))")
    oc create secret generic postgres-creds -n redhat-ods-applications \
      --from-literal=POSTGRES_USER=maasadmin \
      --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
      --from-literal=POSTGRES_DB=maasdb \
      --dry-run=client -o yaml | oc apply -f - >/dev/null
    unset PG_PASSWORD
  else
    ok "postgres-creds already present"
  fi
else
  PG_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(20))")
  oc create secret generic postgres-creds -n redhat-ods-applications \
    --from-literal=POSTGRES_USER=maasadmin \
    --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
    --from-literal=POSTGRES_DB=maasdb
  unset PG_PASSWORD
  ok "postgres-creds created (password never printed/committed)"
fi

oc apply -f manifests/platform/08-postgres-pvc.yaml
oc apply -f manifests/platform/09-postgres-deployment.yaml
oc apply -f manifests/platform/10-postgres-service.yaml
oc wait --for=condition=Available deployment/postgres -n redhat-ods-applications --timeout=300s
ok "PostgreSQL Available"

# --- DSC aigateway (RHOAI 3.5 field; do not re-enable deprecated kserve.modelsAsService) ---
info "Enabling aigateway + modelsAsAService on DataScienceCluster"
CURRENT_AIGW=$(oc get dsc default-dsc -o jsonpath='{.spec.components.aigateway.managementState}' 2>/dev/null || true)
CURRENT_MAAS=$(oc get dsc default-dsc -o jsonpath='{.spec.components.aigateway.modelsAsAService.managementState}' 2>/dev/null || true)
if [[ "$CURRENT_AIGW" == "Managed" && "$CURRENT_MAAS" == "Managed" ]]; then
  ok "aigateway + modelsAsAService already Managed"
else
  oc patch dsc default-dsc --type=merge -p '{
    "spec": {
      "components": {
        "aigateway": {
          "managementState": "Managed",
          "modelsAsAService": { "managementState": "Managed" }
        }
      }
    }
  }'
  ok "DSC patched: aigateway=Managed, modelsAsAService=Managed"
fi

info "Ensuring dashboard modelAsService=true (leave vLLMDeploymentOnMaaS untouched — Technology Preview)"
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{
  "spec": { "dashboardConfig": { "modelAsService": true, "genAiStudio": true } }
}' >/dev/null
ok "Dashboard flags: modelAsService=true, genAiStudio=true"

# --- Wait for MaaS CRDs + infra ---
info "Waiting for MaaS CRDs (up to 10 min)..."
CRD_COUNT=0
for i in $(seq 1 60); do
  CRD_COUNT=$(oc get crd 2>/dev/null | grep -cE 'maas\.opendatahub\.io' || true)
  [[ "${CRD_COUNT:-0}" -ge 3 ]] && break
  if (( i % 6 == 0 )); then
    MSG=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")].message}' 2>/dev/null || true)
    info "  still waiting for MaaS CRDs... ModelsAsAServiceReady msg: ${MSG:-n/a}"
  fi
  sleep 10
done
[[ "${CRD_COUNT:-0}" -ge 3 ]] || { err "MaaS CRDs did not appear (count=$CRD_COUNT)"; oc get dsc default-dsc -o yaml | head -80; exit 1; }
ok "MaaS CRDs present ($CRD_COUNT)"

info "Waiting for infrastructure namespace..."
INFRA_NS=""
for _ in $(seq 1 36); do
  INFRA_NS=$(infra_namespace)
  oc get namespace "$INFRA_NS" &>/dev/null && break
  sleep 10
done
oc get namespace "$INFRA_NS" &>/dev/null || { err "Infra namespace never appeared"; exit 1; }
ok "Infra namespace: $INFRA_NS"
oc label namespace "$INFRA_NS" maas.opendatahub.io/gateway-access=true --overwrite >/dev/null

# --- maas-db-config in infra ns ---
# Idempotence: only (re)write the secret and restart maas-api if the connection
# string actually changed. A blind restart on every re-run would violate the
# "safe to re-run" requirement (scripts/50-verify.sh run twice must be a no-op).
info "Checking maas-db-config in $INFRA_NS (connection string never printed)"
PG_USER=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
PG_PASS=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
PG_DB=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
DESIRED_URL="postgresql://${PG_USER}:${PG_PASS}@postgres.redhat-ods-applications.svc.cluster.local:5432/${PG_DB}?sslmode=disable"
unset PG_USER PG_PASS PG_DB

CURRENT_URL=""
if oc get secret maas-db-config -n "$INFRA_NS" &>/dev/null; then
  CURRENT_URL=$(oc get secret maas-db-config -n "$INFRA_NS" -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

if [[ "$CURRENT_URL" == "$DESIRED_URL" ]]; then
  ok "maas-db-config already up to date — skipping write and maas-api restart"
else
  oc create secret generic maas-db-config -n "$INFRA_NS" \
    --from-literal=DB_CONNECTION_URL="$DESIRED_URL" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "maas-db-config (re)written"
  if oc get deployment maas-api -n "$INFRA_NS" &>/dev/null; then
    info "Connection string changed — restarting maas-api to pick it up"
    oc rollout restart deployment/maas-api -n "$INFRA_NS" >/dev/null || true
    oc rollout status deployment/maas-api -n "$INFRA_NS" --timeout=300s || warn "maas-api rollout not ready yet"
  fi
fi
unset DESIRED_URL CURRENT_URL

info "Waiting for ModelsAsAServiceReady=True (up to 5 min)..."
for _ in $(seq 1 30); do
  ST=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")].status}' 2>/dev/null || true)
  [[ "$ST" == "True" ]] && break
  sleep 10
done
ST=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")].status}' 2>/dev/null || true)
if [[ "$ST" == "True" ]]; then
  ok "ModelsAsAServiceReady=True"
else
  warn "ModelsAsAServiceReady=$ST — check maas-api / DB / UWM; continuing so verify can diagnose"
  oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")]}{"\n"}' || true
fi

echo ""
ok "MaaS enable stage complete. Next: scripts/30-deploy-native-model.sh"
ok "MaaS URL (when ready): $(maas_host_url)"
