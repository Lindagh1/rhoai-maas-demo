#!/usr/bin/env bash
# Demo 2 — Scenario E: negative tests.
#
#   Test 1: MaaSSubscription present, MaaSAuthPolicy absent
#           (docs/spec imply 403; real observed behavior may differ — see below)
#   Test 2: MaaSAuthPolicy present, MaaSSubscription absent
#           (docs/spec imply 429; real observed behavior may differ — see below)
#   Test 3: rate-limit exhaustion on the deliberately tiny (50 tokens/1m)
#           maas-demo2-subscription-ratelimit-test subscription -> expect 429
#
#   REAL FINDINGS (this installed MaaS version, confirmed on-cluster):
#   - Test 1 (no AuthPolicy): returns 403 — matches the docs' implication.
#   - Test 2 (key's own subscription deleted, but a DIFFERENT subscription
#     still satisfies the model's governance pairing so it stays Ready):
#     returns 403 with body "requested subscription not found". The key's
#     access check is bound to its specific granting subscription — not
#     the docs-implied 429 (which is reserved for genuine quota exhaustion
#     on an active subscription, see Test 3).
#   - Test 3 (rate-limit exhaustion on a dedicated 50-tokens/1m sub):
#     returns 429 after bounded requests — matches the docs.
#   This script reports whatever status is actually observed; it does not
#   force the documented expectation.
#
# Safety:
#   - Tests 1/2 temporarily remove ONLY the Demo 2 objects they target, and
#     ALWAYS restore both manifests on exit (trap), regardless of success/
#     failure, so the sandbox never ends up in a half-broken state.
#   - Test 3 uses a dedicated, isolated, low-quota subscription (50 tokens/
#     1m) created solely for this purpose; it never touches the main demo
#     subscription or any other sandbox user's resources. Requests are
#     small and bounded (a fixed loop with max_tokens=5), never an
#     uncontrolled load test.
#   - Reads the API key only from local files via `cat`; never embeds a
#     key value as a literal in this script or in any command it runs.
# NOTE: -e is deliberately omitted. This script expects non-zero exits from
# curl (403, 429) and oc delete — they are the test outcomes being captured,
# not errors. Governance restoration runs via `trap` regardless of exit path.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

EVIDENCE_DIR="evidence/demo2"
mkdir -p "$EVIDENCE_DIR"
require_login

MAIN_KEY_FILE="$DEMO2_USER_APIKEY_FILE"
RL_KEY_FILE="secrets/demo2/maas-demo2-user.ratelimit.apikey"
HOST="$(maas_host_url)"

[[ -f "$MAIN_KEY_FILE" ]] || { err "Missing $MAIN_KEY_FILE — run Scenario C first."; exit 1; }
[[ -f "$RL_KEY_FILE" ]]   || { err "Missing $RL_KEY_FILE — create the rate-limit-test key first."; exit 1; }
MAIN_KEY="$(cat "$MAIN_KEY_FILE")"
RL_KEY="$(cat "$RL_KEY_FILE")"

# Resolve gateway IP for clusters where DNS hasn't propagated to this shell
# (same workaround as scripts/demo2/20-test-inference.sh and Demo 1's
# scripts/infer.sh). Without this, curl may hit the default OpenShift
# router (which 404s) instead of the actual MaaS gateway.
GATEWAY_ADDR=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
RESOLVE_OPT=()
if [[ -n "$GATEWAY_ADDR" ]] && echo "$GATEWAY_ADDR" | grep -qE '[a-zA-Z]'; then
  GATEWAY_IP=$(dig +short "$GATEWAY_ADDR" 2>/dev/null | head -1 || true)
  [[ -n "$GATEWAY_IP" ]] && RESOLVE_OPT=(--resolve "$(maas_hostname):443:${GATEWAY_IP}")
fi

