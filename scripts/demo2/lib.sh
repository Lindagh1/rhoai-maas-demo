#!/usr/bin/env bash
# Shared helpers for Demo 2 scripts. Extends scripts/lib.sh (Demo 1).
set -uo pipefail

DEMO2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$DEMO2_ROOT/scripts/lib.sh"

SECRETS_DIR="$DEMO2_ROOT/secrets/demo2"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR" 2>/dev/null || true

# --- Parameterized identifiers (override via env, never hardcode in callers) ---
DEMO2_GROUP="${DEMO2_GROUP:-maas-demo2-developers}"
DEMO2_USER="${DEMO2_USER:-maas-demo2-user}"
DEMO2_SUBSCRIPTION="${DEMO2_SUBSCRIPTION:-maas-demo2-subscription}"
DEMO2_AUTHPOLICY="${DEMO2_AUTHPOLICY:-maas-demo2-access}"
DEMO2_MODEL_NAME="${DEMO2_MODEL_NAME:-demo-simulator}"
DEMO2_MODEL_NAMESPACE="${DEMO2_MODEL_NAMESPACE:-rhoai-maas-demo}"
DEMO2_KC_REALM="${DEMO2_KC_REALM:-sso}"
DEMO2_KC_ROLE="${DEMO2_KC_ROLE:-user}"
DEMO2_USER_KUBECONFIG="$SECRETS_DIR/${DEMO2_USER}.kubeconfig"
DEMO2_USER_PASSWORD_FILE="$SECRETS_DIR/${DEMO2_USER}.password"
DEMO2_USER_APIKEY_FILE="$SECRETS_DIR/${DEMO2_USER}.apikey"

sso_url() {
  echo "https://sso.$(cluster_domain)"
}

