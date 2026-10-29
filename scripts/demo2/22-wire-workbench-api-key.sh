#!/usr/bin/env bash
# Demo 2 — Étape 3bis support: wire a captured end-user API key into an
# EXISTING dashboard-created Workbench (Notebook CR) as an env var, without
# ever printing the key value.
#
# Real finding this script codifies (see GUIDE.md §9,
# "Workbench 'Environment variables' step... doesn't actually apply"): the
# Create-workbench wizard's own "Environment variables" step was observed to
# silently drop the variable on this RHOAI 3.5.2 build -- no Secret was
# created, no env entry was added to the Notebook's pod spec. The fix proven
# live is to create the Secret explicitly and JSON-patch the Notebook.
#
# This script intentionally does NOT create the Workbench itself -- that
# remains a deliberate, documented MANUAL dashboard step (Projects -> Create
# workbench), because fully replicating RHOAI's dashboard-managed Notebook
# wiring (image, PVC, kube-rbac-proxy sidecar, ServiceAccount, HTTPRoute,
# etc.) from raw YAML was never verified end-to-end in this project -- only
# patching an already-dashboard-created Notebook was. Per project standing
# practice, we only automate what was actually proven to work.
#
# Usage:
#   scripts/demo2/22-wire-workbench-api-key.sh <namespace> <notebook-name> <keyfile> [env-var-name]
#
# Example:
#   scripts/demo2/22-wire-workbench-api-key.sh rhoai-maas-demo \
#     data-scientist-workbench secrets/demo2/maas-demo2-user.apikey DEMO2_API_KEY
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

NAMESPACE="${1:?usage: $0 <namespace> <notebook-name> <keyfile> [env-var-name]}"
NOTEBOOK="${2:?usage: $0 <namespace> <notebook-name> <keyfile> [env-var-name]}"
KEY_FILE="${3:?usage: $0 <namespace> <notebook-name> <keyfile> [env-var-name]}"
ENV_VAR_NAME="${4:-DEMO2_API_KEY}"
SECRET_NAME="demo2-api-key"

require_login
[[ -f "$KEY_FILE" ]] || { err "No such key file: $KEY_FILE"; exit 1; }

API_KEY="$(read_api_key_file "$KEY_FILE" 2>/dev/null || true)"
[[ -n "$API_KEY" ]] || { err "Could not extract a valid API key from $KEY_FILE."; exit 1; }

oc get notebook "$NOTEBOOK" -n "$NAMESPACE" &>/dev/null || {
  err "Notebook '$NOTEBOOK' not found in '$NAMESPACE' — create the workbench from the dashboard first (Projects -> ${NAMESPACE} -> Workbenches -> Create workbench)."
  exit 1
}

echo "=============================================="
echo "Demo 2 — wire API key into workbench"
echo "=============================================="
info "Namespace: $NAMESPACE  Notebook: $NOTEBOOK  Env var: $ENV_VAR_NAME"

info "Ensuring Secret/$SECRET_NAME (value never printed)"
oc create secret generic "$SECRET_NAME" -n "$NAMESPACE" \
  --from-literal="${ENV_VAR_NAME}=${API_KEY}" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null
unset API_KEY
ok "Secret/$SECRET_NAME up to date"

HAS_ENV=$(oc get notebook "$NOTEBOOK" -n "$NAMESPACE" \
  -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='${ENV_VAR_NAME}')].name}" 2>/dev/null || true)

if [[ "$HAS_ENV" == "$ENV_VAR_NAME" ]]; then
  ok "Notebook already has env var ${ENV_VAR_NAME} wired — patching Secret only (no restart needed)."
else
  info "Patching Notebook to add env var ${ENV_VAR_NAME} (this restarts the workbench pod)"
  oc patch notebook "$NOTEBOOK" -n "$NAMESPACE" --type=json -p "[
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/env/-\",
     \"value\": {\"name\": \"${ENV_VAR_NAME}\",
                 \"valueFrom\": {\"secretKeyRef\": {\"name\": \"${SECRET_NAME}\", \"key\": \"${ENV_VAR_NAME}\"}}}}
  ]"
  ok "Notebook patched — pod is restarting"
fi

echo
info "Verify once Running: in the workbench terminal, run: echo \"\${#${ENV_VAR_NAME}}\" (should be > 0, never echo the value itself)"