wait_for_phase() {
  # wait_for_phase <phase> <timeout_s>
  # Polls until the CR reports the target phase, then adds a short extra
  # buffer for Gateway/Envoy config propagation (observed empirically to
  # lag slightly behind the CR status update).
  local want="$1" timeout="${2:-60}" waited=0 phase
  while (( waited < timeout )); do
    phase=$(oc get maasmodelref demo-simulator -n rhoai-maas-demo -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$phase" == "$want" ]]; then
      sleep 5 # gateway propagation buffer
      return 0
    fi
    sleep 3; waited=$((waited+3))
  done
  warn "Timed out after ${timeout}s waiting for MaaSModelRef phase=$want (last seen: $phase) — continuing anyway"
  return 1
}

MODEL_STATUS_PY="/tmp/demo2-model-status.$$.py"
cat > "$MODEL_STATUS_PY" <<'PYEOF'
import json, sys
d = json.load(sys.stdin)
s = d.get("status", {})
print("phase:", s.get("phase"))
for c in s.get("conditions", []):
    ctype = c.get("type")
    cstatus = c.get("status")
    reason = c.get("reason")
    message = c.get("message")
    print("  " + str(ctype) + ": " + str(cstatus) + " (" + str(reason) + ") - " + str(message))
PYEOF

model_status_snapshot() {
  oc get maasmodelref demo-simulator -n rhoai-maas-demo -o json 2>/dev/null \
    | python3 "$MODEL_STATUS_PY" 2>/dev/null \
    || echo "(could not read MaaSModelRef status)"
}

call_models() {
  local key="$1"
  curl -sSk --connect-timeout 10 --max-time 20 "${RESOLVE_OPT[@]}" \
    -H "Authorization: Bearer ${key}" \
    -w '\n%{http_code}' \
    "${HOST}/v1/models" 2>/dev/null || echo -e "\n000"
}

# The gateway's body-based routing expects the FULL model id as reported
# by GET /v1/models (e.g. "publishers/<ns>/models/facebook/opt-125m"), not
# the short alias — confirmed in Scenario D. Hardcoded here (rather than
# re-discovered per call) since the tests below also need to call this
# endpoint while the model is deliberately made un-discoverable (Pending).
MODEL_ID="publishers/${DEMO2_MODEL_NAMESPACE}/models/facebook/opt-125m"

call_infer() {
  local key="$1" max_tokens="${2:-5}"
  curl -sSk --connect-timeout 10 --max-time 20 "${RESOLVE_OPT[@]}" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -w '\n%{http_code}' \
    -d "{\"model\": \"${MODEL_ID}\", \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}], \"max_tokens\": ${max_tokens}}" \
    "${HOST}/v1/chat/completions" 2>/dev/null || echo -e "\n000"
}

echo "=============================================="
echo "Demo 2 — Scenario E: negative tests"
echo "=============================================="

# --- restore safety net ---
restore_governance() {
  oc apply --server-side=true -f manifests/demo2/10-maas-subscription.yaml >/dev/null 2>&1
  oc apply --server-side=true -f manifests/demo2/11-maas-authpolicy.yaml >/dev/null 2>&1
  oc apply --server-side=true -f manifests/demo2/12-maas-subscription-ratelimit-test.yaml >/dev/null 2>&1
}
cleanup_on_exit() {
  restore_governance
  rm -f "$MODEL_STATUS_PY"
}
trap cleanup_on_exit EXIT

### Test 1: subscription present, authpolicy absent -> expect 403
echo
echo "--- Test 1: remove MaaSAuthPolicy only (subscription stays) -> docs imply 403 ---"
oc delete maasauthpolicy maas-demo2-access -n models-as-a-service --ignore-not-found=true >/dev/null 2>&1
wait_for_phase "Pending" 60
STATUS1=$(model_status_snapshot)
echo "$STATUS1"
RESP1=$(call_infer "$MAIN_KEY")
CODE1=$(echo "$RESP1" | tail -1)
BODY1=$(echo "$RESP1" | sed '$d')
echo "HTTP status: $CODE1"
{
  echo "# Scenario E — Test 1: subscription present, authpolicy absent"
  echo "Date: $(date -u +%FT%TZ)"
  echo "Docs/spec implication: 403 Forbidden (auth layer rejects, gateway route still present)"
  echo
  echo "MaaSModelRef status at time of call:"
  echo "$STATUS1"
  echo
  echo "Observed HTTP status: $CODE1"
  echo "$BODY1" | python3 -m json.tool 2>/dev/null || echo "$BODY1"
} | sed -E 's/sk-oai-[A-Za-z0-9_\-]+/sk-oai-***REDACTED***/g' > "$EVIDENCE_DIR/scenario-e-01-no-authpolicy.txt"
if [[ "$CODE1" == "403" ]]; then
  ok "Test 1: got 403 as the docs imply (no AuthPolicy -> access forbidden)."
else
  warn "Test 1: got $CODE1, not 403. Recording this actual observed behavior, not assuming the documented one."
fi

# restore authpolicy before test 2, wait for full recovery
oc apply --server-side=true -f manifests/demo2/11-maas-authpolicy.yaml >/dev/null 2>&1
wait_for_phase "Ready" 60

### Test 2: authpolicy present, subscription absent -> docs imply 429
echo
echo "--- Test 2: remove MaaSSubscription only (authpolicy stays) -> docs imply 429 ---"
oc delete maassubscription maas-demo2-subscription -n models-as-a-service --ignore-not-found=true >/dev/null 2>&1
wait_for_phase "Pending" 60
STATUS2=$(model_status_snapshot)
echo "$STATUS2"
RESP2=$(call_infer "$MAIN_KEY")
CODE2=$(echo "$RESP2" | tail -1)
BODY2=$(echo "$RESP2" | sed '$d')
echo "HTTP status: $CODE2"
{
  echo "# Scenario E — Test 2: authpolicy present, subscription absent"
  echo "Date: $(date -u +%FT%TZ)"
  echo "Docs/spec implication: 429 Too Many Requests (no quota left)"
  echo
  echo "MaaSModelRef status at time of call:"
  echo "$STATUS2"
  echo
  echo "Observed HTTP status: $CODE2"
  echo "$BODY2" | python3 -m json.tool 2>/dev/null || echo "$BODY2"
} | sed -E 's/sk-oai-[A-Za-z0-9_\-]+/sk-oai-***REDACTED***/g' > "$EVIDENCE_DIR/scenario-e-02-no-subscription.txt"
if [[ "$CODE2" == "429" ]]; then
  ok "Test 2: got 429 as the docs imply."
elif [[ "$CODE2" == "403" ]]; then
  ok "Test 2: got 403 (not the 429 one might expect from docs). REAL FINDING: the API key's access check is bound to its specific granting MaaSSubscription. Deleting that subscription revokes the key's access outright (403 Forbidden), even though the model itself stays Ready via another, unrelated subscription (maas-demo2-subscription-ratelimit-test) still pairing with the same AuthPolicy. 429 is reserved for actual quota exhaustion on an existing subscription (see Test 3), not for 'no subscription at all'. Documenting this as the accurate behavior of this installed MaaS version."
else
  warn "Test 2: got $CODE2. Recording this actual observed behavior."
fi

# restore subscription + authpolicy, wait for full recovery before test 3
restore_governance
wait_for_phase "Ready" 60

### Test 3: rate-limit exhaustion on the isolated low-quota subscription
echo
echo "--- Test 3: exhaust the 50 tokens/1m rate-limit-test subscription -> expect 429 ---"
echo "Sending a small, bounded sequence of requests (max 15 attempts, max_tokens=5 each)..."
GOT_429=0
for i in $(seq 1 15); do
  RESP3=$(call_infer "$RL_KEY" 5)
  CODE3=$(echo "$RESP3" | tail -1)
  echo "  attempt $i: HTTP $CODE3"
  if [[ "$CODE3" == "429" ]]; then
    GOT_429=1
    BODY3=$(echo "$RESP3" | sed '$d')
    {
      echo "# Scenario E — Test 3: rate-limit exhaustion (isolated 50 tokens/1m subscription)"
      echo "Date: $(date -u +%FT%TZ)"
      echo "Attempts until 429: $i"
      echo "Observed HTTP status: $CODE3"
      echo "$BODY3" | python3 -m json.tool 2>/dev/null || echo "$BODY3"
    } | sed -E 's/sk-oai-[A-Za-z0-9_\-]+/sk-oai-***REDACTED***/g' > "$EVIDENCE_DIR/scenario-e-03-rate-limit.txt"
    break
  fi
  sleep 1
done
if [[ "$GOT_429" == "1" ]]; then
  ok "Test 3 PASS: got 429 after $i bounded requests."
else
  warn "Test 3: did not observe 429 within 15 bounded attempts."
  {
    echo "# Scenario E — Test 3: rate-limit exhaustion (NOT reproduced)"
    echo "Date: $(date -u +%FT%TZ)"
    echo "15 bounded attempts (max_tokens=5) did not trigger 429."
    echo
    echo "MaaSModelRef status at end of test:"
    model_status_snapshot
  } > "$EVIDENCE_DIR/scenario-e-03-rate-limit.txt"
fi

echo
echo "Evidence saved under $EVIDENCE_DIR/ (keys redacted)."
echo "Restoring main Demo 2 governance state..."
restore_governance
trap - EXIT
sleep 5
echo "=============================================="
