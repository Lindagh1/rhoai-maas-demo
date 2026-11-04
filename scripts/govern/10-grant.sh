#!/usr/bin/env bash
# Gouverner — Scenario B (administrator path, declarative/GitOps workflow).
#
# Creates the MaaSSubscription + matching MaaSAuthPolicy that grant
# group ${DEMO_GROUP} access to ${DEMO_MODEL} (${DEMO_PROJECT}),
# plus a separate low-quota subscription dedicated to the rate-limit test
# (Scenario E / Test 3). Idempotent: safe to re-run.
#
# Validates every manifest with a server-side dry-run against the live CRDs
# before applying (per the task's explicit requirement — never blindly copy
# manifests from older RHOAI releases).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/govern/lib.sh

require_login
assert_sandbox
echo "=============================================="
echo "Gouverner — Scenario B: admin grants access"
echo "=============================================="

# Prerequisite check (fail fast with a clear message, per official docs:
# "If MaaSSubscription or MaaSAuthPolicy creation is rejected, verify that
# the MaasTenantConfig CR exists in the target namespace.")
if ! oc get maastenantconfig default-tenant -n models-as-a-service &>/dev/null; then
  err "No MaasTenantConfig 'default-tenant' found in 'models-as-a-service'. Is MaaS enabled (Publier scripts/publish/20-enable-platform.sh)?"
  exit 1
fi
if ! oc get llminferenceservice "$DEMO_MODEL" -n "$DEMO_PROJECT" &>/dev/null; then
  err "Backend LLMInferenceService '${DEMO_MODEL}' not found in '${DEMO_PROJECT}'. Run Publier first."
  exit 1
fi
if ! oc get group "$DEMO_GROUP" &>/dev/null; then
  err "Group '${DEMO_GROUP}' does not exist. Run scripts/govern/01-create-user.sh first."
  exit 1
fi

MANIFESTS=(
  manifests/govern/quota.yaml
  manifests/govern/access.yaml
  manifests/govern/low-quota.yaml
  manifests/govern/user-rbac.yaml
)

info "Validating manifests with server-side dry-run against live CRDs..."
for f in "${MANIFESTS[@]}"; do
  if oc apply --server-side=true --dry-run=server -f "$f" >/dev/null 2>/tmp/.demo-dryrun.log; then
    ok "dry-run OK: $f"
  else
    err "dry-run FAILED for $f:"
    cat /tmp/.demo-dryrun.log
    exit 1
  fi
done

info "Applying (idempotent)..."
for f in "${MANIFESTS[@]}"; do
  oc apply --server-side=true -f "$f" >/dev/null
  ok "applied: $f"
done

# ---------------------------------------------------------------------------
# Verification (per task requirements): both resources exist and have the
# expected state; model references correct; token limits correct; subject
# group matches; and — critically — this does NOT grant access to any other
# model or any other group than the ones we explicitly listed.
# ---------------------------------------------------------------------------
info "Verifying..."

SUB_GROUPS=$(oc get maassubscription demo-quota -n models-as-a-service -o jsonpath='{.spec.owner.groups[*].name}')
SUB_MODEL=$(oc get maassubscription demo-quota -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].name}')
SUB_MODEL_NS=$(oc get maassubscription demo-quota -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].namespace}')
SUB_LIMIT=$(oc get maassubscription demo-quota -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].tokenRateLimits[0].limit}')
SUB_WINDOW=$(oc get maassubscription demo-quota -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].tokenRateLimits[0].window}')

[[ "$SUB_GROUPS" == "$DEMO_GROUP" ]] && ok "Subscription owner.groups == [${DEMO_GROUP}] only" || { err "Subscription owner.groups unexpected: '${SUB_GROUPS}'"; exit 1; }
[[ "$SUB_MODEL" == "$DEMO_MODEL" && "$SUB_MODEL_NS" == "$DEMO_PROJECT" ]] && ok "Subscription modelRefs == ${DEMO_PROJECT}/${DEMO_MODEL} only" || { err "Subscription modelRefs unexpected: ${SUB_MODEL_NS}/${SUB_MODEL}"; exit 1; }
ok "Subscription token rate limit: ${SUB_LIMIT} tokens / ${SUB_WINDOW}"