# Fetch a short-lived Keycloak *master-realm* admin token using the
# cluster-generated `keycloak-initial-admin` Secret. Never echoes the token
# or the underlying credentials. Caller captures stdout into a variable.
kc_admin_token() {
  local user pass resp
  user=$(oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
  pass=$(oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
  if [[ -z "$user" || -z "$pass" ]]; then
    err "Could not read keycloak-initial-admin secret (keycloak namespace). Is Keycloak installed on this sandbox?"
    return 1
  fi
  resp=$(curl -sk -X POST "$(sso_url)/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${user}" \
    -d "password=${pass}" \
    -d "grant_type=password")
  unset user pass
  python3 -c "
import json,sys
d = json.loads(sys.argv[1])
tok = d.get('access_token')
if not tok:
    sys.exit(1)
print(tok)
" "$resp" 2>/dev/null
}

# Safety check (required before any Keycloak mutation): refuse to proceed if
# the 'sso' realm serves more than the single in-cluster OpenShift OAuth
# client. This Keycloak is expected to be dedicated, disposable sandbox
# infrastructure — not a shared enterprise IdP.
kc_assert_sandbox_scoped() {
  local token clients_json client_count custom_clients
  token=$(kc_admin_token) || { err "Cannot verify Keycloac scope: no admin token"; return 1; }
  clients_json=$(curl -sk -H "Authorization: Bearer ${token}" \
    "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/clients")
  # Every Keycloak realm auto-provisions these 6 built-in clients
  # (account, account-console, admin-cli, broker, realm-management,
  # security-admin-console) regardless of who created the realm. Only
  # custom/additional clients indicate the realm serves more than this
  # cluster's own OAuth integration.
  custom_clients=$(python3 -c "
import json,sys
builtin = {'account','account-console','admin-cli','broker','realm-management','security-admin-console'}
d = json.loads(sys.argv[1])
custom = [c.get('clientId') for c in d if c.get('clientId') not in builtin]
print(','.join(custom))
" "$clients_json" 2>/dev/null || echo "?")
  client_count=$(python3 -c "print(len('$custom_clients'.split(',')) if '$custom_clients' else 0)")
  if [[ "$client_count" != "1" ]]; then
    err "Realm '${DEMO2_KC_REALM}' has ${client_count} non-default clients (${custom_clients}) — expected exactly 1: this cluster's own OpenShift OAuth client. Refusing to mutate — this Keycloak may be shared beyond this sandbox."
    return 1
  fi
  local ns_age
  ns_age=$(oc get ns keycloak -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)
  ok "Keycloak scope check passed: realm '${DEMO2_KC_REALM}' has exactly 1 client (this cluster's own OAuth IdP); keycloak namespace created ${ns_age} (same disposable sandbox as everything else)."
  unset token clients_json
  return 0
}

kc_user_exists() {
  local token count
  token=$(kc_admin_token) || return 1
  count=$(curl -sk -H "Authorization: Bearer ${token}" \
    "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/users?username=${DEMO2_USER}&exact=true" \
    | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  unset token
  [[ "${count:-0}" -gt 0 ]]
}

kc_user_id() {
  local token
  token=$(kc_admin_token) || return 1
  curl -sk -H "Authorization: Bearer ${token}" \
    "$(sso_url)/admin/realms/${DEMO2_KC_REALM}/users?username=${DEMO2_USER}&exact=true" \
    | python3 -c "
import json,sys
d = json.load(sys.stdin)
print(d[0]['id'] if d else '')
"
}

gen_password() {
  python3 -c "import secrets,string; a=string.ascii_letters+string.digits+'!@#%^&*'; print(''.join(secrets.choice(a) for _ in range(28)))"
}

# ---------------------------------------------------------------------------
# Identity-provider detection (portable across different partner sandboxes).
# A different Red Hat OpenShift AI sandbox will very likely NOT have the
# in-cluster Keycloak this sandbox happens to have. These scripts must
# inspect whatever `oauth/cluster` actually has configured and branch,
# instead of assuming any one IdP technology.
# ---------------------------------------------------------------------------

# Prints one of: htpasswd | keycloak-incluster | oidc-other | none
detect_idp_strategy() {
  local idp_json idp_count htpasswd_name
  idp_json=$(oc get oauth cluster -o json 2>/dev/null | python3 -c "
import json,sys
d = json.load(sys.stdin)
print(json.dumps(d.get('spec',{}).get('identityProviders',[])))
" 2>/dev/null || echo '[]')
  idp_count=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$idp_json" 2>/dev/null || echo 0)

  if [[ "$idp_count" == "0" ]]; then
    echo "none"
    return 0
  fi

  htpasswd_name=$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
for p in d:
    if p.get('type') == 'HTPasswd':
        print(p['name']); break
" "$idp_json" 2>/dev/null || true)
  if [[ -n "$htpasswd_name" ]]; then
    echo "htpasswd"
    return 0
  fi

  local oidc_issuer
  oidc_issuer=$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
for p in d:
    if p.get('type') == 'OpenID':
        print(p.get('openID',{}).get('issuer','')); break
" "$idp_json" 2>/dev/null || true)
  if [[ -n "$oidc_issuer" ]]; then
    # In-cluster Keycloak heuristic: issuer host resolves to a Route served
    # by this same cluster's ingress, AND the Keycloak Operator CRD + a
    # Keycloak CR actually exist here. A partner sandbox using an *external*
    # enterprise OIDC/Entra ID provider will fail at least one of these.
    local domain
    domain=$(cluster_domain)
    if [[ "$oidc_issuer" == *".${domain}"* ]] && oc get keycloaks.k8s.keycloak.org -A &>/dev/null; then
      echo "keycloak-incluster"
      return 0
    fi
    echo "oidc-other"
    return 0
  fi

  echo "oidc-other"
}

htpasswd_idp_name() {
  oc get oauth cluster -o json 2>/dev/null | python3 -c "
import json,sys
d = json.load(sys.stdin)
for p in d.get('spec',{}).get('identityProviders',[]):
    if p.get('type') == 'HTPasswd':
        print(p['name']); break
"
}

htpasswd_secret_name() {
  local idp="$1"
  oc get oauth cluster -o json 2>/dev/null | python3 -c "
import json,sys
d = json.load(sys.stdin)
for p in d.get('spec',{}).get('identityProviders',[]):
    if p.get('name') == sys.argv[1]:
        print(p.get('htpasswd',{}).get('fileData',{}).get('name','')); break
" "$idp"
}
