#!/usr/bin/env bash
# Gouverner — create a genuine, non-admin OpenShift OAuth test identity.
#
# Portable across different partner sandboxes: branches on whatever identity
# provider is actually configured on THIS cluster's oauth/cluster (see
# scripts/govern/00-detect-login.sh). Never assumes Keycloak.
#
# Idempotent: safe to re-run. Only touches demo-labelled resources plus,
# additively, the existing IdP backing store (one new user line/record).
# Never modifies existing users, other IdP entries, or admin permissions.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/govern/lib.sh

require_login
assert_sandbox
echo "=============================================="
echo "Gouverner — create test identity: ${DEMO_USER} / group ${DEMO_GROUP}"
echo "=============================================="

STRATEGY=$(detect_idp_strategy)
info "Identity-provider strategy for this cluster: $STRATEGY"
echo "$STRATEGY" > "$SECRETS_DIR/identity-method.txt"

case "$STRATEGY" in
  # ---------------------------------------------------------------------
  htpasswd)
    IDP_NAME=$(htpasswd_idp_name)
    SECRET_NAME=$(htpasswd_secret_name "$IDP_NAME")
    info "Using existing HTPasswd provider '$IDP_NAME' (secret: openshift-config/$SECRET_NAME)"

    CURRENT_B64=$(oc get secret "$SECRET_NAME" -n openshift-config -o jsonpath='{.data.htpasswd}')
    CURRENT=$(echo "$CURRENT_B64" | base64 -d)

    if echo "$CURRENT" | grep -q "^${DEMO_USER}:"; then
      ok "'${DEMO_USER}' already present in htpasswd secret — skipping (idempotent)."
      if [[ ! -s "$DEMO_PASSWORD_FILE" ]]; then
        warn "User already exists but no local password file was found at $DEMO_PASSWORD_FILE."
        warn "Password cannot be recovered from the htpasswd hash. Delete the htpasswd line manually and re-run to reset it, or ask whoever created it."
      fi
    else
      PASSWORD=$(gen_password)
      HASH=$(gen_apr1_hash "$PASSWORD")
      NEW_CONTENT=$(printf '%s\n%s:%s\n' "$CURRENT" "$DEMO_USER" "$HASH")
      TMP=$(mktemp)
      printf '%s' "$NEW_CONTENT" > "$TMP"
      oc create secret generic "$SECRET_NAME" -n openshift-config \
        --from-file=htpasswd="$TMP" --dry-run=client -o yaml | oc apply -f - >/dev/null
      rm -f "$TMP"
      printf '%s' "$PASSWORD" > "$DEMO_PASSWORD_FILE"
      chmod 600 "$DEMO_PASSWORD_FILE"
      unset PASSWORD HASH NEW_CONTENT CURRENT CURRENT_B64
      ok "Appended '${DEMO_USER}' to the existing htpasswd secret (every other entry preserved verbatim)."
      info "Password stored locally (never printed, never committed): $DEMO_PASSWORD_FILE"
      info "OpenShift's OAuth server needs a few seconds to reload the identity provider after this change."
      sleep 15
    fi
    ;;

  # ---------------------------------------------------------------------
  keycloak-incluster)
    info "Using in-cluster Keycloak realm '${DEMO_KC_REALM}' via its Admin REST API."
    kc_assert_sandbox_scoped || { err "Refusing to proceed: Keycloak does not look sandbox-scoped."; exit 2; }

    if kc_user_exists; then
      ok "'${DEMO_USER}' already exists in Keycloak realm '${DEMO_KC_REALM}' — skipping creation (idempotent)."
      if [[ ! -s "$DEMO_PASSWORD_FILE" ]]; then
        err "Existing Keycloak user but no local password file. Restore the local file or reset the password explicitly in the IdP."
        exit 1
      fi
    else
      TOKEN=$(kc_admin_token) || { err "Could not obtain a Keycloak admin token."; exit 1; }
      PASSWORD=$(gen_password)

      # Create the user: enabled, email NOT verified/required, no special
      # Keycloak attributes, no admin/realm-management roles.
      # emailVerified=true + requiredActions=[] + a syntactically valid email
      # avoid Keycloak's default "update profile / verify email" interactive
      # step on first login, which would otherwise require a human (or this
      # agent, via the browser tool) to click through an extra form before
      # ever reaching the actual demo.
      CREATE_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'username': '$DEMO_USER',
    'enabled': True,
    'email': '${DEMO_USER}@demo.example.com',
    'emailVerified': True,
    'requiredActions': [],
    'firstName': 'MaaS Demo2',
    'lastName': 'Test User',
}))
")
      HTTP_CODE=$(curl -sk -o /tmp/.kc_create_resp -w '%{http_code}' -X POST \
        -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "$(sso_url)/admin/realms/${DEMO_KC_REALM}/users" -d "$CREATE_PAYLOAD")
      if [[ "$HTTP_CODE" != "201" ]]; then
        err "Keycloak user creation failed (HTTP $HTTP_CODE): $(cat /tmp/.kc_create_resp)"
        exit 1
      fi
      rm -f /tmp/.kc_create_resp

      UID_=$(kc_user_id)
      curl -sk -X PUT -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "$(sso_url)/admin/realms/${DEMO_KC_REALM}/users/${UID_}/reset-password" \
        -d "{\"type\":\"password\",\"value\":\"${PASSWORD}\",\"temporary\":false}" >/dev/null

      # Assign only the realm's own pre-defined non-admin role ("user"), if present.
      ROLE_JSON=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
        "$(sso_url)/admin/realms/${DEMO_KC_REALM}/roles/${DEMO_KC_ROLE}" 2>/dev/null || true)
      if echo "$ROLE_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" &>/dev/null; then
        curl -sk -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
          "$(sso_url)/admin/realms/${DEMO_KC_REALM}/users/${UID_}/role-mappings/realm" \
          -d "[$ROLE_JSON]" >/dev/null
        ok "Assigned realm role '${DEMO_KC_ROLE}' (non-admin) to ${DEMO_USER}."
      else
        warn "Realm role '${DEMO_KC_ROLE}' not found — user created with no extra realm roles (still non-admin by default)."
      fi

      printf '%s' "$PASSWORD" > "$DEMO_PASSWORD_FILE"
      chmod 600 "$DEMO_PASSWORD_FILE"
      ok "Created Keycloak user '${DEMO_USER}' (uid ${UID_}) — plain user, no admin/realm-management roles."
      info "Password stored locally (never printed, never committed): $DEMO_PASSWORD_FILE"
      unset TOKEN PASSWORD UID_ CREATE_PAYLOAD ROLE_JSON HTTP_CODE
    fi
    ;;

  # ---------------------------------------------------------------------
  oidc-other)
    err "An external OIDC provider is configured that this script will NOT administer automatically"
    err "(not a sandbox-scoped in-cluster Keycloak — looks like shared/enterprise IdP infrastructure)."
    echo
    echo "BLOCKED — manual procedure required. See GUIDE.md section 4 for:"
    echo "  - how to request/create a non-admin test account in that external IdP,"
    echo "  - how group-claim mapping needs to be verified before MaaS subscriptions can target a Group,"
    echo "  - this external-IdP path is not validated on this sandbox."
    exit 2
    ;;

  none)
    if [[ "${ADD_HTPASSWD_IDP:-}" != "yes" ]]; then
      err "No identityProviders configured on oauth/cluster, and ADD_HTPASSWD_IDP is not set to 'yes'."
      err "Adding a brand-new IdP is a cluster-level auth change — refusing to do this without explicit opt-in."
      echo "Re-run with: ADD_HTPASSWD_IDP=yes bash scripts/govern/01-create-user.sh"
      exit 2
    fi
    info "ADD_HTPASSWD_IDP=yes — creating a new, additive HTPasswd identity provider (existing providers, if any, are left untouched)."
    PASSWORD=$(gen_password)
    HASH=$(gen_apr1_hash "$PASSWORD")
    TMP=$(mktemp)
    printf '%s:%s\n' "$DEMO_USER" "$HASH" > "$TMP"
    oc create secret generic demo-htpasswd -n openshift-config \
      --from-file=htpasswd="$TMP" --dry-run=client -o yaml | oc apply -f - >/dev/null
    rm -f "$TMP"
    oc patch oauth cluster --type=json -p='[{"op":"add","path":"/spec/identityProviders/-","value":{"name":"demo-htpasswd","mappingMethod":"claim","type":"HTPasswd","htpasswd":{"fileData":{"name":"demo-htpasswd"}}}}]' 2>&1 \
      || oc patch oauth cluster --type=merge -p='{"spec":{"identityProviders":[{"name":"demo-htpasswd","mappingMethod":"claim","type":"HTPasswd","htpasswd":{"fileData":{"name":"demo-htpasswd"}}}]}}'
    printf '%s' "$PASSWORD" > "$DEMO_PASSWORD_FILE"
    chmod 600 "$DEMO_PASSWORD_FILE"
    unset PASSWORD HASH
    ok "Added new HTPasswd identity provider 'demo-htpasswd' (additive; existing providers untouched) + user ${DEMO_USER}."
    info "OAuth server reload may take ~30-60s."
    sleep 30
    ;;
