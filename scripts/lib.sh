#!/usr/bin/env bash
# Shared helpers sourced by every Publier script.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # used by scripts that source this lib (install-*.sh)
MANIFESTS="$REPO_ROOT/manifests"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

require_login() {
  if ! oc whoami &>/dev/null; then
    err "Not logged into an OpenShift cluster. Run 'oc login' in your terminal (do not paste tokens into chat)."
    exit 1
  fi
  local server
  server=$(oc whoami --show-server 2>/dev/null || true)
  info "Authenticated as $(oc whoami) @ ${server}"
}

assert_sandbox() {
  local server
  server=$(oc whoami --show-server 2>/dev/null || true)
  if [[ "$server" != *sandbox* && "${ALLOW_NON_SANDBOX:-}" != "1" ]]; then
    err "Server '$server' does not look like a disposable sandbox. Set ALLOW_NON_SANDBOX=1 to override."
    exit 2
  fi
}

# Discover the MaaS infrastructure namespace (never hardcode after tenant exists).
infra_namespace() {
  local ns
  ns=$(oc get maastenantconfig default-tenant -n models-as-a-service \
        -o jsonpath='{.status.infraNamespace}' 2>/dev/null || true)
  if [[ -z "$ns" ]]; then
    ns=$(oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service \
          -o jsonpath='{.status.infraNamespace}' 2>/dev/null || true)
  fi
  echo "${ns:-redhat-ai-gateway-infra}"
}

cluster_domain() {
  oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
}

cert_name() {
  local c
  c=$(oc get ingresscontroller default -n openshift-ingress-operator \
       -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null || true)
  if [[ -z "$c" ]]; then
    if oc get secret cert-manager-ingress-cert -n openshift-ingress &>/dev/null; then
      c=cert-manager-ingress-cert
    else
      c=router-certs-default
    fi
  fi
  echo "$c"
}

maas_hostname() {
  echo "maas.$(cluster_domain)"
}

maas_host_url() {
  echo "https://$(maas_hostname)"
}

wait_csv_succeeded() {
  local ns="$1" label="$2" timeout_s="${3:-300}"
  local end=$((SECONDS + timeout_s))
  local phase=""
  while (( SECONDS < end )); do
    phase=$(oc get csv -n "$ns" -l "$label" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
    [[ "$phase" == "Succeeded" ]] && { ok "CSV Succeeded ($label)"; return 0; }
    sleep 10
  done
  err "CSV did not Succeed within ${timeout_s}s (phase=${phase:-unknown})"
  return 1
}

gpu_free_count() {
  python3 - <<'PYGPU'
import json, subprocess
nodes=json.loads(subprocess.check_output(['oc','get','nodes','-o','json']))['items']
pods=json.loads(subprocess.check_output(['oc','get','pods','-A','-o','json']))['items']
capacity=sum(int(n['status'].get('allocatable',{}).get('nvidia.com/gpu',0)) for n in nodes if not n.get('spec',{}).get('unschedulable'))
used=0
for p in pods:
 if p.get('status',{}).get('phase') in ('Succeeded','Failed'): continue
 spec=p.get('spec',{})
 gpu=lambda c:int(c.get('resources',{}).get('requests',{}).get('nvidia.com/gpu',0))
 used+=max(sum(map(gpu,spec.get('containers',[]))),max(map(gpu,spec.get('initContainers',[])),default=0))
print(max(0,capacity-used))
PYGPU
}
