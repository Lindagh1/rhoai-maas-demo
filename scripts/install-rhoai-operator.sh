#!/usr/bin/env bash
# install-rhoai-operator.sh - Install Red Hat OpenShift AI (RHOAI) with ALL
# DataScienceCluster components Managed/Unmanaged (nothing left Removed) and
# every OdhDashboardConfig feature flag turned on/visible, on a cluster that
# does NOT already have RHOAI installed (unlike the sandbox used by
# scripts/bootstrap.sh, which assumes RHOAI is pre-installed).
#
# Idempotent: safe to re-run. Installs:
#   - rhods-operator (redhat-ods-operator ns, channel stable-3.x)
#   - rhcl-operator / Red Hat Connectivity Link (openshift-operators ns) --
#     satisfies Kserve LLMInferenceService's Connectivity Link dependency
#   - leader-worker-set (openshift-lws-operator ns) -- satisfies Kserve
#     LLMInferenceService's Wide EP / LeaderWorkerSet dependency
#   - kueue-operator / Red Hat build of Kueue (openshift-operators ns) --
#     backs the DSC's kueue component (set to Unmanaged, see note below)
#   - job-set / JobSet Operator (openshift-jobset-operator ns) + a
#     JobSetOperator/cluster CR -- required precondition for the Trainer
#     component
# Then creates/patches:
#   - DSCInitialization/default-dsci (auto-created by the operator)
#   - DataScienceCluster/default-dsc: every component Managed, except
#     kueue=Unmanaged (its "Managed" value is rejected by the admission
#     webhook on this operator version -- kept in the CRD enum only for OLM
#     upgrade backwards-compat) and llamastackoperator=Removed (deprecated,
#     mutually exclusive with ogx=Managed).
#   - OdhDashboardConfig/odh-dashboard-config: every disable* flag set to
#     false and every feature-enablement flag set to true, so all of the
#     above is visible in the dashboard nav (excludes 3 DEPRECATED fields
#     the webhook refuses to accept a value for: disableAcceleratorProfiles,
#     disableHardwareProfiles, disableFineTuning).
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

info "Installing extra dependency operators (rhcl-operator, kueue-operator, leader-worker-set, job-set)..."
oc apply -f "$MANIFEST_DIR/05-rhcl-operator-subscription.yaml"
oc apply -f "$MANIFEST_DIR/06-kueue-operator-subscription.yaml"
oc apply -f "$MANIFEST_DIR/07-lws-operator.yaml"
oc apply -f "$MANIFEST_DIR/09-jobset-operator.yaml"

info "Waiting for job-set CSV to reach Succeeded (needed before the JobSetOperator CR)..."
for i in $(seq 1 15); do
  CSV=$(oc get subscription job-set -n openshift-jobset-operator -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
  if [[ -n "$CSV" ]]; then
    PHASE=$(oc get csv "$CSV" -n openshift-jobset-operator -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Succeeded" ]] && { ok "job-set CSV Succeeded"; break; }
  fi
  [[ "$i" == "15" ]] && warn "job-set CSV not Succeeded after 2.5m, continuing anyway"
  sleep 10
done
oc apply -f "$MANIFEST_DIR/10-jobset-cr.yaml"

info "Applying DataScienceCluster with ALL components Managed (kueue=Unmanaged, llamastackoperator=Removed)"
oc apply -f "$MANIFEST_DIR/04-dsc.yaml"

info "Applying OdhDashboardConfig with all disable* flags = false and all feature flags = true"
oc apply -f "$MANIFEST_DIR/08-dashboard-config.yaml"

info "Waiting for DataScienceCluster/default-dsc to be Ready (timeout ~6m; the Trainer/JobSet dependency can take a few extra reconciles)..."
for i in $(seq 1 24); do
  PHASE=$(oc get dsc default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$PHASE" == "Ready" ]] && { ok "DSC Ready"; break; }
  [[ "$i" == "24" ]] && { warn "DSC not Ready after 6m, check 'oc get dsc default-dsc -o yaml'"; break; }
  sleep 15
done

echo
info "Non-Ready conditions (should be empty if fully Ready):"
oc get dsc default-dsc -o jsonpath='{range .status.conditions[?(@.status!="True")]}{.type}: {.status} - {.message}{"\n"}{end}' || true

DASH_HOST=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || true)
ok "RHOAI installation complete. Dashboard: https://${DASH_HOST:-<pending>}"