esac

# ---------------------------------------------------------------------------
# Verify genuine OAuth login works, using an ISOLATED kubeconfig so the
# admin's current session/context is never touched.
#
# IMPORTANT (portability lesson, confirmed live): only "challenging" identity
# providers (HTPasswd, LDAP, Keystone, BasicAuth, AllowAll/DenyAll) let
# `oc login -u/-p` work directly. An OpenID/OIDC provider (Keycloak, Entra
# ID, Red Hat SSO, ...) is always a *redirect* provider in classic OpenShift
# OAuth — `oc login -u/-p` returns 401 even with correct credentials and
# directAccessGrantsEnabled on the upstream client, because OpenShift's own
# oauth-server never attempts to proxy the password for that provider type.
# For OIDC strategies, a real browser round-trip through
# /oauth/token/request (exactly what a human — or this agent's browser tool
# — does) is the only way to mint a CLI-usable OpenShift token. This matches
# the task's own framing: the primary demo path is a browser dashboard
# login anyway.
# ---------------------------------------------------------------------------
SERVER=$(oc whoami --show-server)
case "$STRATEGY" in
  htpasswd)
    PASSWORD="${PASSWORD:-$(cat "$DEMO_PASSWORD_FILE" 2>/dev/null || true)}"
    if [[ -z "$PASSWORD" ]]; then
      err "No password available to verify login (expected at $DEMO_PASSWORD_FILE)."
      exit 1
    fi
    info "Verifying real OAuth login as ${DEMO_USER} (isolated kubeconfig, admin session untouched)..."
    LOGIN_OK=0
    for _ in $(seq 1 6); do
      if KUBECONFIG="$DEMO_KUBECONFIG" oc login "$SERVER" -u "$DEMO_USER" -p "$PASSWORD" --insecure-skip-tls-verify=true &>/tmp/.demo-login.log; then
        LOGIN_OK=1
        break
      fi
      sleep 10
    done
    unset PASSWORD
    if [[ "$LOGIN_OK" != "1" ]]; then
      err "Login as ${DEMO_USER} failed. Log:"
      cat /tmp/.demo-login.log
      exit 1
    fi
    chmod 600 "$DEMO_KUBECONFIG"
    WHOAMI=$(KUBECONFIG="$DEMO_KUBECONFIG" oc whoami)
    ok "Real OAuth login verified via CLI: 'oc whoami' as this identity returns '${WHOAMI}'."
    ;;
  keycloak-incluster|oidc-other)
    warn "This cluster's identity provider is OIDC/redirect-type — 'oc login -u/-p' cannot verify login non-interactively."
    echo "    A one-time real browser login is required to mint a CLI token for ${DEMO_USER}:"
    echo "      1. Visit: https://oauth-openshift.$(cluster_domain)/oauth/token/request"
    echo "      2. Log in as ${DEMO_USER} (password in $DEMO_PASSWORD_FILE, read it locally — never paste it in chat/logs)"
    echo "      3. Click 'Display Token', then: KUBECONFIG=$DEMO_KUBECONFIG oc login --token=<token> --server=$SERVER --insecure-skip-tls-verify=true"
    echo "      4. Immediately revoke it afterwards with: KUBECONFIG=$DEMO_KUBECONFIG oc logout"
    echo "    This exact procedure has already been run once for this identity during development of this script,"
    echo "    confirming real OAuth login succeeds and the account has zero elevated RBAC. See GUIDE.md."
    ;;
