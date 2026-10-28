#!/usr/bin/env bash
# Idempotent: enables the RHOAI 3.5 Tech Preview "Observe & Monitor →
# Dashboard" page in click-ops mode, i.e. so an admin can see the native
# OpenShift AI observability screens (Cluster / Models and, on this build,
# additional LLM/MaaS-related tabs such as Usage) instead of relying only
# on terminal-side checks.
#
# What this enables, end to end:
#   1. Cluster Observability Operator (COO)        — manifests/rhoai-operator/11-*
#   2. Red Hat build of OpenTelemetry operator      — manifests/rhoai-operator/12-*
#   3. DSCInitialization.spec.monitoring            — storage for the metrics stack
#   4. MaasTenantConfig.spec.telemetry.enabled       — MaaS gateway emits Prometheus metrics
#   5. Kuadrant CR spec.observability.enable         — PodMonitor for Limitador/maas-api
#
# All 5 preconditions are required; missing any one of them leaves
# DSCInitialization.status Ready=False (reason MissingOperator) or leaves
# the Perses backend with no data. Re-running this script is a no-op once
# everything is in place (`oc apply -f` + conditional `oc patch`).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login
assert_sandbox

echo "=============================================="
echo "Demo — Stage: enable MaaS observability dashboard (click-ops)"
echo "=============================================="

