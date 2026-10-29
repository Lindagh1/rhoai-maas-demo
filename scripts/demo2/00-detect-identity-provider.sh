#!/usr/bin/env bash
# Demo 2 — read-only identity-provider detection.
# Different RHOAI sandboxes (e.g. the partner's own cluster) will not
# necessarily have the same IdP technology as the one this repo was first
# built against. This script never mutates anything; it only reports what
# strategy scripts/demo2/01-create-test-identity.sh would use.
# NOTE: -e is deliberately omitted. This is a read-only detection script that
# inspects resources which may or may not exist; non-zero exits from `oc get`
# are expected, not errors.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

require_login
echo "=============================================="
echo "Demo 2 — Identity provider detection (read-only)"
echo "=============================================="

oc get oauth cluster -o jsonpath='{range .spec.identityProviders[*]}- name={.name} type={.type}{"\n"}{end}' 2>/dev/null

STRATEGY=$(detect_idp_strategy)
echo
info "Detected strategy: $STRATEGY"
case "$STRATEGY" in
  htpasswd)
    IDP_NAME=$(htpasswd_idp_name)
    SECRET_NAME=$(htpasswd_secret_name "$IDP_NAME")
    ok "HTPasswd identity provider '$IDP_NAME' found (secret: openshift-config/$SECRET_NAME)."
    echo "  -> 01-create-test-identity.sh will append '${DEMO2_USER}' to this existing secret (additive, no other users touched)."
    ;;
  keycloak-incluster)
    ok "In-cluster Keycloak detected, backing the only configured OIDC provider."
    echo "  -> 01-create-test-identity.sh will create '${DEMO2_USER}' via the Keycloak Admin API,"
    echo "     after verifying the realm is sandbox-scoped (single client, in-cluster)."
    ;;
  oidc-other)
    warn "An OpenID/OIDC identity provider is configured, but it does NOT look like an in-cluster"
    warn "Keycloak this script can safely administer (external issuer, or Keycloak Operator/CR not found)."
    echo "  -> This is very likely an enterprise IdP (e.g. Red Hat SSO, Entra ID, Okta) shared beyond this sandbox."
    echo "  -> 01-create-test-identity.sh will REFUSE to mutate it and will print a manual procedure instead."
    echo "     See GUIDE.md §11.5 (external OIDC path)."
    ;;
  none)
    warn "No identityProviders configured on oauth/cluster (only kubeadmin / SA tokens, or cluster-bootstrap state)."
    echo "  -> 01-create-test-identity.sh will REFUSE to add a new HTPasswd provider unless you explicitly set"
    echo "     ADD_HTPASSWD_IDP=yes (this is a cluster-level auth config change)."
    ;;
esac
echo
info "Re-run this anytime: bash scripts/demo2/00-detect-identity-provider.sh"