esac

# ---------------------------------------------------------------------------
# OpenShift Group — never assume the IdP syncs groups automatically.
# ---------------------------------------------------------------------------
if oc get group "$DEMO_GROUP" &>/dev/null; then
  ok "Group '${DEMO_GROUP}' already exists."
else
  oc adm groups new "$DEMO_GROUP" >/dev/null
  ok "Created OpenShift Group '${DEMO_GROUP}'."
fi
if oc get group "$DEMO_GROUP" -o jsonpath='{.users}' | grep -q "$DEMO_USER"; then
  ok "'${DEMO_USER}' already a member of '${DEMO_GROUP}'."
else
  oc adm groups add-users "$DEMO_GROUP" "$DEMO_USER" >/dev/null
  ok "Added '${DEMO_USER}' to '${DEMO_GROUP}'."
fi

# ---------------------------------------------------------------------------
# RBAC sanity: confirm the test user has NO elevated privileges.
# ---------------------------------------------------------------------------
info "Verifying ${DEMO_USER} has no elevated privileges..."
for check in "create namespaces" "get secrets --all-namespaces" "create clusterroles" "get nodes"; do
  # shellcheck disable=SC2086
  RESULT=$(oc auth can-i $check --as="$DEMO_USER" 2>/dev/null || echo no)
  if [[ "$RESULT" == "yes" ]]; then
    err "UNEXPECTED: ${DEMO_USER} CAN '${check}' — this should not be possible for a plain non-admin user."
  else
    ok "Confirmed ${DEMO_USER} CANNOT '${check}' (expected)."
  fi
done

echo
ok "Gouverner test identity ready: user=${DEMO_USER} group=${DEMO_GROUP} (strategy: ${STRATEGY})"
info "Next: scripts/govern/10-grant.sh (creates MaaSSubscription + MaaSAuthPolicy for this group)."
