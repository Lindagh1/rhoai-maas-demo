#!/usr/bin/env bash
# READ-ONLY discovery for an authenticated Red Hat OpenShift sandbox.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/docs/sandbox-audit-raw.txt"
mkdir -p "$(dirname "$OUT")"
if ! command -v oc >/dev/null 2>&1; then
  echo 'ERROR: oc CLI not available. Install it and authenticate to your sandbox.' >&2
  exit 2
fi
if ! oc whoami >/dev/null 2>&1; then
  echo 'ERROR: oc session not authenticated. Run oc login in the sandbox terminal.' >&2
  exit 2
fi
umask 077
: > "$OUT"
run() {
  { printf '\n===== '; printf '%q ' "$@"; printf '=====\n'; "$@"; } >> "$OUT" 2>&1 || printf 'WARN: command failed (may not be installed / RBAC)
' >> "$OUT"
}
# NOTE: output has environment identifiers and should stay local; NEVER paste tokens / secrets.
run oc whoami
run oc whoami --show-server
run oc version
run oc get clusterversion
run oc get nodes -o wide
run oc get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory
# GPU is a cluster-wide constrained resource: allocatable != free. Compute the
# actually-schedulable headroom so the plan never assumes a model fits just
# because a GPU exists on some node (see CURSOR_PROMPT_DEMO1.md Stage A).
run bash -c '
  echo "Per-node nvidia.com/gpu allocated vs allocatable:"
  for n in $(oc get nodes -o jsonpath="{.items[*].metadata.name}"); do
    alloc=$(oc get node "$n" -o jsonpath="{.status.allocatable.nvidia\.com/gpu}")
    [[ -z "$alloc" || "$alloc" == "0" ]] && continue
    used=$(oc get pods -A --field-selector="spec.nodeName=$n" -o json 2>/dev/null \
      | python3 -c "
import json,sys
d=json.load(sys.stdin)
n=0
for p in d[\"items\"]:
    if p[\"status\"].get(\"phase\") in (\"Succeeded\",\"Failed\"):
        continue
    for c in p.get(\"spec\",{}).get(\"containers\",[]):
        n += int(c.get(\"resources\",{}).get(\"requests\",{}).get(\"nvidia.com/gpu\",0) or 0)
print(n)
" 2>/dev/null || echo "?")
    echo "  node=$n allocatable=$alloc used=$used"
  done
'
run oc get namespaces
run oc get subscription.operators.coreos.com -A
run oc get csv -A
run oc get dsc
run oc get dsci -A
run oc get odhdashboardconfig -A
run oc get kuadrant -A
run oc get gatewayclass
run oc get gateway -A
run oc get storageclass
run oc get hardwareprofile -A
run oc get llminferenceservices -A
run oc get maasmodelrefs -A
run oc get maastenantconfig -A
run oc get aitenant -A
run oc get pods -n kuadrant-system
run oc get pods -n redhat-ai-gateway-infra
run oc get pods -n redhat-ods-applications
run oc get dsc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{.spec.components.aigateway}{"\n"}{.status.conditions}{"\n"}{end}'
run oc get odhdashboardconfig -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,MAAS:.spec.dashboardConfig.modelAsService,GENAI:.spec.dashboardConfig.genAiStudio
run oc get maastenantconfig default-tenant -n models-as-a-service -o jsonpath='{.status.infraNamespace}'
# Secret metadata presence ONLY. No -o yaml / JSON data.
run oc get secret maas-db-config -n redhat-ai-gateway-infra -o name
run oc auth can-i create namespaces
run oc auth can-i create llminferenceservices.serving.kserve.io -A
run oc auth can-i create maasmodelrefs.maas.opendatahub.io -A
printf 'Audit saved to %s\nReview and redact environment-specific details before sharing.\n' "$OUT"
