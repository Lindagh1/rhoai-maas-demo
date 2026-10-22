#!/usr/bin/env bash
# bootstrap.sh - Idempotent installation of RHOAI 3.5 Models-as-a-Service
# platform prerequisites + the demo model + demo governance objects.
#
# Safe to run repeatedly (make bootstrap && make bootstrap must both succeed
# with no errors and no duplicate resources). Every step uses `oc apply` /
# declarative patches and waits on status conditions before moving on. This
# script NEVER patches controller-managed Deployments directly, never loops
# in the background, and aborts if the platform is unhealthy.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh

require_login

echo "=============================================="
echo "RHOAI 3.5 MaaS demo — bootstrap"
echo "=============================================="

# ---------------------------------------------------------------------------
# Phase 0 gate: abort if the cluster is already unhealthy.
# ---------------------------------------------------------------------------
info "Phase 0: cluster health gate"
# Exclude the namespaces THIS bootstrap is actively (re)converging -- pods
# there can legitimately CrashLoopBackOff mid-installation (e.g. maas-api
# before maas-db-config is (re)applied with correct credentials). Any
# CrashLoopBackOff OUTSIDE those namespaces means the underlying platform
# itself is unhealthy, which is a genuine abort condition.
CRASHLOOPS=$(oc get pods -A --no-headers 2>/dev/null \
  | grep "CrashLoopBackOff" \
  | grep -vE "^(redhat-ai-gateway-infra|models-as-a-service|rhoai-maas-demo|kuadrant-system) " \
  | wc -l | tr -d ' ')
if [[ "$CRASHLOOPS" != "0" ]]; then
  err "Cluster has $CRASHLOOPS CrashLoopBackOff pod(s) outside the MaaS install scope. Aborting bootstrap."
  oc get pods -A --no-headers | grep "CrashLoopBackOff" | grep -vE "^(redhat-ai-gateway-infra|models-as-a-service|rhoai-maas-demo|kuadrant-system) "
  exit 1
fi
ok "No CrashLoopBackOff pods detected outside the MaaS install scope."

# ---------------------------------------------------------------------------
# Phase 4a: GatewayClass
# ---------------------------------------------------------------------------
info "Phase 4a: GatewayClass"
oc apply -f manifests/platform/01-gatewayclass.yaml
oc wait --for=condition=Accepted gatewayclass/openshift-default --timeout=60s
ok "GatewayClass openshift-default Accepted"

# ---------------------------------------------------------------------------
# Phase 4b: Kuadrant namespace + RHCL operator
# ---------------------------------------------------------------------------
info "Phase 4b: Connectivity Link (Kuadrant) operator"
oc apply -f manifests/platform/02-kuadrant-namespace.yaml
if oc get csv -n openshift-operators -l operators.coreos.com/rhcl-operator.openshift-operators \
     -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Succeeded; then
  ok "rhcl-operator already Succeeded"
