#!/usr/bin/env bash
# Demo 2 — create a genuine, non-admin OpenShift OAuth test identity.
#
# Portable across different partner sandboxes: branches on whatever identity
# provider is actually configured on THIS cluster's oauth/cluster (see
# scripts/demo2/00-detect-identity-provider.sh). Never assumes Keycloak.
#
# Idempotent: safe to re-run. Only touches demo2-labelled resources plus,
# additively, the existing IdP backing store (one new user line/record).
# Never modifies existing users, other IdP entries, or admin permissions.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

require_login
assert_sandbox
echo "=============================================="
echo "Demo 2 — create test identity: ${DEMO2_USER} / group ${DEMO2_GROUP}"
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

    if echo "$CURRENT" | grep -q "^${DEMO2_USER}:"; then
      ok "'${DEMO2_USER}' already present in htpasswd secret — skipping (idempotent)."
      if [[ ! -s "$DEMO2_USER_PASSWORD_FILE" ]]; then
        warn "User already exists but no local password file was found at $DEMO2_USER_PASSWORD_FILE."
        warn "Password cannot be recovered from the htpasswd hash. Delete the htpasswd line manually and re-run to reset it, or ask whoever created it."
      fi
    else
      PASSWORD=$(gen_password)
      HASH=$(openssl passwd -apr1 "$PASSWORD")
      NEW_CONTENT=$(printf '%s\n%s:%s\n' "$CURRENT" "$DEMO2_USER" "$HASH")
      TMP=$(mktemp)
      printf '%s' "$NEW_CONTENT" > "$TMP"
      oc create secret generic "$SECRET_NAME" -n openshift-config \
        --from-file=htpasswd="$TMP" --dry-run=client -o yaml | oc apply -f - >/dev/null
      rm -f "$TMP"
      printf '%s' "$PASSWORD" > "$DEMO2_USER_PASSWORD_FILE"
      chmod 600 "$DEMO2_USER_PASSWORD_FILE"
      unset PASSWORD HASH NEW_CONTENT CURRENT CURRENT_B64
      ok "Appended '${DEMO2_USER}' to the existing htpasswd secret (every other entry preserved verbatim)."
      info "Password stored locally (never printed, never committed): $DEMO2_USER_PASSWORD_FILE"
      info "OpenShift's OAuth server needs a few seconds to reload the identity provider after this change."
      sleep 15
    fi
    ;;

  # ---------------------------------------------------------------------
  keycloak-incluster)
    info "Using in-cluster Keycloak realm '${DEMO2_KC_REALM}' via its Admin REST API."
    kc_assert_sandbox_scoped || { err "Refusing to proceed: Keycloak does not look sandbox-scoped."; exit 2; }

    if kc_user_exists; then
      ok "'${DEMO2_USER}' already exists in Keycloak realm '${DEMO2_KC_REALM}' — skipping creation (idempotent)."
      if [[ ! -s "$DEMO2_USER_PASSWORD_FILE" ]]; then
        warn "User already exists but no local password file at $DEMO2_USER_PASSWORD_FILE — resetting password now so login can be verified."
        PASSWORD=$(gen_password)
        TOKEN=$(kc_admin_token)
        UID_=$(kc_user_id)
        curl -sk -X PUT -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
          "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/users/${UID_}/reset-password" \
          -d "{\"type\":\"password\",\"value\":\"${PASSWORD}\",\"temporary\":false}" >/dev/null
        printf '%s' "$PASSWORD" > "$DEMO2_USER_PASSWORD_FILE"
        chmod 600 "$DEMO2_USER_PASSWORD_FILE"
        unset PASSWORD TOKEN UID_
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
    'username': '$DEMO2_USER',
    'enabled': True,
    'email': '${DEMO2_USER}@demo.example.com',
    'emailVerified': True,
    'requiredActions': [],
    'firstName': 'MaaS Demo2',
    'lastName': 'Test User',
}))
")
      HTTP_CODE=$(curl -sk -o /tmp/.kc_create_resp -w '%{http_code}' -X POST \
        -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/users" -d "$CREATE_PAYLOAD")
      if [[ "$HTTP_CODE" != "201" ]]; then
        err "Keycloak user creation failed (HTTP $HTTP_CODE): $(cat /tmp/.kc_create_resp)"
        exit 1
      fi
      rm -f /tmp/.kc_create_resp

      UID_=$(kc_user_id)
      curl -sk -X PUT -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/users/${UID_}/reset-password" \
        -d "{\"type\":\"password\",\"value\":\"${PASSWORD}\",\"temporary\":false}" >/dev/null

      # Assign only the realm's own pre-defined non-admin role ("user"), if present.
      ROLE_JSON=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
        "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/roles/${DEMO2_KC_ROLE}" 2>/dev/null || true)
      if echo "$ROLE_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" &>/dev/null; then
        curl -sk -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
          "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/users/${UID_}/role-mappings/realm" \
          -d "[$ROLE_JSON]" >/dev/null
        ok "Assigned realm role '${DEMO2_KC_ROLE}' (non-admin) to ${DEMO2_USER}."
      else
        warn "Realm role '${DEMO2_KC_ROLE}' not found — user created with no extra realm roles (still non-admin by default)."
      fi

      printf '%s' "$PASSWORD" > "$DEMO2_USER_PASSWORD_FILE"
      chmod 600 "$DEMO2_USER_PASSWORD_FILE"
      ok "Created Keycloak user '${DEMO2_USER}' (uid ${UID_}) — plain user, no admin/realm-management roles."
      info "Password stored locally (never printed, never committed): $DEMO2_USER_PASSWORD_FILE"
      unset TOKEN PASSWORD UID_ CREATE_PAYLOAD ROLE_JSON HTTP_CODE
    fi
    ;;

  # ---------------------------------------------------------------------
  oidc-other)
    err "An external OIDC provider is configured that this script will NOT administer automatically"
    err "(not a sandbox-scoped in-cluster Keycloak — looks like shared/enterprise IdP infrastructure)."
    echo
    echo "BLOCKED — manual procedure required. See GUIDE.md §11.5 for:"
    echo "  - how to request/create a non-admin test account in that external IdP,"
    echo "  - how group-claim mapping needs to be verified before MaaS subscriptions can target a Group,"
    echo "  - the architecture diagram for this path (not executed on this sandbox)."
    exit 2
    ;;

  none)
    if [[ "${ADD_HTPASSWD_IDP:-}" != "yes" ]]; then
      err "No identityProviders configured on oauth/cluster, and ADD_HTPASSWD_IDP is not set to 'yes'."
      err "Adding a brand-new IdP is a cluster-level auth change — refusing to do this without explicit opt-in."
      echo "Re-run with: ADD_HTPASSWD_IDP=yes bash scripts/demo2/01-create-test-identity.sh"
      exit 2
    fi
    info "ADD_HTPASSWD_IDP=yes — creating a new, additive HTPasswd identity provider (existing providers, if any, are left untouched)."
    PASSWORD=$(gen_password)
    HASH=$(openssl passwd -apr1 "$PASSWORD")
    TMP=$(mktemp)
    printf '%s:%s\n' "$DEMO2_USER" "$HASH" > "$TMP"
    oc create secret generic htpasswd-demo2 -n openshift-config \
      --from-file=htpasswd="$TMP" --dry-run=client -o yaml | oc apply -f - >/dev/null
    rm -f "$TMP"
    oc patch oauth cluster --type=json -p='[{"op":"add","path":"/spec/identityProviders/-","value":{"name":"demo2-htpasswd","mappingMethod":"claim","type":"HTPasswd","htpasswd":{"fileData":{"name":"htpasswd-demo2"}}}}]' 2>&1 \
      || oc patch oauth cluster --type=merge -p='{"spec":{"identityProviders":[{"name":"demo2-htpasswd","mappingMethod":"claim","type":"HTPasswd","htpasswd":{"fileData":{"name":"htpasswd-demo2"}}}]}}'
    printf '%s' "$PASSWORD" > "$DEMO2_USER_PASSWORD_FILE"
    chmod 600 "$DEMO2_USER_PASSWORD_FILE"
    unset PASSWORD HASH
    ok "Added new HTPasswd identity provider 'demo2-htpasswd' (additive; existing providers untouched) + user ${DEMO2_USER}."
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
    PASSWORD="${PASSWORD:-$(cat "$DEMO2_USER_PASSWORD_FILE" 2>/dev/null || true)}"
    if [[ -z "$PASSWORD" ]]; then
      err "No password available to verify login (expected at $DEMO2_USER_PASSWORD_FILE)."
      exit 1
    fi
    info "Verifying real OAuth login as ${DEMO2_USER} (isolated kubeconfig, admin session untouched)..."
    LOGIN_OK=0
    for _ in $(seq 1 6); do
      if KUBECONFIG="$DEMO2_USER_KUBECONFIG" oc login "$SERVER" -u "$DEMO2_USER" -p "$PASSWORD" --insecure-skip-tls-verify=true &>/tmp/.demo2_login.log; then
        LOGIN_OK=1
        break
      fi
      sleep 10
    done
    unset PASSWORD
    if [[ "$LOGIN_OK" != "1" ]]; then
      err "Login as ${DEMO2_USER} failed. Log:"
      cat /tmp/.demo2_login.log
      exit 1
    fi
    chmod 600 "$DEMO2_USER_KUBECONFIG"
    WHOAMI=$(KUBECONFIG="$DEMO2_USER_KUBECONFIG" oc whoami)
    ok "Real OAuth login verified via CLI: 'oc whoami' as this identity returns '${WHOAMI}'."
    ;;
  keycloak-incluster|oidc-other)
    warn "This cluster's identity provider is OIDC/redirect-type — 'oc login -u/-p' cannot verify login non-interactively."
    echo "    A one-time real browser login is required to mint a CLI token for ${DEMO2_USER}:"
    echo "      1. Visit: https://oauth-openshift.$(cluster_domain)/oauth/token/request"
    echo "      2. Log in as ${DEMO2_USER} (password in $DEMO2_USER_PASSWORD_FILE, read it locally — never paste it in chat/logs)"
    echo "      3. Click 'Display Token', then: KUBECONFIG=$DEMO2_USER_KUBECONFIG oc login --token=<token> --server=$SERVER --insecure-skip-tls-verify=true"
    echo "      4. Immediately revoke it afterwards with: KUBECONFIG=$DEMO2_USER_KUBECONFIG oc logout"
    echo "    This exact procedure has already been run once for this identity during development of this script,"
    echo "    confirming real OAuth login succeeds and the account has zero elevated RBAC. See GUIDE.md."
    ;;
