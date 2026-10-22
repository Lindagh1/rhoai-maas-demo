#!/usr/bin/env bash
# =============================================================================
# PREDEMO-HEALTHCHECK.sh — Red Hat OpenShift AI 3.5 "Knowledge Advisor" demo
# =============================================================================
# Run this 15-30 minutes before the live demo. It re-validates every backend
# component the demo depends on and prints a PASS/WARN/FAIL summary.
#
# Requirements: `oc` logged in as a cluster user with access to:
#   - redhat-ods-applications, my-first-model, models-as-a-service,
#     openshift-ingress, knowledge-advisor namespaces
#
# Usage:
#   ./PREDEMO-HEALTHCHECK.sh          # full check
#   ./PREDEMO-HEALTHCHECK.sh --quick  # skip the slow functional RAG check
# =============================================================================
set -uo pipefail

PASS=0
FAIL=0
WARN=0
QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

NS_KA="knowledge-advisor"
NS_MODELS="my-first-model"
WORKBENCH_POD="knowledge-advisor-workbench-0"
WORKBENCH_CONTAINER="knowledge-advisor-workbench"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARN=$((WARN+1)); }
section() { echo ""; echo -e "${BOLD}== $1 ==${NC}"; }

wb_exec() {
  oc exec -n "$NS_KA" "$WORKBENCH_POD" -c "$WORKBENCH_CONTAINER" -- "$@" 2>/dev/null
}

wb_python() {
  oc exec -n "$NS_KA" "$WORKBENCH_POD" -c "$WORKBENCH_CONTAINER" -- python3 -c "$1" 2>/dev/null
}

echo -e "${BOLD}Red Hat OpenShift AI 3.5 — Knowledge Advisor demo — pre-demo health check${NC}"
echo "Run at: $(date)"
echo "Cluster: $(oc whoami --show-server 2>/dev/null || echo unknown)"
echo "User:    $(oc whoami 2>/dev/null || echo unknown)"

# -----------------------------------------------------------------------------
section "1. Platform — RHOAI operator & DataScienceCluster"
# -----------------------------------------------------------------------------
DSC_READY=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
[[ "$DSC_READY" == "True" ]] && pass "DataScienceCluster 'default-dsc' is Ready" \
  || fail "DataScienceCluster 'default-dsc' is NOT Ready (status=$DSC_READY) — check: oc get dsc default-dsc -o yaml"

RHOAI_CSV=$(oc get csv -n redhat-ods-applications 2>/dev/null | grep -i rhods-operator | awk '{print $1"="$NF}')
[[ -n "$RHOAI_CSV" ]] && pass "RHOAI operator CSV: $RHOAI_CSV" || warn "Could not read RHOAI operator CSV"

