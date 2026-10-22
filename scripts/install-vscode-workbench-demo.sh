#!/usr/bin/env bash
# install-vscode-workbench-demo.sh - Deploy a demo VS Code (code-server)
# RHOAI workbench declaratively (Namespace/Data-Science-Project + PVC +
# Notebook CR), then wait for it to become Ready and print the browsable URL.
#
# Idempotent: safe to re-run. Requires RHOAI's `workbenches` component to be
# Managed (see scripts/install-rhoai-operator.sh) and the code-server-notebook
# ImageStream to exist in the applications namespace.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_login

MANIFEST_DIR="$MANIFESTS/workbench-vscode-demo"
NS=vscode-demo
NAME=vscode-demo

info "Applying Namespace (Data Science Project) + PVC + Notebook CR"
oc apply -f "$MANIFEST_DIR/01-namespace.yaml"
oc apply -f "$MANIFEST_DIR/02-pvc.yaml"
oc apply -f "$MANIFEST_DIR/03-notebook.yaml"

info "Waiting for pod $NAME-0 to become Ready (timeout ~3m; first pull can be slow)..."
for i in $(seq 1 18); do
  READY=$(oc get pod "$NAME-0" -n "$NS" -o jsonpath='{.status.containerStatuses[?(@.name=="'"$NAME"'")].ready}' 2>/dev/null || true)
  if [[ "$READY" == "true" ]]; then ok "Pod Ready"; break; fi
  [[ "$i" == "18" ]] && { warn "Pod not Ready after 3m, check 'oc get pod $NAME-0 -n $NS' / 'oc logs $NAME-0 -n $NS'"; break; }
  sleep 10
done

# The workbench is exposed via a Gateway API HTTPRoute (nb-<ns>-<name> in the
# RHOAI applications namespace) attached to the same Gateway that backs the
# RHOAI dashboard itself -- NOT a classic per-notebook Route. Resolve the
# externally-reachable hostname from the Route that fronts that Gateway.
GW_ROUTE_HOST=$(oc get route -n openshift-ingress -o jsonpath='{range .items[*]}{.spec.to.name}{" "}{.spec.host}{"\n"}{end}' \
  | awk '/data-science-gateway/ {print $2}' | head -1)
ok "VS Code workbench deployed. Pod: 2/2 (workbench + kube-rbac-proxy)."
ok "Open: https://${GW_ROUTE_HOST:-<gateway route not found>}/notebook/${NS}/${NAME}/"
info "(You'll be redirected through OpenShift OAuth login -- normal, expected behavior.)"