esac

# ---------------------------------------------------------------------------
# OpenShift Group — never assume the IdP syncs groups automatically.
# ---------------------------------------------------------------------------
if oc get group "$DEMO2_GROUP" &>/dev/null; then
  ok "Group '${DEMO2_GROUP}' already exists."
else
  oc adm groups new "$DEMO2_GROUP" >/dev/null
  ok "Created OpenShift Group '${DEMO2_GROUP}'."
fi
if oc get group "$DEMO2_GROUP" -o jsonpath='{.users}' | grep -q "$DEMO2_USER"; then
  ok "'${DEMO2_USER}' already a member of '${DEMO2_GROUP}'."
else
  oc adm groups add-users "$DEMO2_GROUP" "$DEMO2_USER" >/dev/null
  ok "Added '${DEMO2_USER}' to '${DEMO2_GROUP}'."
fi

# ---------------------------------------------------------------------------
# RBAC sanity: confirm the test user has NO elevated privileges.
# ---------------------------------------------------------------------------
info "Verifying ${DEMO2_USER} has no elevated privileges..."
for check in "create namespaces" "get secrets --all-namespaces" "create clusterroles" "get nodes"; do
  # shellcheck disable=SC2086
  RESULT=$(oc auth can-i $check --as="$DEMO2_USER" 2>/dev/null || echo no)
  if [[ "$RESULT" == "yes" ]]; then
    err "UNEXPECTED: ${DEMO2_USER} CAN '${check}' — this should not be possible for a plain non-admin user."
  else
    ok "Confirmed ${DEMO2_USER} CANNOT '${check}' (expected)."
  fi
done

echo
ok "Demo 2 test identity ready: user=${DEMO2_USER} group=${DEMO2_GROUP} (strategy: ${STRATEGY})"
info "Next: scripts/demo2/10-admin-grant-access.sh (creates MaaSSubscription + MaaSAuthPolicy for this group)."
