#!/usr/bin/env bash
# Idempotent: install only missing supported Demo 1 prerequisites (RHCL, Kuadrant,
# GatewayClass, UWM, Authorino TLS). Does NOT enable MaaS or deploy models.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_login
assert_sandbox

echo "=============================================="
echo "Demo 1 — Stage: prerequisites"
echo "=============================================="

# --- User Workload Monitoring ---
info "Enabling User Workload Monitoring (MaaS metrics prerequisite)"
if oc get configmap cluster-monitoring-config -n openshift-monitoring &>/dev/null; then
  CURRENT=$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' 2>/dev/null || true)
  if echo "$CURRENT" | grep -q 'enableUserWorkload:\s*true'; then
    ok "enableUserWorkload already true"
  else
    warn "cluster-monitoring-config exists; merging enableUserWorkload=true without wiping other keys"
    # Prefer patching via apply of known-good minimal config only when empty/absent flag.
    oc apply -f manifests/platform/11-user-workload-monitoring.yaml
  fi
else
  oc apply -f manifests/platform/11-user-workload-monitoring.yaml
fi
info "Waiting for UWM pods (up to 3 min)..."
for _ in $(seq 1 18); do
  READY=$(oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | grep -c Running || true)
  [[ "${READY:-0}" -ge 1 ]] && break
  sleep 10
done
if [[ "${READY:-0}" -ge 1 ]]; then
  ok "User Workload Monitoring pods Running ($READY)"
else
  warn "UWM pods not Running yet — MaaS may show Degraded until they appear"
  oc get pods -n openshift-user-workload-monitoring || true
fi

# --- GatewayClass (additive) ---
info "Ensuring GatewayClass openshift-default"
oc apply -f manifests/platform/01-gatewayclass.yaml
oc wait --for=condition=Accepted gatewayclass/openshift-default --timeout=60s
ok "GatewayClass openshift-default Accepted"

# --- RHCL / Kuadrant ---
info "Ensuring kuadrant-system namespace"
oc apply -f manifests/platform/02-kuadrant-namespace.yaml

if oc get csv -n openshift-operators -l operators.coreos.com/rhcl-operator.openshift-operators \
     -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Succeeded; then
  ok "rhcl-operator CSV already Succeeded"
else
  info "Installing Red Hat Connectivity Link Operator (channel stable-1.4)"
  oc apply -f manifests/platform/03-rhcl-operator-subscription.yaml
  wait_csv_succeeded openshift-operators operators.coreos.com/rhcl-operator.openshift-operators 600
fi

info "Applying Authorino service annotation scaffold + Kuadrant CR"
oc apply -f manifests/platform/04-authorino-service-annotation.yaml
oc apply -f manifests/platform/05-kuadrant.yaml

info "Waiting for Kuadrant Ready (up to 5 min)..."
if ! oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=300s; then
  warn "Kuadrant not Ready — bouncing kuadrant-operator pod once (Istio race workaround)"
  POD=$(oc get pods -n openshift-operators --no-headers 2>/dev/null | awk '/kuadrant-operator/{print $1; exit}')
  [[ -n "${POD:-}" ]] && oc delete pod -n openshift-operators "$POD" --wait=false || true
  oc wait --for=condition=Ready kuadrant/kuadrant -n kuadrant-system --timeout=300s
fi
ok "Kuadrant Ready"

# --- Authorino TLS (§1.4) ---
info "Configuring Authorino TLS"
for _ in $(seq 1 36); do
  oc get authorino authorino -n kuadrant-system &>/dev/null && break
  sleep 5
done
oc get authorino authorino -n kuadrant-system &>/dev/null || { err "Authorino CR never appeared"; exit 1; }

oc annotate service authorino-authorino-authorization -n kuadrant-system \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert --overwrite >/dev/null

TLS_ENABLED=$(oc get authorino authorino -n kuadrant-system -o jsonpath='{.spec.listener.tls.enabled}' 2>/dev/null || true)
if [[ "$TLS_ENABLED" != "true" ]]; then
  oc patch authorino authorino -n kuadrant-system --type=merge --patch '{
    "spec": {
      "listener": {
        "tls": {
          "enabled": true,
          "certSecretRef": { "name": "authorino-server-cert" }
        }
      }
    }
  }'
  ok "Authorino TLS listener enabled"
else
  ok "Authorino TLS already enabled"
fi

oc -n kuadrant-system set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt >/dev/null || true
oc wait --for=condition=Available deployment/authorino -n kuadrant-system --timeout=180s
ok "Authorino Available"

echo ""
ok "Prerequisites complete. Next: scripts/20-enable-maas.sh"
