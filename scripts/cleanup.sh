#!/usr/bin/env bash
# cleanup.sh - Remove ONLY demo-specific resources (make cleanup).
#
# Keeps the MaaS platform itself (Kuadrant/Authorino/Limitador, GatewayClass,
# maas-default-gateway, PostgreSQL, default-tenant, DSC MaaS enablement)
# intact and ready for another demo, per explicit instruction. Safe to run
# twice in a row.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
source scripts/api_key.sh 2>/dev/null || true
require_login

echo "=============================================="
echo "RHOAI MAAS DEMO CLEANUP"
echo "=============================================="

# Revoke the demo API key (best-effort; management API accepts the OIDC token)
if [[ -f .env.local ]]; then
  # shellcheck disable=SC1091
  source .env.local
  if [[ -n "${MAAS_API_KEY_ID:-}" ]]; then
    HOST="${MAAS_URL:-$(maas_host_url)}"
    curl -sSk --connect-timeout 10 --max-time 20 \
      -H "Authorization: Bearer $(oc whoami -t)" \
      -X DELETE "${HOST}/maas-api/v1/api-keys/${MAAS_API_KEY_ID}" >/dev/null 2>&1 || true
    echo "Demo API key          REVOKED (best-effort)"
  else
    echo "Demo API key          NOT APPLICABLE"
  fi
  rm -f .env.local
else
  echo "Demo API key          NOT APPLICABLE"
fi

# MaaS governance objects (namespace: models-as-a-service, shared platform ns —
# only OUR named objects are deleted, nothing else in that namespace is touched)
oc delete maassubscription maas-demo-subscription -n models-as-a-service --ignore-not-found=true \
  && echo "MaaSSubscription       REMOVED" || echo "MaaSSubscription       REMOVE FAILED"
oc delete maasauthpolicy maas-demo-access -n models-as-a-service --ignore-not-found=true \
  && echo "MaaSAuthPolicy         REMOVED" || echo "MaaSAuthPolicy         REMOVE FAILED"

# MaaSModelRef + model + namespace (cascades: LLMInferenceService, HTTPRoute, pods, SAs)
oc delete maasmodelref demo-simulator -n rhoai-maas-demo --ignore-not-found=true 2>/dev/null || true
oc delete namespace rhoai-maas-demo --ignore-not-found=true --wait=true --timeout=120s \
  && echo "Demo namespace         REMOVED" || echo "Demo namespace         REMOVE FAILED/ALREADY GONE"

echo ""
echo "Shared MaaS infra       UNCHANGED (Kuadrant/Authorino/Limitador/Gateway/PostgreSQL/default-tenant kept for reuse)"
echo "RHOAI                   UNCHANGED"
echo "Kuadrant                UNCHANGED"
echo "Authorino               UNCHANGED"
echo "Gateway                 UNCHANGED"
echo ""
echo "=============================================="
echo "RESULT                  CLEAN"
echo "=============================================="

echo ""
echo "Verification:"
oc get namespace rhoai-maas-demo 2>&1 | tail -1
oc get maasmodelref -A 2>&1 | tail -1
oc get maassubscription -A 2>&1 | tail -1
oc get maasauthpolicy -A 2>&1 | tail -1
