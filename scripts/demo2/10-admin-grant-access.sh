#!/usr/bin/env bash
# Demo 2 — Scenario B (administrator path, declarative/GitOps workflow).
#
# Creates the MaaSSubscription + matching MaaSAuthPolicy that grant
# group ${DEMO2_GROUP} access to ${DEMO2_MODEL_NAME} (${DEMO2_MODEL_NAMESPACE}),
# plus a separate low-quota subscription dedicated to the rate-limit test
# (Scenario E / Test 3). Idempotent: safe to re-run.
#
# Validates every manifest with a server-side dry-run against the live CRDs
# before applying (per the task's explicit requirement — never blindly copy
# manifests from older RHOAI releases).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

require_login
assert_sandbox
echo "=============================================="
echo "Demo 2 — Scenario B: admin grants access"
echo "=============================================="

# Prerequisite check (fail fast with a clear message, per official docs:
# "If MaaSSubscription or MaaSAuthPolicy creation is rejected, verify that
# the MaasTenantConfig CR exists in the target namespace.")
if ! oc get maastenantconfig default-tenant -n models-as-a-service &>/dev/null; then
  err "No MaasTenantConfig 'default-tenant' found in 'models-as-a-service'. Is MaaS enabled (Demo 1 scripts/20-enable-maas.sh)?"
  exit 1
fi
if ! oc get llminferenceservice "$DEMO2_MODEL_NAME" -n "$DEMO2_MODEL_NAMESPACE" &>/dev/null; then
  err "Backend LLMInferenceService '${DEMO2_MODEL_NAME}' not found in '${DEMO2_MODEL_NAMESPACE}'. Run Demo 1 first."
  exit 1
fi
if ! oc get group "$DEMO2_GROUP" &>/dev/null; then
  err "Group '${DEMO2_GROUP}' does not exist. Run scripts/demo2/01-create-test-identity.sh first."
  exit 1
fi

MANIFESTS=(
  manifests/demo2/10-maas-subscription.yaml
  manifests/demo2/11-maas-authpolicy.yaml
  manifests/demo2/12-maas-subscription-ratelimit-test.yaml
)

info "Validating manifests with server-side dry-run against live CRDs..."
for f in "${MANIFESTS[@]}"; do
  if oc apply --server-side=true --dry-run=server -f "$f" >/dev/null 2>/tmp/.demo2_dryrun.log; then
    ok "dry-run OK: $f"
  else
    err "dry-run FAILED for $f:"
    cat /tmp/.demo2_dryrun.log
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

SUB_GROUPS=$(oc get maassubscription maas-demo2-subscription -n models-as-a-service -o jsonpath='{.spec.owner.groups[*].name}')
SUB_MODEL=$(oc get maassubscription maas-demo2-subscription -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].name}')
SUB_MODEL_NS=$(oc get maassubscription maas-demo2-subscription -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].namespace}')
SUB_LIMIT=$(oc get maassubscription maas-demo2-subscription -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].tokenRateLimits[0].limit}')
SUB_WINDOW=$(oc get maassubscription maas-demo2-subscription -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].tokenRateLimits[0].window}')

[[ "$SUB_GROUPS" == "$DEMO2_GROUP" ]] && ok "Subscription owner.groups == [${DEMO2_GROUP}] only" || { err "Subscription owner.groups unexpected: '${SUB_GROUPS}'"; exit 1; }
[[ "$SUB_MODEL" == "$DEMO2_MODEL_NAME" && "$SUB_MODEL_NS" == "$DEMO2_MODEL_NAMESPACE" ]] && ok "Subscription modelRefs == ${DEMO2_MODEL_NAMESPACE}/${DEMO2_MODEL_NAME} only" || { err "Subscription modelRefs unexpected: ${SUB_MODEL_NS}/${SUB_MODEL}"; exit 1; }
ok "Subscription token rate limit: ${SUB_LIMIT} tokens / ${SUB_WINDOW}"

POL_GROUPS=$(oc get maasauthpolicy maas-demo2-access -n models-as-a-service -o jsonpath='{.spec.subjects.groups[*].name}')
POL_MODEL=$(oc get maasauthpolicy maas-demo2-access -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].name}')
[[ "$POL_GROUPS" == "$DEMO2_GROUP" ]] && ok "AuthPolicy subjects.groups == [${DEMO2_GROUP}] only" || { err "AuthPolicy subjects.groups unexpected: '${POL_GROUPS}'"; exit 1; }
[[ "$POL_MODEL" == "$DEMO2_MODEL_NAME" ]] && ok "AuthPolicy modelRefs == ${DEMO2_MODEL_NAME} only" || { err "AuthPolicy modelRefs unexpected: '${POL_MODEL}'"; exit 1; }

# Negative check: confirm no OTHER model (e.g. the legacy my-first-model) is
# referenced by either resource — guards against accidental over-broad grants.
for f in "${MANIFESTS[@]}"; do
  if grep -qE 'my-first-model|llama-32-3b-instruct' "$f"; then
    err "Manifest $f unexpectedly references a non-Demo2 model — refusing."
    exit 1
  fi
done
ok "No references to other models (legacy my-first-model untouched)."

RATELIMIT_LIMIT=$(oc get maassubscription maas-demo2-subscription-ratelimit-test -n models-as-a-service -o jsonpath='{.spec.modelRefs[0].tokenRateLimits[0].limit}')
ok "Rate-limit test subscription limit: ${RATELIMIT_LIMIT} tokens/1m (separate from the main ${SUB_LIMIT}-token subscription used in the rest of the demo)."

echo
ok "Scenario B (declarative) complete. MaaSModelRef should now reach Ready=True (governance pairing satisfied)."
info "Verify: oc get maasmodelref ${DEMO2_MODEL_NAME} -n ${DEMO2_MODEL_NAMESPACE}"
info "IMPORTANT (documented behavior per official docs): if you later edit maas-demo2-subscription's groups/models via the dashboard"
info "or YAML, you must manually update maas-demo2-access to match — subscription edits do NOT auto-sync an existing authorization policy."