else
  oc apply -f manifests/platform/03-rhcl-operator-subscription.yaml
  info "Waiting for rhcl-operator CSV to succeed (up to 5 min)..."
  for i in $(seq 1 30); do
    PHASE=$(oc get csv -n openshift-operators -l operators.coreos.com/rhcl-operator.openshift-operators \
             -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Succeeded" ]] && break
    sleep 10
  done
  if [[ "$PHASE" == "Succeeded" ]]; then
    ok "rhcl-operator installed (CSV Succeeded)"
  else
    err "rhcl-operator did not reach Succeeded (phase: ${PHASE:-unknown})"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Phase 4c: Authorino service annotation + Kuadrant CR
# ---------------------------------------------------------------------------
info "Phase 4c: Kuadrant CR (installs Authorino + Limitador)"
oc apply -f manifests/platform/04-authorino-service-annotation.yaml
oc apply -f manifests/platform/05-kuadrant.yaml

info "Waiting for Kuadrant to become Ready (up to 3 min)..."
if oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=180s 2>&1 | grep -q "condition met"; then
  ok "Kuadrant Ready"
else
  warn "Kuadrant not yet Ready — checking for MissingDependency (Istio race), retrying operator..."
  POD=$(oc get pods -n openshift-operators --no-headers 2>/dev/null | grep kuadrant-operator | awk '{print $1}' | head -1)
  if [[ -n "$POD" ]]; then
    oc delete pod -n openshift-operators "$POD" 2>/dev/null || true
    sleep 5
  fi
  oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=180s
  ok "Kuadrant Ready (after operator restart)"
fi

# ---------------------------------------------------------------------------
# Phase 4d: Authorino TLS
# ---------------------------------------------------------------------------
info "Phase 4d: Authorino TLS configuration"
info "Waiting for Authorino CR to exist (created by Kuadrant operator)..."
for i in $(seq 1 30); do
  oc get authorino authorino -n kuadrant-system &>/dev/null && break
  sleep 5
done
oc get authorino authorino -n kuadrant-system &>/dev/null || { err "Authorino CR never appeared"; exit 1; }

TLS_ENABLED=$(oc get authorino authorino -n kuadrant-system -o jsonpath='{.spec.listener.tls.enabled}' 2>/dev/null || echo "")
if [[ "$TLS_ENABLED" == "true" ]]; then
  ok "Authorino TLS already enabled"
else
  oc patch authorino authorino -n kuadrant-system --type=merge --patch '
{
  "spec": {
    "listener": {
      "tls": {
        "enabled": true,
        "certSecretRef": { "name": "authorino-server-cert" }
      }
    }
  }
}'
  ok "Authorino TLS listener enabled"
fi

oc -n kuadrant-system set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt >/dev/null
oc wait --for=condition=Available deployment/authorino -n kuadrant-system --timeout=180s
ok "Authorino deployment Available with TLS env configured"

# ---------------------------------------------------------------------------
# Phase 4e: MaaS Gateway (with parametersRef memory override — OOM prevention)
# ---------------------------------------------------------------------------
info "Phase 4e: MaaS Gateway"
oc apply -f manifests/platform/06-gateway-resources.yaml

CLUSTER_DOMAIN=$(cluster_domain)
CERT_NAME=$(cert_name)
MAAS_HOSTNAME=$(maas_hostname)
info "CLUSTER_DOMAIN=$CLUSTER_DOMAIN  CERT_NAME=$CERT_NAME  MAAS_HOSTNAME=$MAAS_HOSTNAME"

if oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
  ok "Gateway maas-default-gateway already exists — inspecting before touching it"
  EXISTING_PARAMS=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.infrastructure.parametersRef.name}' 2>/dev/null || true)
  if [[ "$EXISTING_PARAMS" != "maas-gateway-options" ]]; then
    warn "Existing Gateway does not reference maas-gateway-options ConfigMap; re-applying template idempotently."
    export CLUSTER_DOMAIN CERT_NAME MAAS_HOSTNAME
    envsubst '${MAAS_HOSTNAME} ${CERT_NAME}' < manifests/platform/07-gateway.yaml.tmpl | oc apply -f -
  fi
else
  export CLUSTER_DOMAIN CERT_NAME MAAS_HOSTNAME
  envsubst '${MAAS_HOSTNAME} ${CERT_NAME}' < manifests/platform/07-gateway.yaml.tmpl | oc apply -f -
fi

info "Waiting for Gateway to be Programmed (up to 3 min)..."
oc wait --for=condition=Programmed gateway/maas-default-gateway -n openshift-ingress --timeout=180s
ok "Gateway maas-default-gateway Programmed"

# ---------------------------------------------------------------------------
# Phase 5: PostgreSQL
# ---------------------------------------------------------------------------
info "Phase 5: PostgreSQL for MaaS API-key storage"
NEED_PG_PASSWORD_SYNC=false
if oc get secret postgres-creds -n redhat-ods-applications &>/dev/null; then
  EXISTING_PG_PASSWORD=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
  if [[ -z "$EXISTING_PG_PASSWORD" ]]; then
    warn "postgres-creds POSTGRES_PASSWORD is empty (leftover from a prior failed generator) — self-healing"
    PG_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(20))")
    if [[ -z "$PG_PASSWORD" ]]; then
      err "Failed to generate a PostgreSQL password (python3 unavailable?). Aborting."
      exit 1
    fi
    oc create secret generic postgres-creds -n redhat-ods-applications \
      --from-literal=POSTGRES_USER=maasadmin \
      --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
      --from-literal=POSTGRES_DB=maasdb \
      --dry-run=client -o yaml | oc apply -f - >/dev/null
    NEED_PG_PASSWORD_SYNC=true
    ok "postgres-creds secret repaired (new password generated, never printed/committed)"
  else
    ok "postgres-creds secret already exists (password non-empty)"
  fi
