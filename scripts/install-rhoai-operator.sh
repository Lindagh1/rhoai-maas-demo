#!/usr/bin/env bash
# install-rhoai-operator.sh - Install the base Red Hat OpenShift AI (RHOAI)
# operator + a minimal default DataScienceCluster on a cluster that does NOT
# already have RHOAI installed (unlike the sandbox used by scripts/bootstrap.sh,
# which assumes RHOAI is pre-installed).
#
# Idempotent: safe to re-run. Only touches:
#   - namespace/redhat-ods-operator (OLM Subscription + OperatorGroup)
#   - DSCInitialization/default-dsci (auto-created by the operator)
#   - DataScienceCluster/default-dsc (created here with a conservative,
#     dependency-free component set: dashboard, workbenches, kserve,
#     aipipelines, modelregistry, trainingoperator, trustyai, ray).
#     kueue / feastoperator / mlflowoperator / sparkoperator /
#     llamastackoperator / mcplifecycleoperator / ogx / aigateway are left
#     Removed since they need extra operators (Kueue, Connectivity Link,
#     LeaderWorkerSet, etc.) that are out of scope for a base install check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_login

MANIFEST_DIR="$MANIFESTS/rhoai-operator"

info "Applying namespace + OperatorGroup + Subscription (redhat-ods-operator, channel stable-3.x)"
oc apply -f "$MANIFEST_DIR/01-namespace.yaml"
oc apply -f "$MANIFEST_DIR/02-operatorgroup.yaml"
oc apply -f "$MANIFEST_DIR/03-subscription.yaml"

info "Waiting for the rhods-operator CSV to reach Succeeded (timeout 5m)..."
for i in $(seq 1 20); do
  CSV=$(oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
  if [[ -n "$CSV" ]]; then
    PHASE=$(oc get csv "$CSV" -n redhat-ods-operator -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$PHASE" == "Succeeded" ]]; then ok "CSV $CSV Succeeded"; break; fi
    if [[ "$PHASE" == "Failed" ]]; then err "CSV $CSV Failed"; exit 1; fi
  fi
  if [[ "$i" == "20" ]]; then err "Timed out waiting for CSV"; exit 1; fi
  sleep 15
done

info "Waiting for DSCInitialization/default-dsci to be Ready (auto-created by the operator)..."
for i in $(seq 1 12); do
  PHASE=$(oc get dsci default-dsci -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$PHASE" == "Ready" ]] && { ok "DSCI Ready"; break; }
  [[ "$i" == "12" ]] && { err "Timed out waiting for DSCI"; exit 1; }
  sleep 10
done

info "Applying default DataScienceCluster (dashboard, workbenches, kserve, aipipelines, modelregistry, trainingoperator, trustyai, ray = Managed)"
oc apply -f "$MANIFEST_DIR/04-dsc.yaml"

info "Waiting for DataScienceCluster/default-dsc to be Ready (timeout ~4m)..."
for i in $(seq 1 16); do
  PHASE=$(oc get dsc default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$PHASE" == "Ready" ]] && { ok "DSC Ready"; break; }
  [[ "$i" == "16" ]] && { warn "DSC not Ready after 4m, check 'oc get dsc default-dsc -o yaml'"; break; }
  sleep 15
done

DASH_HOST=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || true)
ok "RHOAI installation complete. Dashboard: https://${DASH_HOST:-<pending>}"
