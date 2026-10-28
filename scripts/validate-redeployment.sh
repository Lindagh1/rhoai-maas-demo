#!/usr/bin/env bash
# Read-only, non-destructive validation of the full redeployment kit
# (Demo 1 + Demo 2 + observability) against the CURRENTLY logged-in
# cluster, WITHOUT applying or mutating anything.
#
# Two things are checked, separately classified:
#   1. Operator catalog availability (packagemanifest lookups) -- tells you
#      whether a brand-new sandbox's OperatorHub even offers the required
#      channels, independent of whether they are installed here.
#   2. `oc apply --dry-run=server` for every ACTIVE manifest in the kit --
#      proves the YAML itself is valid against the live API server's CRD
#      schemas. A dry-run failure because a CRD/API group does not exist
#      yet (expected on a fresh, not-yet-bootstrapped sandbox) is reported
#      as SKIP, not FAIL -- it means "run the prerequisite script first",
#      not "this manifest is broken".
#
# Deliberately excludes manifests/maas/maas-subscription.yaml and
# manifests/maas/maas-auth-policy.yaml (orphaned, not part of the active
# kit -- see README.md) and anything under openshift-ai-demo/,
# manifests/fraud-detection-tutorial/, manifests/workbench-vscode-demo/
# (historical, unrelated demos).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck disable=SC1091
source scripts/lib.sh

require_login
echo "=============================================="
echo "Redeployment kit — validation (read-only, no mutation)"
echo "=============================================="
info "Target: $(oc whoami) @ $(oc whoami --show-server)"

FAIL=0
SKIP=0

echo
echo "--- 1. Operator catalog availability ---"
declare -A PACKAGES=(
  [rhcl-operator]="RHCL (Kuadrant/Authorino dependency, used stable-1.4)"
  [authorino-operator]="Authorino Operator"
  [cluster-observability-operator]="Cluster Observability Operator (COO)"
  [opentelemetry-product]="Red Hat build of OpenTelemetry"
  [rhods-operator]="Red Hat OpenShift AI"
)
for pkg in "${!PACKAGES[@]}"; do
  CHANNELS=$(oc get packagemanifest "$pkg" -n openshift-marketplace \
    -o jsonpath='{.status.channels[*].name}' 2>/dev/null || true)
  if [[ -n "$CHANNELS" ]]; then
    ok "$pkg (${PACKAGES[$pkg]}) — channels: $CHANNELS"
  else
    err "$pkg (${PACKAGES[$pkg]}) — NOT found in openshift-marketplace catalog on this cluster"
    FAIL=1
  fi
done

echo
echo "--- 2. Manifest dry-run (server-side, against live CRDs) ---"

dry_run_file() {
  local file="$1"
  local out
  # Plain client-side dry-run=server (NOT --server-side=true): this mirrors
  # exactly how the real scripts apply these manifests (`oc apply -f ...`,
  # no server-side-apply flag). Using --server-side here would trigger
  # unrelated field-manager ownership conflicts against objects already
  # owned by other controllers (e.g. the authorino-operator CSV), which is
  # not representative of what the actual bootstrap scripts do.
  if out=$(oc apply --dry-run=server -f "$file" 2>&1); then
    ok "dry-run OK: $file"
  else
    if echo "$out" | grep -qiE 'no matches for kind|the server doesn.t have a resource type|could not find the requested resource'; then
      warn "SKIP (CRD/API not installed yet on this cluster): $file"
      SKIP=1
    else
      err "dry-run FAILED: $file"
      echo "$out" | sed 's/^/    /'
      FAIL=1
    fi
  fi
}

dry_run_templated_file() {
  local tmpl="$1"
  local rendered
  rendered=$(mktemp)
  CLUSTER_DOMAIN=$(cluster_domain)
  CERT_NAME=$(cert_name)
  MAAS_HOSTNAME=$(maas_hostname)
  export CLUSTER_DOMAIN CERT_NAME MAAS_HOSTNAME
  envsubst '${MAAS_HOSTNAME} ${CERT_NAME}' < "$tmpl" > "$rendered"
  dry_run_file "$rendered"
  rm -f "$rendered"
}

# Demo 1 — platform prerequisites + MaaS enablement
for f in manifests/platform/01-gatewayclass.yaml \
         manifests/platform/02-kuadrant-namespace.yaml \
         manifests/platform/03-rhcl-operator-subscription.yaml \
         manifests/platform/04-authorino-service-annotation.yaml \
         manifests/platform/05-kuadrant.yaml \
         manifests/platform/06-gateway-resources.yaml \
         manifests/platform/08-postgres-pvc.yaml \
         manifests/platform/09-postgres-deployment.yaml \
         manifests/platform/10-postgres-service.yaml \
         manifests/platform/11-user-workload-monitoring.yaml; do
  [[ -f "$f" ]] && dry_run_file "$f"
done
[[ -f manifests/platform/07-gateway.yaml.tmpl ]] && dry_run_templated_file manifests/platform/07-gateway.yaml.tmpl

# Demo 1 — model + MaaS publication
[[ -f manifests/model/namespace.yaml ]] && dry_run_file manifests/model/namespace.yaml
dry_run_file manifests/model/llminferenceservice.yaml
dry_run_file manifests/maas/maas-model-ref.yaml

# Observability (COO + OTel operator install + RBAC/PodMonitor drift fix)
for f in manifests/rhoai-operator/11-cluster-observability-operator.yaml \
         manifests/rhoai-operator/12-opentelemetry-operator.yaml \
         manifests/rhoai-operator/13-observability-rbac-podmonitors.yaml; do
  [[ -f "$f" ]] && dry_run_file "$f"
done

# Demo 2 — governance + RBAC
for f in manifests/demo2/10-maas-subscription.yaml \
         manifests/demo2/11-maas-authpolicy.yaml \
         manifests/demo2/12-maas-subscription-ratelimit-test.yaml \
         manifests/demo2/13-user-dashboard-rbac.yaml; do
  [[ -f "$f" ]] && dry_run_file "$f"
done

echo
echo "=============================================="
if [[ "$FAIL" == "1" ]]; then
  err "Validation found real failures (see above) — fix before trusting the kit on a new sandbox."
elif [[ "$SKIP" == "1" ]]; then
  warn "Validation passed, with some manifests SKIPPED because their CRDs/operators are not installed on THIS cluster yet."
  warn "That is expected if you are running this before scripts/10-prerequisites.sh / scripts/20-enable-maas.sh."
else
  ok "All manifests passed server-side dry-run against the live cluster. No mutation was made."
fi
echo "=============================================="
exit "$FAIL"