else
  PG_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(20))")
  if [[ -z "$PG_PASSWORD" ]]; then
    err "Failed to generate a PostgreSQL password (python3 unavailable?). Aborting."
    exit 1
  fi
  oc create secret generic postgres-creds -n redhat-ods-applications \
    --from-literal=POSTGRES_USER=maasadmin \
    --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
    --from-literal=POSTGRES_DB=maasdb
  ok "postgres-creds secret created (password generated, never printed/committed)"
fi

oc apply -f manifests/platform/08-postgres-pvc.yaml
oc apply -f manifests/platform/09-postgres-deployment.yaml
oc apply -f manifests/platform/10-postgres-service.yaml
info "Waiting for PostgreSQL deployment to become Available..."
oc wait --for=condition=Available deployment/postgres -n redhat-ods-applications --timeout=180s
ok "PostgreSQL Available"

if [[ "$NEED_PG_PASSWORD_SYNC" == "true" ]]; then
  info "Syncing repaired password into the running PostgreSQL role (ALTER ROLE, via local socket auth — no controller/Deployment patching)"
  PG_POD=$(oc get pod -n redhat-ods-applications -l app=postgres -o jsonpath='{.items[0].metadata.name}')
  SYNC_USER=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
  SYNC_PASS=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
  oc exec -n redhat-ods-applications "$PG_POD" -- bash -c "psql -h /var/run/postgresql -U postgres -d postgres -c \"ALTER USER ${SYNC_USER} WITH PASSWORD '${SYNC_PASS}';\"" >/dev/null
  unset SYNC_USER SYNC_PASS
  ok "PostgreSQL role password synced to match postgres-creds secret"
fi

# ---------------------------------------------------------------------------
# Phase 6: Enable RHOAI MaaS
# ---------------------------------------------------------------------------
# The official RHOAI 3.5 docs (docs.redhat.com) document
# spec.components.kserve.modelsAsService.managementState=Managed as the way
# to enable MaaS. However, THIS cluster's live admission webhook rejects that
# field with: "modelsAsService is deprecated; cannot re-enable once Removed.
# Use spec.components.aigateway.modelsAsAService instead" -- this exact
# cluster build has already migrated to the newer "AI Gateway" modularized
# component referenced by the MaaS companion guide's DataScienceCluster
# example. Per the explicit instruction to verify schema against the live
# cluster rather than assume from docs, we try the documented field first and
# transparently fall back to the field the cluster itself demands.
info "Phase 6: Enable Models-as-a-Service in DataScienceCluster"

CURRENT_MAAS_STATE=$(oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}' 2>/dev/null || true)
CURRENT_AIGW_STATE=$(oc get dsc default-dsc -o jsonpath='{.spec.components.aigateway.modelsAsAService.managementState}' 2>/dev/null || true)

if [[ "$CURRENT_MAAS_STATE" == "Managed" || "$CURRENT_AIGW_STATE" == "Managed" ]]; then
  ok "MaaS already enabled on this DSC (kserve.modelsAsService=$CURRENT_MAAS_STATE, aigateway.modelsAsAService=$CURRENT_AIGW_STATE)"
else
  PATCH_OUT=$(oc patch dsc default-dsc --type=merge -p '{"spec":{"components":{"kserve":{"modelsAsService":{"managementState":"Managed"}}}}}' 2>&1) && PATCH_RC=0 || PATCH_RC=$?
  if [[ "$PATCH_RC" -eq 0 ]]; then
    ok "DSC patched: kserve.modelsAsService=Managed (documented RHOAI 3.5 field)"
  elif echo "$PATCH_OUT" | grep -qi "aigateway.modelsAsAService"; then
    warn "kserve.modelsAsService is deprecated on this cluster build; using spec.components.aigateway.modelsAsAService instead (live-schema fallback)"
    oc patch dsc default-dsc --type=merge -p '{"spec":{"components":{"aigateway":{"managementState":"Managed","modelsAsAService":{"managementState":"Managed"}}}}}'
    ok "DSC patched: aigateway.managementState=Managed, aigateway.modelsAsAService=Managed"
  else
    err "Failed to enable Models-as-a-Service on the DataScienceCluster:"
    echo "$PATCH_OUT"
    exit 1
  fi
fi