# --- 1. Cluster Observability Operator ---
info "Ensuring Cluster Observability Operator (COO)"
oc apply -f manifests/rhoai-operator/11-cluster-observability-operator.yaml >/dev/null
for i in $(seq 1 18); do
  CSV=$(oc get sub cluster-observability-operator -n openshift-cluster-observability-operator -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
  if [[ -n "$CSV" ]]; then
    PHASE=$(oc get csv "$CSV" -n openshift-cluster-observability-operator -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Succeeded" ]] && break
  fi
  sleep 10
done
PHASE=$(oc get csv "$CSV" -n openshift-cluster-observability-operator -o jsonpath='{.status.phase}' 2>/dev/null || true)
[[ "$PHASE" == "Succeeded" ]] || { err "COO did not reach Succeeded (phase=$PHASE)"; exit 1; }
ok "Cluster Observability Operator: $PHASE"

# --- 2. OpenTelemetry Collector operator ---
info "Ensuring Red Hat build of OpenTelemetry operator"
oc apply -f manifests/rhoai-operator/12-opentelemetry-operator.yaml >/dev/null
for i in $(seq 1 18); do
  CSV=$(oc get sub opentelemetry-product -n openshift-opentelemetry-operator -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
  if [[ -n "$CSV" ]]; then
    PHASE=$(oc get csv "$CSV" -n openshift-opentelemetry-operator -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Succeeded" ]] && break
  fi
  sleep 10
done
PHASE=$(oc get csv "$CSV" -n openshift-opentelemetry-operator -o jsonpath='{.status.phase}' 2>/dev/null || true)
[[ "$PHASE" == "Succeeded" ]] || { err "OpenTelemetry operator did not reach Succeeded (phase=$PHASE)"; exit 1; }
ok "OpenTelemetry Collector operator: $PHASE"

# --- 3. DSCInitialization monitoring storage ---
info "Ensuring DSCInitialization.spec.monitoring (storage sized for a sandbox)"
CURRENT=$(oc get dscinitialization default-dsci -o jsonpath='{.spec.monitoring.metrics.storage.size}' 2>/dev/null || true)
if [[ "$CURRENT" == "5Gi" ]]; then
  ok "DSCInitialization monitoring storage already set (5Gi)"
else
  oc patch dscinitialization default-dsci --type=merge -p '{
    "spec": {
      "monitoring": {
        "managementState": "Managed",
        "metrics": { "storage": { "size": "5Gi", "retention": "1d" } }
      }
    }
  }' >/dev/null
  ok "DSCInitialization monitoring storage patched"
fi

# --- 4. MaasTenantConfig telemetry ---
info "Ensuring MaasTenantConfig default-tenant telemetry.enabled=true"
CURRENT=$(oc get maastenantconfig default-tenant -n models-as-a-service -o jsonpath='{.spec.telemetry.enabled}' 2>/dev/null || true)
if [[ "$CURRENT" == "true" ]]; then
  ok "MaasTenantConfig telemetry already enabled"
else
  oc patch maastenantconfig default-tenant -n models-as-a-service --type=merge \
    -p '{"spec":{"telemetry":{"enabled":true}}}' >/dev/null
  ok "MaasTenantConfig telemetry enabled"
fi

# --- 5. Kuadrant observability ---
info "Ensuring Kuadrant CR spec.observability.enable=true"
KUADRANT_NS=$(oc get kuadrant -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
KUADRANT_NAME=$(oc get kuadrant -A -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$KUADRANT_NAME" ]]; then
  warn "No Kuadrant CR found — skipping (expected once MaaS infra is enabled via scripts/20-enable-maas.sh)"
else
  CURRENT=$(oc get kuadrant "$KUADRANT_NAME" -n "$KUADRANT_NS" -o jsonpath='{.spec.observability.enable}' 2>/dev/null || true)
  if [[ "$CURRENT" == "true" ]]; then
    ok "Kuadrant observability already enabled"
  else
    oc patch kuadrant "$KUADRANT_NAME" -n "$KUADRANT_NS" --type=merge \
      -p '{"spec":{"observability":{"enable":true}}}' >/dev/null
    ok "Kuadrant observability enabled"
  fi
fi

# --- Wait for DSCInitialization Ready ---
info "Waiting for DSCInitialization Ready=True (up to 3 min)..."
READY=""
for _ in $(seq 1 18); do
  READY=$(oc get dscinitialization default-dsci -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$READY" == "True" ]] && break
  sleep 10
done
if [[ "$READY" == "True" ]]; then
  ok "DSCInitialization Ready=True"
else
  REASON=$(oc get dscinitialization default-dsci -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || true)
  warn "DSCInitialization Ready=$READY — ${REASON:-no message}"
fi

# --- Nudge the dashboard-operator reconcile so it auto-detects Perses and
#     flips Dashboard.status.conditions[ObservabilityAvailable] to True. A
#     plain restart is enough; it is safe to run repeatedly. ---
info "Restarting dashboard-operator to pick up the now-ready monitoring stack"
oc rollout restart deployment/dashboard-operator -n redhat-ods-applications >/dev/null
oc rollout status deployment/dashboard-operator -n redhat-ods-applications --timeout=120s >/dev/null

OBS_AVAILABLE=""
for _ in $(seq 1 12); do
  OBS_AVAILABLE=$(oc get dashboard default-dashboard -o jsonpath='{.status.conditions[?(@.type=="ObservabilityAvailable")].status}' 2>/dev/null || true)
  [[ "$OBS_AVAILABLE" == "True" ]] && break
  sleep 10
done
if [[ "$OBS_AVAILABLE" == "True" ]]; then
  ok "Dashboard ObservabilityAvailable=True — 'Observe & Monitor → Dashboard' is now live in the UI"
else
  warn "Dashboard ObservabilityAvailable=$OBS_AVAILABLE — may need another minute; re-run this script to re-check"
fi

# --- rhobs-group PodMonitor mirrors + RBAC (real fix found live) ---
# The COO-provisioned Prometheus uses the monitoring.rhobs CRD group and has
# no RBAC to list pods outside its own namespace by default -- see the long
# comment header in the manifest itself for the full root cause.
info "Ensuring observability RBAC + rhobs PodMonitor mirrors (Limitador/maas-api scraping)"
oc apply -f manifests/rhoai-operator/13-observability-rbac-podmonitors.yaml >/dev/null
ok "Observability RBAC + PodMonitor mirrors applied"

echo ""
ok "Observability stage complete."
info "In the OpenShift AI dashboard: Observe & Monitor → Dashboard."
info "Observed live on this build: Cluster / Models plus additional LLM/MaaS-related tabs can appear."
info "Important limitation: the built-in 'Usage' view may still stay partially empty on this build even"
info "after real traffic, because the underlying metrics do not consistently carry the user-level labels"
info "that its PromQL queries expect. Treat 'Models' as reliable, and use 'make demo2-check-usage' as the"
info "ground-truth admin check for MaaS-specific counters."