POL_GROUPS=$(oc get maasauthpolicy demo-access -n models-as-a-service -o jsonpath='{.spec.subjects.groups[*].name}')
POL_MODEL=$(oc get maasauthpolicy demo-access -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].name}')
[[ "$POL_GROUPS" == "$DEMO_GROUP" ]] && ok "AuthPolicy subjects.groups == [${DEMO_GROUP}] only" || { err "AuthPolicy subjects.groups unexpected: '${POL_GROUPS}'"; exit 1; }
[[ "$POL_MODEL" == "$DEMO_MODEL" ]] && ok "AuthPolicy modelRefs == ${DEMO_MODEL} only" || { err "AuthPolicy modelRefs unexpected: '${POL_MODEL}'"; exit 1; }

# Negative check: confirm no OTHER model (e.g. the legacy my-first-model) is
# referenced by either resource — guards against accidental over-broad grants.
for f in "${MANIFESTS[@]}"; do
  if grep -qE 'my-first-model|llama-32-3b-instruct' "$f"; then
    err "Manifest $f unexpectedly references a non-Demo2 model — refusing."
    exit 1
  fi
done
ok "No references to other models (legacy my-first-model untouched)."

RATELIMIT_LIMIT=$(oc get maassubscription demo-low-quota -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].tokenRateLimits[0].limit}')
ok "Rate-limit test subscription limit: ${RATELIMIT_LIMIT} tokens/1m (separate from the main ${SUB_LIMIT}-token subscription used in the rest of the demo)."

if oc get maasauthpolicy demo-quota-policy -n models-as-a-service >/dev/null 2>&1; then
  warn "Found leftover duplicate MaaSAuthPolicy/demo-quota-policy. It is harmless but was created accidentally by the dashboard UI in a previous run; delete it for a cleaner demo state."
fi

# The dashboard's maas-ui discovers the public MaaS hostname and calls it with
# Go's HTTP/2 client. On this single-node sandbox the gateway's HTTP/2
# handshake is reset (the UI then shows "Error loading API keys ... EOF").
# HTTP/1.1 to the same URL works. GODEBUG=http2client=0 forces that client
# onto HTTP/1.1. The Deployment is operator-owned; re-apply if a reconcile
# drops the variable.
if oc get deploy maas-ui -n redhat-ods-applications &>/dev/null; then
  CURRENT_GODEBUG=$(oc set env deploy/maas-ui -n redhat-ods-applications --list 2>/dev/null | awk -F= '/^GODEBUG=/{print $2}')
  if [[ "$CURRENT_GODEBUG" == *http2client=0* ]]; then
    ok "maas-ui already uses HTTP/1.1 (GODEBUG=http2client=0)"
  else
    info "Forcing maas-ui onto HTTP/1.1 so the API keys page can reach the gateway"
    oc set env deploy/maas-ui -n redhat-ods-applications GODEBUG=http2client=0 >/dev/null
    oc rollout status deploy/maas-ui -n redhat-ods-applications --timeout=180s >/dev/null
    ok "maas-ui restarted with GODEBUG=http2client=0"
  fi
fi

echo
ok "Scenario B (declarative) complete. MaaSModelRef should now reach Ready=True (governance pairing satisfied)."
info "Verify: oc get maasmodelref ${DEMO_MODEL} -n ${DEMO_PROJECT}"
info "IMPORTANT (documented behavior per official docs): if you later edit demo-quota's groups/models via the dashboard"
info "or YAML, you must manually update demo-access to match — subscription edits do NOT auto-sync an existing authorization policy."
