#!/usr/bin/env bash
# Demo 2 — Scenario D: real inference as the genuine non-admin end-user.
#
# Uses the real maas-demo2-user API key (created through the dashboard in
# Scenario C, never the admin's own token). The key is read from a local,
# gitignored file (or DEMO2_API_KEY env var) — never hardcoded, never
# printed in full, never committed.
#
# Exercises both documented discovery/inference surfaces:
#   1. GET  /v1/models                 (OpenAI-compatible model discovery)
#   2. POST /v1/chat/completions       (body-based routing, recommended)
# Saves sanitized (API-key-redacted) evidence under evidence/demo2/.
# NOTE: -e is deliberately omitted. This script inspects HTTP status codes
# from curl and classifies them (200 = pass, anything else = warn/report);
# a non-200 response is a finding to record, not a script failure.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

EVIDENCE_DIR="evidence/demo2"
mkdir -p "$EVIDENCE_DIR"

API_KEY="${DEMO2_API_KEY:-}"
KEY_FILE="${DEMO2_API_KEY_FILE:-$DEMO2_USER_APIKEY_FILE}"
if [[ -z "$API_KEY" ]]; then
  if [[ -f "$KEY_FILE" ]]; then
    API_KEY="$(cat "$KEY_FILE")"
  else
    err "No API key found. Run Scenario C (dashboard) first, or set DEMO2_API_KEY / DEMO2_API_KEY_FILE."
    exit 1
  fi
fi
[[ -z "$API_KEY" ]] && { err "API key is empty."; exit 1; }

HOST="$(maas_host_url)"
echo "=============================================="
echo "Demo 2 — Scenario D: inference as maas-demo2-user"
echo "=============================================="
echo "MaaS URL: $HOST"

# Resolve gateway IP for clusters where DNS hasn't propagated to this shell
GATEWAY_ADDR=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
RESOLVE_OPT=()
if [[ -n "$GATEWAY_ADDR" ]] && echo "$GATEWAY_ADDR" | grep -qE '[a-zA-Z]'; then
  GATEWAY_IP=$(dig +short "$GATEWAY_ADDR" 2>/dev/null | head -1 || true)
  [[ -n "$GATEWAY_IP" ]] && RESOLVE_OPT=(--resolve "$(maas_hostname):443:${GATEWAY_IP}")
fi

redact() { sed -E 's/sk-oai-[A-Za-z0-9_\-]+/sk-oai-***REDACTED***/g'; }

# --- Step 1: model discovery (/v1/models) ---
echo
echo "--- Step 1: GET /v1/models (model discovery) ---"
MODELS_RESP=$(curl -sSk "${RESOLVE_OPT[@]}" --connect-timeout 10 --max-time 30 \
  -H "Authorization: Bearer ${API_KEY}" \
  -w '\n%{http_code}' \
  "${HOST}/v1/models" 2>/dev/null || echo -e "\n000")
MODELS_CODE=$(echo "$MODELS_RESP" | tail -1)
MODELS_BODY=$(echo "$MODELS_RESP" | sed '$d')
echo "HTTP status: $MODELS_CODE"
echo "$MODELS_BODY" | python3 -m json.tool 2>/dev/null | head -30 || echo "$MODELS_BODY" | head -c 500

{
  echo "# Scenario D — Step 1: GET /v1/models"
  echo "Date: $(date -u +%FT%TZ)"
  echo "HTTP status: $MODELS_CODE"
  echo "$MODELS_BODY" | python3 -m json.tool 2>/dev/null || echo "$MODELS_BODY"
} | redact > "$EVIDENCE_DIR/scenario-d-01-models.txt"

MODEL_ID=$(echo "$MODELS_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',[{}])[0].get('id','')) if d.get('data') else print('')" 2>/dev/null || echo "")
MODEL_ID="${MODEL_ID:-facebook/opt-125m}"
echo "Resolved model id for inference: $MODEL_ID"

if [[ "$MODELS_CODE" == "200" ]]; then
  ok "Model discovery succeeded (HTTP 200) — maas-demo2-user can see demo-simulator via its real subscription."
else
  warn "Model discovery did not return 200 (got $MODELS_CODE)."
fi

# --- Step 2: real inference (/v1/chat/completions) ---
echo
echo "--- Step 2: POST /v1/chat/completions (body-based routing) ---"
# Body goes through a temp file + --data-binary, not an inline -d "<escaped
# JSON>" string: an inline escaped-quote one-liner was found to get mangled
# when typed/pasted in some terminals (e.g. a browser-based workbench
# terminal), producing a malformed request and a misleading 404 — see
# docs/demo2/05-troubleshooting.md. --http1.1 is also required when this
# script runs from inside an in-cluster pod (e.g. a workbench), where
# HTTP/2 to the external MaaS route was observed to hang/close with no
# response; calls from outside the cluster work fine either way.
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
cat > "$BODY_FILE" <<EOF
{"model": "${MODEL_ID}", "messages": [{"role": "user", "content": "Say hello from the Demo 2 end-user journey."}], "max_tokens": 30}
EOF
INFER_RESP=$(curl -sSk --http1.1 "${RESOLVE_OPT[@]}" --connect-timeout 10 --max-time 30 \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -D - -o /tmp/demo2-infer-body.$$ -w '\n%{http_code}' \
  --data-binary "@${BODY_FILE}" \
  "${HOST}/v1/chat/completions" 2>/dev/null || echo -e "\n000")
INFER_HEADERS=$(echo "$INFER_RESP" | sed '$d')
INFER_CODE=$(echo "$INFER_RESP" | tail -1)
INFER_BODY=$(cat /tmp/demo2-infer-body.$$ 2>/dev/null || echo "")
rm -f /tmp/demo2-infer-body.$$

echo "HTTP status: $INFER_CODE"
echo "--- Rate-limit headers ---"
echo "$INFER_HEADERS" | grep -i -E 'x-ratelimit|retry-after' || echo "(none observed)"
echo "--- Body ---"
echo "$INFER_BODY" | python3 -m json.tool 2>/dev/null || echo "$INFER_BODY"

{
  echo "# Scenario D — Step 2: POST /v1/chat/completions"
  echo "Date: $(date -u +%FT%TZ)"
  echo "Model: $MODEL_ID"
  echo "HTTP status: $INFER_CODE"
  echo "## Response headers (rate-limit related)"
  echo "$INFER_HEADERS" | grep -i -E 'x-ratelimit|retry-after|content-type' || echo "(none observed)"
  echo "## Response body"
  echo "$INFER_BODY" | python3 -m json.tool 2>/dev/null || echo "$INFER_BODY"
} | redact > "$EVIDENCE_DIR/scenario-d-02-inference.txt"

if [[ "$INFER_CODE" == "200" ]]; then
  USAGE=$(echo "$INFER_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('usage',{})))" 2>/dev/null || echo "{}")
  CONTENT=$(echo "$INFER_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('choices',[{}])[0].get('message',{}).get('content',''))" 2>/dev/null || echo "")
  ok "Inference succeeded (HTTP 200) as the real maas-demo2-user identity."
  echo "Token usage: $USAGE"
  echo "Model reply (truncated): ${CONTENT:0:120}"
else
  warn "Inference did not return 200 (got $INFER_CODE)."
fi

echo
echo "Evidence saved (API key redacted):"
echo "  $EVIDENCE_DIR/scenario-d-01-models.txt"
echo "  $EVIDENCE_DIR/scenario-d-02-inference.txt"
echo "=============================================="
[[ "$MODELS_CODE" == "200" && "$INFER_CODE" == "200" ]]
