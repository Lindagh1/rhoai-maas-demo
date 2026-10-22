#!/usr/bin/env bash
# infer.sh - Happy-path MaaS inference call (make infer).
#
# Application -> OpenAI-compatible API -> MaaS Gateway -> Authorization+quota -> Model
#
# Never calls the backend model directly. Always goes through the MaaS
# Gateway host with an API key.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh
source scripts/api_key.sh
require_login

HOST="$(maas_host_url)"
API_KEY="$(get_or_create_api_key)" || exit 1

echo "=============================================="
echo "MaaS happy-path inference"
echo "=============================================="
echo "MaaS URL: $HOST"

# Resolve gateway IP for clusters where DNS hasn't propagated to this shell
GATEWAY_ADDR=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
RESOLVE_OPT=()
if [[ -n "$GATEWAY_ADDR" ]] && echo "$GATEWAY_ADDR" | grep -qE '[a-zA-Z]'; then
  GATEWAY_IP=$(dig +short "$GATEWAY_ADDR" 2>/dev/null | head -1 || true)
  [[ -n "$GATEWAY_IP" ]] && RESOLVE_OPT=(--resolve "$(maas_hostname):443:${GATEWAY_IP}")
fi

# List models through the management API
MODELS_RESPONSE=$(curl -sSk "${RESOLVE_OPT[@]}" --connect-timeout 10 --max-time 30 \
  -H "Authorization: Bearer ${API_KEY}" \
  "${HOST}/maas-api/v1/models" 2>/dev/null || echo "{}")
MODEL_ID=$(echo "$MODELS_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',[{}])[0].get('id','')) if d.get('data') else print('')" 2>/dev/null || echo "")
MODEL_ID="${MODEL_ID:-facebook/opt-125m}"
echo "Model: $MODEL_ID"

RESPONSE=$(curl -sSk "${RESOLVE_OPT[@]}" --connect-timeout 10 --max-time 30 \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -w '\n%{http_code}' \
  -d "{\"model\": \"${MODEL_ID}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello from the MaaS demo\"}], \"max_tokens\": 30}" \
  "${HOST}/v1/chat/completions" 2>/dev/null || echo -e "\n000")

CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "HTTP status: $CODE"
if [[ "$CODE" == "200" ]]; then
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  ok "Inference succeeded (HTTP 200)"
else
  echo "$BODY"
  warn "Inference did not return 200"
fi
echo "=============================================="
[[ "$CODE" == "200" ]]
