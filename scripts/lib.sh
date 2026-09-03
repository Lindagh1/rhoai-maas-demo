#!/usr/bin/env bash
# Shared helpers sourced by every script in this repo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS="$REPO_ROOT/manifests"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

require_login() {
  if ! oc whoami &>/dev/null; then
    err "Not logged into an OpenShift cluster. Run 'oc login' first."
    exit 1
  fi
}

# Discover the MaaS infrastructure namespace declaratively (never hardcoded).
# Falls back to the documented RHOAI 3.5+ default only if the Tenant/
# MaasTenantConfig resources don't exist yet (e.g. before Phase 6/7 runs).
infra_namespace() {
  local ns
  ns=$(oc get maastenantconfig default-tenant -n models-as-a-service \
        -o jsonpath='{.status.infraNamespace}' 2>/dev/null || true)
  echo "${ns:-redhat-ai-gateway-infra}"
}

cluster_domain() {
  oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
}

cert_name() {
  local c
  c=$(oc get ingresscontroller default -n openshift-ingress-operator \
       -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null || true)
  echo "${c:-router-certs-default}"
}

maas_hostname() {
  echo "maas.$(cluster_domain)"
}

maas_host_url() {
  echo "https://$(maas_hostname)"
}
