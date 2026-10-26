#!/usr/bin/env bash
# Demo 2 — consolidated, read-only audit. Safe to run on any sandbox,
# at any time, before/after any other demo2 script. Never mutates
# anything, never prints a secret value.
# NOTE: -e is deliberately omitted. Audit probes resources that may not exist
# yet (group, identity, governance CRs, secret files) and reports their
# presence/absence — every `oc get` failure is an expected, informational
# branch, not an error.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

require_login
echo "=============================================="
echo "Demo 2 — Consolidated audit (read-only)"
echo "=============================================="

echo
echo "--- 1. Identity provider strategy ---"
STRATEGY=$(detect_idp_strategy)
info "Detected strategy: $STRATEGY"

echo
echo "--- 2. Test identity (${DEMO2_USER} / ${DEMO2_GROUP}) ---"
if oc get group "$DEMO2_GROUP" &>/dev/null; then
  ok "Group '${DEMO2_GROUP}' exists."
else
  warn "Group '${DEMO2_GROUP}' does not exist yet. Run: make demo2-create-identity"
fi
case "$STRATEGY" in
  htpasswd)
    IDP_NAME=$(htpasswd_idp_name)
    SECRET_NAME=$(htpasswd_secret_name "$IDP_NAME")
    if oc get secret "$SECRET_NAME" -n openshift-config -o jsonpath='{.data.htpasswd}' 2>/dev/null \
        | base64 -d 2>/dev/null | grep -q "^${DEMO2_USER}:"; then
      ok "User '${DEMO2_USER}' exists in htpasswd secret '${SECRET_NAME}'."
    else
      warn "User '${DEMO2_USER}' not found in htpasswd secret yet. Run: make demo2-create-identity"
    fi
    ;;
  keycloak-incluster)
    if kc_user_exists; then
      ok "User '${DEMO2_USER}' exists in Keycloak realm '${DEMO2_KC_REALM}'."
    else
      warn "User '${DEMO2_USER}' not found in Keycloak yet. Run: make demo2-create-identity"
    fi
    ;;
  *)
    warn "Strategy '$STRATEGY' — see docs/demo2/09-auth-oidc-entra.md for the manual procedure."
    ;;
esac

echo
echo "--- 3. MaaS governance objects (models-as-a-service namespace) ---"
oc get maassubscription,maasauthpolicy -n models-as-a-service 2>&1 \
  | grep -E "$DEMO2_SUBSCRIPTION|$DEMO2_AUTHPOLICY|NAME" || warn "No Demo 2 governance objects found yet. Run: make demo2-grant-access"

echo
echo "--- 4. Model readiness (${DEMO2_MODEL_NAMESPACE}/${DEMO2_MODEL_NAME}) ---"
PHASE=$(oc get maasmodelref "$DEMO2_MODEL_NAME" -n "$DEMO2_MODEL_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$PHASE" == "Ready" ]]; then
  ok "MaaSModelRef phase: Ready"
elif [[ "$PHASE" == "NotFound" ]]; then
  err "MaaSModelRef '${DEMO2_MODEL_NAME}' not found in '${DEMO2_MODEL_NAMESPACE}'. Is Demo 1's model deployed/published?"
else
  warn "MaaSModelRef phase: $PHASE (not Ready yet)"
fi

echo
echo "--- 5. Local secrets present (names only, never values) ---"
for f in "$DEMO2_USER_PASSWORD_FILE" "$DEMO2_USER_APIKEY_FILE" "$SECRETS_DIR/${DEMO2_USER}.ratelimit.apikey"; do
  if [[ -f "$f" ]]; then
    ok "$(basename "$f") present."
  else
    warn "$(basename "$f") missing."
  fi
done

echo
echo "=============================================="
echo "Audit complete."
echo "=============================================="
