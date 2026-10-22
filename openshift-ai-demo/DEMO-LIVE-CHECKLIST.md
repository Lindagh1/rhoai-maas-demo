# DEMO LIVE CHECKLIST — what you actually click/do on stage

> This file contains **only** what you touch during the live presentation —
> no backend prep, no explanations of *why*. For the full narration and
> field-by-field detail behind each step, see `DEMO-CLICKBOOK.md` (linked
> inline as `[§X]`). Run `./PREDEMO-HEALTHCHECK.sh` 15–30 min before you start
> and confirm `0 FAIL`.

**Demo question (always use exactly this):** *"Which days can employees work remotely?"* → expect **"Monday and Friday"**.

**Open these browser tabs before you start** (so no page-load time burns during the demo):
1. OpenShift AI dashboard, logged in → `Data Science Projects`
2. OpenShift AI dashboard → `Gen AI Studio → Models`
3. Streamlit app: `https://knowledge-advisor-streamlit-knowledge-advisor.apps.ocp.tfmbf.sandbox2633.opentlc.com`
4. JupyterLab for `knowledge-advisor-workbench` (Open from the Workbenches tab)
5. MLflow: `https://rh-ai.apps.ocp.tfmbf.sandbox2633.opentlc.com/mlflow` (workspace switched to `knowledge-advisor`)
6. A terminal with `oc` logged in to the cluster, and a Terminal tab open inside JupyterLab

---

## Part 1 — Admin walkthrough (Alex)

- [ ] **Operators** — Installed Operators → Red Hat OpenShift AI → open CSV `[§A]`
- [ ] **DataScienceCluster** — CSV → Data Science Cluster tab → `default-dsc` → show `Ready` + component list `[§B]`
- [ ] **GPU node** — Compute → Nodes → GPU node → Labels → point at `nvidia.com/gpu.product=NVIDIA-L4` `[§C]`
- [ ] **Hardware Profile** — Settings → Hardware profiles → **Create hardware profile** → fill fields → **Cancel** → open `gpu-profile` `[§D]`
- [ ] **Project** — Data Science Projects → **Create project** → type `demo-scratch` → **Cancel** → open `knowledge-advisor` `[§E]`
- [ ] **LLM deploy** — `my-first-model` project → Models → **Deploy model** → fill fields → **Cancel** → open `llama-32-3b-instruct` (Ready) `[§F]`
- [ ] **Embedding deploy** — Model Catalog → search `minilm` → **Deploy model** → fill fields → **Cancel** → open `all-minilm-l6-v2` (Ready) `[§G]`
- [ ] **MaaS discovery view** — Gen AI Studio → Models → point at `llama-32-3b-instruct` MaaS badge `[§H]`
  - ⚠️ Say out loud: MaaS API-key inference call has a known platform bug (HTTP 500) — RAG app uses the direct predictor instead.
- [ ] **Subscription/quota** — same model page → Access & Quota tab → point at `100,000 tokens/hour`, `Active` `[§I/§J]`

## Part 2 — Data Scientist walkthrough (Maya)

- [ ] **Discover model** — Gen AI Studio → Models → click `llama-32-3b-instruct` card `[§K]`
- [ ] **API key** — model page → API Keys tab → **Create API key** → name `demo-live-key` → **Create** → show once → **Revoke** `[§L]`
- [ ] **Connection (vector DB)** — `knowledge-advisor` → Connections → **Create connection** → type URI → fill fields → **Cancel** (or create+delete) → open `vector-database` `[§N]`
- [ ] **Connection (object storage)** — Connections → **Create connection** → type S3 → fill fields → **Cancel** → open `company-documents` `[§O]`
- [ ] **Workbench** — Workbenches tab → **Create workbench** → fill fields → **Cancel** → open `knowledge-advisor-workbench` → **Open** (launches JupyterLab) `[§P]`
- [ ] **Embedding request** — in JupyterLab, open `02_semantic_search_test.py` → **Run All** → show top-3 pgvector matches `[§Q]`
- [ ] **LLM request** — JupyterLab Terminal → run the direct-predictor `curl` → show JSON response `[§R]`
- [ ] **Pipeline server** — Pipelines tab → gear icon → **Configure pipeline server** → point at fields (do NOT resubmit) `[§S]`
- [ ] **Pipeline import** — Pipelines tab → **Import pipeline** (optional live re-import, or just open existing) → open `knowledge-advisor-ingestion` graph `[§T]`
- [ ] **Pipeline run** — pipeline detail → **Create run** → name it → **Create** → watch graph turn green node-by-node → click a node → **Logs** `[§U]`
- [ ] **OGXServer usage** — terminal → `curl http://knowledge-advisor-ogx-service.knowledge-advisor.svc.cluster.local:8321/v1/models` → show both models registered `[§V]`
- [ ] **Playground** — Gen AI Studio → Playground → select server `knowledge-advisor-ogx` → select model `llama-32-3b-instruct` → type a prompt → **Send** `[§W]`
- [ ] **RAG with visible retrieval** — Streamlit app → question box already filled → **Ask Knowledge Advisor** → point at retrieved-context cards, THEN the answer card `[§X]`
- [ ] **Application** — (same Streamlit tab) optionally ask a second question to show it generalizes `[§Y]`
- [ ] **MLflow** — MLflow tab → workspace `knowledge-advisor` → experiment `knowledge-advisor-rag` → open a `FINISHED` run → point at params/metrics. Optional: run the 4-line `mlflow.start_run()` snippet live in the JupyterLab terminal `[§Z]`
- [ ] **MCP Catalog** — left nav → MCP Catalog → browse tiles → open one `[§AA]`
- [ ] **Agents Catalog** — left nav → Agents Catalog → browse tiles → open one `[§AB]`

## Fallbacks (if a live click fails on stage)

| If this fails live... | ...do this instead |
|---|---|
| API key creation form errors | Say "here's one I created earlier" — reference `maas-api-key` secret, do not reveal value |
| Pipeline run doesn't finish in time | Open the already-`Succeeded` run from history and narrate the graph instead |
| Playground can't reach the model | Fall back to the JupyterLab terminal `curl` against the OGX service directly |
| Streamlit app is slow/down | Run `03_rag_end_to_end.py` in JupyterLab instead — identical output |
| MLflow UI is slow to load | Show run history via the `mlflow.search_runs()` snippet in a notebook cell instead |
| Any dashboard page 500s | Refresh once; if it persists, narrate from `DEMO-CLICKBOOK.md` screenshots/description instead of clicking live |

## Absolute must-not-fail moment

The single most important click: **Streamlit app → "Ask Knowledge Advisor"** with the pre-filled question.
Expected: retrieved context cards showing `hr-remote-work-policy.md`, then an answer containing
**"Monday and Friday"**. This was re-validated by `PREDEMO-HEALTHCHECK.sh` immediately before this
document was written. If in doubt, run the health check again right before walking on stage.
