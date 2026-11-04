#!/usr/bin/env bash
# Gouverner — consolidated, read-only audit. Safe to run on any sandbox,
# at any time, before/after any other govern script. Never mutates
# anything, never prints a secret value.
# NOTE: -e is deliberately omitted. Audit probes resources that may not exist
# yet (group, identity, governance CRs, secret files) and reports their
# presence/absence — every `oc get` failure is an expected, informational
# branch, not an error.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/govern/lib.sh

require_login
echo "=============================================="
echo "Gouverner — Consolidated audit (read-only)"
echo "=============================================="

echo
echo "--- 1. Identity provider strategy ---"
STRATEGY=$(detect_idp_strategy)
info "Detected strategy: $STRATEGY"

echo
echo "--- 2. Test identity (${DEMO_USER} / ${DEMO_GROUP}) ---"
if oc get group "$DEMO_GROUP" &>/dev/null; then
  ok "Group '${DEMO_GROUP}' exists."
else
  warn "Group '${DEMO_GROUP}' does not exist yet. Run: make govern-user"
fi
case "$STRATEGY" in
  htpasswd)
    IDP_NAME=$(htpasswd_idp_name)
    SECRET_NAME=$(htpasswd_secret_name "$IDP_NAME")
    if oc get secret "$SECRET_NAME" -n openshift-config -o jsonpath='{.data.htpasswd}' 2>/dev/null \
        | base64 -d 2>/dev/null | grep -q "^${DEMO_USER}:"; then
      ok "User '${DEMO_USER}' exists in htpasswd secret '${SECRET_NAME}'."
    else
      warn "User '${DEMO_USER}' not found in htpasswd secret yet. Run: make govern-user"
    fi
    ;;
  keycloak-incluster)
    if kc_user_exists; then
      ok "User '${DEMO_USER}' exists in Keycloak realm '${DEMO_KC_REALM}'."
    else
      warn "User '${DEMO_USER}' not found in Keycloak yet. Run: make govern-user"
    fi
    ;;
  *)
    warn "Strategy '$STRATEGY' — see GUIDE.md §11.5 for the manual procedure."
    ;;
esac

echo
echo "--- 3. MaaS governance objects (models-as-a-service namespace) ---"
oc get maassubscription,maasauthpolicy -n models-as-a-service 2>&1 \
  | grep -E "$DEMO_QUOTA|$DEMO_ACCESS|NAME" || warn "No Gouverner governance objects found yet. Run: make govern"

echo
echo "--- 4. Model readiness (${DEMO_PROJECT}/${DEMO_MODEL}) ---"
PHASE=$(oc get maasmodelref "$DEMO_MODEL" -n "$DEMO_PROJECT" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$PHASE" == "Ready" ]]; then
  ok "MaaSModelRef phase: Ready"
elif [[ "$PHASE" == "NotFound" ]]; then
  err "MaaSModelRef '${DEMO_MODEL}' not found in '${DEMO_PROJECT}'. Is Publier's model deployed/published?"
else
  warn "MaaSModelRef phase: $PHASE (not Ready yet)"
fi

echo
echo "--- 5. Local secrets present (names only, never values) ---"
for f in "$DEMO_PASSWORD_FILE" "$DEMO_APIKEY_FILE" "$SECRETS_DIR/${DEMO_USER}.ratelimit.apikey"; do
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