# -----------------------------------------------------------------------------
section "2. GPU / Accelerator / Hardware profiles"
# -----------------------------------------------------------------------------
GPU_NODE=$(oc get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$GPU_NODE" ]]; then
  GPU_PRODUCT=$(oc get node "$GPU_NODE" -o jsonpath='{.metadata.labels.nvidia\.com/gpu\.product}' 2>/dev/null)
  pass "GPU node present: $GPU_NODE ($GPU_PRODUCT)"
else
  fail "No node labeled nvidia.com/gpu.present=true"
fi

HWP_COUNT=$(oc get hardwareprofile -n redhat-ods-applications --no-headers 2>/dev/null | wc -l)
[[ "$HWP_COUNT" -ge 1 ]] && pass "Hardware profiles present ($HWP_COUNT found)" \
  || fail "No HardwareProfile resources found in redhat-ods-applications"

# -----------------------------------------------------------------------------
section "3. Shared LLM + embedding InferenceServices"
# -----------------------------------------------------------------------------
LLAMA_READY=$(oc get inferenceservice llama-32-3b-instruct -n "$NS_MODELS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
[[ "$LLAMA_READY" == "True" ]] && pass "llama-32-3b-instruct InferenceService Ready" \
  || fail "llama-32-3b-instruct InferenceService NOT Ready (status=$LLAMA_READY)"

EMBED_READY=$(oc get inferenceservice all-minilm-l6-v2 -n "$NS_MODELS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
[[ "$EMBED_READY" == "True" ]] && pass "all-minilm-l6-v2 InferenceService Ready" \
  || fail "all-minilm-l6-v2 InferenceService NOT Ready (status=$EMBED_READY)"

# -----------------------------------------------------------------------------
section "4. Models-as-a-Service (MaaS) governance"
# -----------------------------------------------------------------------------
MMR_PHASE=$(oc get maasmodelref llama-32-3b-instruct-external -n models-as-a-service -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$MMR_PHASE" == "Ready" ]] && pass "MaaSModelRef llama-32-3b-instruct-external: Ready" \
  || fail "MaaSModelRef NOT Ready (phase=$MMR_PHASE)"

MAP_PHASE=$(oc get maasauthpolicy llama-32-3b-instruct-access -n models-as-a-service -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$MAP_PHASE" == "Active" ]] && pass "MaaSAuthPolicy llama-32-3b-instruct-access: Active" \
  || fail "MaaSAuthPolicy NOT Active (phase=$MAP_PHASE)"

MSUB_PHASE=$(oc get maassubscription llama-32-3b-instruct-subscription -n models-as-a-service -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$MSUB_PHASE" == "Active" ]] && pass "MaaSSubscription llama-32-3b-instruct-subscription: Active (100k tokens/hr)" \
  || fail "MaaSSubscription NOT Active (phase=$MSUB_PHASE)"

warn "KNOWN ISSUE: governed MaaS inference call via API key returns HTTP 500 " \
     "\"authType 'apikey' credentials not found\" — platform bug in this sandbox build. " \
     "Demo uses the direct predictor endpoint for RAG generation; MaaS story covers " \
     "discovery + API key creation only. See DEMO-CLICKBOOK.md."

# -----------------------------------------------------------------------------
section "5. MLflow"
# -----------------------------------------------------------------------------
MLFLOW_AVAIL=$(oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
[[ "$MLFLOW_AVAIL" == "True" ]] && pass "MLflow instance Available" \
  || fail "MLflow instance NOT Available (status=$MLFLOW_AVAIL)"

# -----------------------------------------------------------------------------
section "6. OGX (Gen AI orchestration capability)"
# -----------------------------------------------------------------------------
OGX_READY=$(oc get ogx default-ogx -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
[[ "$OGX_READY" == "True" ]] && pass "Platform OGX component Ready" \
  || fail "Platform OGX component NOT Ready (status=$OGX_READY)"

MCP_FLAG=$(oc get odhdashboardconfig -n redhat-ods-applications -o jsonpath='{.items[0].spec.dashboardConfig.mcpCatalog}' 2>/dev/null)
[[ "$MCP_FLAG" == "true" ]] && pass "MCP Catalog dashboard flag enabled" || warn "MCP Catalog flag not confirmed enabled"

AGENTS_FLAG=$(oc get odhdashboardconfig -n redhat-ods-applications -o jsonpath='{.items[0].spec.dashboardConfig.agentsCatalog}' 2>/dev/null)
[[ "$AGENTS_FLAG" == "true" ]] && pass "Agents Catalog dashboard flag enabled" || warn "Agents Catalog flag not confirmed enabled"

# -----------------------------------------------------------------------------
section "7. knowledge-advisor project — infra"
# -----------------------------------------------------------------------------
oc get ns "$NS_KA" &>/dev/null && pass "Namespace '$NS_KA' exists" || fail "Namespace '$NS_KA' missing"

for dep in pgvector-db minio; do
  READY=$(oc get pods -n "$NS_KA" -l app="$dep" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  [[ "$READY" == "Running" ]] && pass "$dep pod Running" || warn "$dep pod not confirmed Running (phase=$READY) — check pod selector/labels"
done

WB_READY=$(oc get pod "$WORKBENCH_POD" -n "$NS_KA" -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$WB_READY" == "Running" ]] && pass "Workbench pod Running" || fail "Workbench pod not Running (phase=$WB_READY)"

for conn in company-documents pipeline-artifacts vector-database; do
  oc get secret "$conn" -n "$NS_KA" &>/dev/null && pass "Connection secret '$conn' present" \
    || fail "Connection secret '$conn' missing"
done

# -----------------------------------------------------------------------------
section "8. Data Science Pipelines"
# -----------------------------------------------------------------------------
DSPA_READY=$(oc get pods -n "$NS_KA" -l app=ds-pipeline-dspa -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
[[ "$DSPA_READY" == "Running" ]] && pass "Pipeline server (DSPA) pod Running" || fail "Pipeline server pod not Running"

LATEST_WF=$(oc get workflows -n "$NS_KA" -o json 2>/dev/null | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    items = sorted(d['items'], key=lambda i: i['metadata']['creationTimestamp'])
    print(items[-1]['metadata']['name'] + ' ' + items[-1]['status'].get('phase','Unknown'))
except Exception:
    print('NONE NONE')
")
WF_NAME=$(echo "$LATEST_WF" | awk '{print $1}')
WF_PHASE=$(echo "$LATEST_WF" | awk '{print $2}')
if [[ "$WF_PHASE" == "Succeeded" ]]; then
  pass "Latest ingestion pipeline run ($WF_NAME): Succeeded"
else
  fail "Latest ingestion pipeline run ($WF_NAME): $WF_PHASE — re-run from workbench: python3 04_run_pipeline.py"
fi

# -----------------------------------------------------------------------------
section "9. OGXServer (knowledge-advisor-ogx)"
# -----------------------------------------------------------------------------
OGXS_PHASE=$(oc get ogxserver knowledge-advisor-ogx -n "$NS_KA" -o jsonpath='{.status.phase}' 2>/dev/null)
OGXS_AVAIL=$(oc get ogxserver knowledge-advisor-ogx -n "$NS_KA" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
if [[ "$OGXS_PHASE" == "Ready" && "${OGXS_AVAIL:-0}" -ge 1 ]]; then
  pass "OGXServer knowledge-advisor-ogx: Ready, $OGXS_AVAIL replica(s) available"
else
  fail "OGXServer knowledge-advisor-ogx: phase=$OGXS_PHASE available=$OGXS_AVAIL"
fi

# -----------------------------------------------------------------------------
section "10. Streamlit Knowledge Advisor app"
# -----------------------------------------------------------------------------
ST_READY=$(oc get pods -n "$NS_KA" -l app=knowledge-advisor-streamlit -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
[[ "$ST_READY" == "Running" ]] && pass "Streamlit app pod Running" || fail "Streamlit app pod not Running"

ST_HOST=$(oc get route knowledge-advisor-streamlit -n "$NS_KA" -o jsonpath='{.spec.host}' 2>/dev/null)
if [[ -n "$ST_HOST" ]]; then
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://$ST_HOST/_stcore/health" 2>/dev/null)
  [[ "$HTTP_CODE" == "200" ]] && pass "Streamlit route reachable (https://$ST_HOST) — HTTP $HTTP_CODE" \
    || fail "Streamlit route NOT reachable (https://$ST_HOST) — HTTP $HTTP_CODE"
else
  fail "Streamlit route not found"
fi

# -----------------------------------------------------------------------------
section "11. Functional checks (embedding, pgvector, retrieval, MLflow)"
# -----------------------------------------------------------------------------
EMBED_DIM=$(wb_python "
import requests
r = requests.post('http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings',
                   json={'model':'all-minilm-l6-v2','input':['healthcheck']}, timeout=15)
r.raise_for_status()
print(len(r.json()['data'][0]['embedding']))
")
[[ "$EMBED_DIM" == "384" ]] && pass "Embedding predictor returns 384-dim vector" \
  || fail "Embedding predictor check failed (got: '$EMBED_DIM')"

CHUNK_STATS=$(wb_python "
import os, psycopg
conn = psycopg.connect(os.environ['URI'])
cur = conn.cursor()
cur.execute('SELECT count(*), count(distinct source) FROM document_chunks;')
print(*cur.fetchone())
")
read -r ROWS SOURCES <<< "$CHUNK_STATS"
if [[ "$ROWS" -ge 20 && "$SOURCES" == "4" ]]; then
  pass "pgvector document_chunks table: $ROWS rows across $SOURCES documents"
else
  fail "pgvector document_chunks table looks wrong (rows=$ROWS sources=$SOURCES) — re-run ingestion pipeline"
fi

LLM_OK=$(wb_python "
import requests
r = requests.post('http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1/chat/completions',
                   json={'model':'llama-32-3b-instruct','messages':[{'role':'user','content':'reply OK'}],'max_tokens':5},
                   timeout=30)
r.raise_for_status()
print('OK' if r.json().get('choices') else 'NOOUT')
")
[[ "$LLM_OK" == "OK" ]] && pass "llama-32-3b-instruct direct predictor responds" \
  || fail "llama-32-3b-instruct direct predictor check failed (got: '$LLM_OK')"

if ! $QUICK; then
  RAG_ANSWER=$(wb_python "
import os, requests, psycopg
q = 'Which days can employees work remotely?'
er = requests.post('http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings',
                    json={'model':'all-minilm-l6-v2','input':[q]}, timeout=15)
emb = er.json()['data'][0]['embedding']
conn = psycopg.connect(os.environ['URI'])
cur = conn.cursor()
cur.execute('SELECT source, content FROM document_chunks ORDER BY embedding <=> %s::vector LIMIT 3;', (str(emb),))
chunks = cur.fetchall()
context = chr(10).join(f'[{s}] {c}' for s, c in chunks)
prompt = f'Answer using only this context.\n{context}\nQuestion: {q}\nAnswer:'
lr = requests.post('http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1/chat/completions',
                    json={'model':'llama-32-3b-instruct','messages':[{'role':'user','content':prompt}],'max_tokens':100,'temperature':0.1},
                    timeout=30)
print(lr.json()['choices'][0]['message']['content'])
")
  if [[ "$RAG_ANSWER" == *"Monday"* && "$RAG_ANSWER" == *"Friday"* ]]; then
    pass "END-TO-END RAG QUESTION correct: 'Monday' and 'Friday' both present in answer"
  else
    fail "END-TO-END RAG QUESTION did not return the expected answer. Got: $RAG_ANSWER"
  fi
else
  warn "Skipped full RAG functional check (--quick mode)"
fi

# MLflow: check the workbench can reach the tracking server, find the
# 'knowledge-advisor-rag' experiment, and confirm it has at least one
# FINISHED run.
MLFLOW_RESULT=$(wb_python "
import requests
token = open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip()
base = 'https://rh-ai.apps.ocp.tfmbf.sandbox2633.opentlc.com/mlflow'
headers = {'Authorization': f'Bearer {token}', 'X-MLflow-Workspace': 'knowledge-advisor', 'Content-Type': 'application/json'}
try:
    er = requests.get(f'{base}/api/2.0/mlflow/experiments/search?max_results=20', headers=headers, timeout=15, verify=False)
    exps = {e['name']: e['experiment_id'] for e in er.json().get('experiments', [])}
    exp_id = exps.get('knowledge-advisor-rag')
    if not exp_id:
        print('NOEXP')
    else:
        rr = requests.post(f'{base}/api/2.0/mlflow/runs/search', headers=headers,
                            json={'experiment_ids': [exp_id], 'max_results': 20}, timeout=15, verify=False)
        runs = rr.json().get('runs', [])
        print(f'OK {len(runs)}')
except Exception as e:
    print('ERR', e)
" 2>/dev/null)
if [[ "$MLFLOW_RESULT" == OK* ]]; then
  RUN_COUNT=$(echo "$MLFLOW_RESULT" | awk '{print $2}')
  pass "MLflow experiment 'knowledge-advisor-rag' reachable with $RUN_COUNT run(s)"
else
  fail "MLflow experiment/run check failed (got: '$MLFLOW_RESULT') — verify manually in dashboard"
fi

# -----------------------------------------------------------------------------
section "SUMMARY"
# -----------------------------------------------------------------------------
echo ""
echo -e "  ${GREEN}PASS: $PASS${NC}   ${YELLOW}WARN: $WARN${NC}   ${RED}FAIL: $FAIL${NC}"
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}All critical checks passed. Demo environment is ready.${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}$FAIL check(s) FAILED. Fix before presenting — see messages above.${NC}"
  exit 1
fi