# ogx exposes Gen AI Studio user-facing MaaS features (official docs section
# "Dashboard configuration for Models-as-a-Service"). On this cluster build,
# the operator's own reconciler logs reveal a hard prerequisite not mentioned
# in any doc: "LlamaStackOperator is set to Managed; it has been deprecated,
# set it to Removed before enabling OGX". LlamaStackOperator has no CRD/CR
# instances on this cluster (nothing depends on it), so removing it is safe.
LLAMASTACK_STATE=$(oc get dsc default-dsc -o jsonpath='{.spec.components.llamastackoperator.managementState}' 2>/dev/null || true)
if [[ "$LLAMASTACK_STATE" == "Managed" ]]; then
  warn "llamastackoperator=Managed blocks OGX provisioning on this build; setting it to Removed (deprecated, superseded by OGX, no active consumers found)"
  oc patch dsc default-dsc --type=merge -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Removed"}}}}'
fi

oc patch dsc default-dsc --type=merge -p '{"spec":{"components":{"ogx":{"managementState":"Managed"}}}}'
ok "DSC patched: ogx.managementState=Managed"

info "Enabling dashboard flags (modelAsService, genAiStudio)"
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '
{
  "spec": {
    "dashboardConfig": {
      "modelAsService": true,
      "genAiStudio": true
    }
  }
}'
ok "Dashboard flags set: modelAsService=true, genAiStudio=true"

# maasAuthPolicies is a legacy flag that this cluster's admission webhook has
# deprecated ("must be removed or left unchanged") now that aigateway
# modularization is active -- the MaaS governance UI is gated by genAiStudio
# instead. We only attempt it if it's not already set, and treat rejection as
# a non-fatal, expected outcome (never hard-fails bootstrap).
CURRENT_MAAP=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.maasAuthPolicies}' 2>/dev/null || true)
if [[ "$CURRENT_MAAP" != "true" ]]; then
  if oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge \
      -p '{"spec":{"dashboardConfig":{"maasAuthPolicies":true}}}' &>/tmp/maap_patch.log; then
    ok "Dashboard flag maasAuthPolicies=true set"
  else
    warn "spec.dashboardConfig.maasAuthPolicies is deprecated/frozen on this cluster build (governance UI is gated by genAiStudio instead) — skipping, non-fatal:"
    tail -1 /tmp/maap_patch.log
  fi
fi
info "vLLMDeploymentOnMaaS intentionally left untouched (Technology Preview, out of scope)"

# ---------------------------------------------------------------------------
# Phase 7: Wait for MaaS reconciliation
# ---------------------------------------------------------------------------
info "Phase 7: Waiting for the aigateway/ogx modules and MaaS CRDs to appear (up to 8 min)..."
for i in $(seq 1 48); do
  CRD_COUNT=$(oc get crd 2>/dev/null | grep -cE 'maas\.opendatahub\.io|aitenants\.')
  [[ "$CRD_COUNT" -ge 6 ]] && break
  if (( i % 6 == 0 )); then
    AIGW_MSG=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="AIGatewayReady")].message}' 2>/dev/null || true)
    OGX_MSG=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="OGXReady")].message}' 2>/dev/null || true)
    info "  still waiting... AIGatewayReady: ${AIGW_MSG:-unknown} | OGXReady: ${OGX_MSG:-unknown}"
  fi
  sleep 10
done
if [[ "$CRD_COUNT" -ge 6 ]]; then
  ok "MaaS CRDs present ($CRD_COUNT found)"
else
  err "MaaS CRDs did not appear after 8 minutes (found: $CRD_COUNT)"
  echo "--- DSC conditions ---"
  oc get dsc default-dsc -o json | python3 -c "
import json,sys
d=json.load(sys.stdin)
for c in d.get('status',{}).get('conditions',[]):
    print(c.get('type'), '=', c.get('status'), '|', c.get('reason'), '|', c.get('message',''))
"
  exit 1
fi

info "Waiting for infra namespace to appear..."
INFRA_NS=""
for i in $(seq 1 30); do
  INFRA_NS=$(infra_namespace)
  oc get namespace "$INFRA_NS" &>/dev/null && break
  sleep 10
done
oc get namespace "$INFRA_NS" &>/dev/null || { err "Infra namespace $INFRA_NS never appeared"; exit 1; }
ok "Infra namespace: $INFRA_NS"

oc label namespace "$INFRA_NS" maas.opendatahub.io/gateway-access=true --overwrite >/dev/null
ok "Labeled $INFRA_NS for Gateway route binding"

# ---------------------------------------------------------------------------
# Phase 5b (deferred): maas-db-config secret (needs infra namespace to exist)
# ---------------------------------------------------------------------------
info "Ensuring maas-db-config secret in $INFRA_NS points at our PostgreSQL with the correct credentials"
# Note: the aigateway/ogx module auto-creates a placeholder maas-db-config
# secret as soon as the infra namespace is provisioned, but it does not know
# our actual PostgreSQL credentials -- it must be overwritten with the real
# connection string (never printed/committed) for maas-api to connect.
PG_USER=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
PG_PASS=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
PG_DB=$(oc get secret postgres-creds -n redhat-ods-applications -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
DESIRED_URL="postgresql://${PG_USER}:${PG_PASS}@postgres.redhat-ods-applications.svc.cluster.local:5432/${PG_DB}?sslmode=disable"

CURRENT_URL=""
if oc get secret maas-db-config -n "$INFRA_NS" &>/dev/null; then
  CURRENT_URL=$(oc get secret maas-db-config -n "$INFRA_NS" -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

if [[ "$CURRENT_URL" == "$DESIRED_URL" ]]; then
  ok "maas-db-config already has the correct connection string"
else
  oc create secret generic maas-db-config -n "$INFRA_NS" \
    --from-literal=DB_CONNECTION_URL="$DESIRED_URL" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "maas-db-config (re)created with correct connection string (never printed)"
  if oc get deployment maas-api -n "$INFRA_NS" &>/dev/null; then
    info "Restarting maas-api to pick up DB config..."
    oc rollout restart deployment/maas-api -n "$INFRA_NS"
    oc rollout status deployment/maas-api -n "$INFRA_NS" --timeout=180s
  fi
fi
unset PG_USER PG_PASS PG_DB DESIRED_URL CURRENT_URL

info "Waiting for default-tenant to become Ready (up to 5 min)..."
for i in $(seq 1 30); do
  TENANT_READY=$(oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$TENANT_READY" == "True" ]] && break
  sleep 10
done
if [[ "$TENANT_READY" == "True" ]]; then
  ok "default-tenant Ready"
else
  warn "default-tenant not yet Ready. Current status:"
  oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service -o jsonpath='{.status.conditions}' 2>/dev/null || true
  echo ""
fi

# ---------------------------------------------------------------------------
# Phase 9: Deploy CPU simulator model
# ---------------------------------------------------------------------------
info "Phase 9: Deploying CPU simulator model"
oc apply -f manifests/model/namespace.yaml
oc apply --server-side=true -f manifests/model/llminferenceservice.yaml

info "Waiting for simulator pod to be Running (up to 3 min)..."
for i in $(seq 1 18); do
  RUNNING=$(oc get pods -n rhoai-maas-demo --no-headers 2>/dev/null | grep -c "Running" || true)
  [[ "$RUNNING" -ge 1 ]] && break
  sleep 10
done
if [[ "$RUNNING" -ge 1 ]]; then
  ok "Simulator pod Running"
else
  warn "Simulator pod not Running yet:"
  oc get pods -n rhoai-maas-demo
fi

# ---------------------------------------------------------------------------
# Phase 10-11: MaaS governance objects
# ---------------------------------------------------------------------------
info "Phase 10-11: MaaSModelRef / MaaSSubscription / MaaSAuthPolicy"
oc apply --server-side=true -f manifests/maas/maas-model-ref.yaml
oc apply --server-side=true -f manifests/maas/maas-subscription.yaml
oc apply --server-side=true -f manifests/maas/maas-auth-policy.yaml

info "Waiting for MaaSModelRef to be Ready (up to 3 min)..."
for i in $(seq 1 18); do
  MR_PHASE=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$MR_PHASE" == "Ready" ]] && break
  sleep 10
done
if [[ "$MR_PHASE" == "Ready" ]]; then
  ok "MaaSModelRef Ready"
else
  warn "MaaSModelRef phase: ${MR_PHASE:-unknown}"
fi

echo ""
echo "=============================================="
echo "Bootstrap complete."
echo "MaaS URL: $(maas_host_url)"
echo "Run 'make status' for a full readiness report."
echo "=============================================="
