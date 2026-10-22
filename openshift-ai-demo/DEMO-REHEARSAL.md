# DEMO REHEARSAL — one click at a time, in presentation order

> **Verified against the live cluster on 2026-09-18, 09:4x CEST** (read-only checks only —
> nothing was created, modified, or deleted). Cluster is **frozen at commit `a911df5`**.
> `./PREDEMO-HEALTHCHECK.sh` re-run during this verification: **30 PASS / 1 WARN / 0 FAIL** —
> byte-for-byte the same result as the original build. Every resource name, namespace, and
> "expect to see" value below was re-confirmed live, not copied blind from `DEMO-CLICKBOOK.md`.
>
> This file is the **walk order**. For narration depth and the "why", see `DEMO-CLICKBOOK.md`
> (cross-referenced inline as `[§X]`). For the bare checkbox list, see `DEMO-LIVE-CHECKLIST.md`.
> Do not create/delete/edit anything beyond what's explicitly marked `CREATE LIVE` below —
> the cluster is frozen.

**Demo question (always exactly this):** *"Which days can employees work remotely?"*
**Expected answer:** contains **"Monday"** and **"Friday"** — re-confirmed live, 09:4x CEST today.

**Legend:**
- 🟢 **OPEN EXISTING** — navigate to it, show it, touch nothing that changes state
- 🟡 **RUN EXISTING** — click a button that executes against an already-prepared resource (a real pipeline run, a real chat request) — safe, idempotent-ish, no config changes
- 🔵 **CREATE LIVE** — actually creates something new (a throwaway project, a temp API key, a Connection) — safe and reversible, cleanup noted
- ⚪ **SHOW FORM → CANCEL** — open the creation wizard, narrate the fields, click Cancel — nothing created
- 🔴 **YAML/CLI REQUIRED** — no dashboard wizard exists for creating this; only show/use it from the dashboard

---

## Before you walk on stage

1. Run the health check one more time and confirm `0 FAIL`:
   ```bash
   cd openshift-ai-demo && ./PREDEMO-HEALTHCHECK.sh
   ```
   Expect: `PASS: 30   WARN: 1   FAIL: 0` (the 1 WARN is the documented MaaS API-key inference bug — expected, not a regression).

2. Open these browser tabs, in this order, and leave them open:
   1. OpenShift Console → logged in as `admin`
   2. OpenShift AI dashboard → `Data Science Projects`
   3. OpenShift AI dashboard → `Gen AI Studio → Models`
   4. Streamlit app: `https://knowledge-advisor-streamlit-knowledge-advisor.apps.ocp.tfmbf.sandbox2633.opentlc.com` (confirmed **HTTP 200** live)
   5. JupyterLab for `knowledge-advisor-workbench` (Workbenches tab → **Open**) — confirm the pod shows `2/2 Running` before opening
   6. MLflow: `https://rh-ai.apps.ocp.tfmbf.sandbox2633.opentlc.com/mlflow`, workspace switched to `knowledge-advisor`
   7. A terminal with `oc whoami` confirming you're logged in, plus a Terminal tab open inside JupyterLab

3. Do **not** re-run anything from `PART 7` of the original build prompt — the cluster is frozen. The only live-write actions on stage are the ones explicitly marked 🔵 below, and every one of them is additive/reversible.

---

# PART 1 — ADMIN WALKTHROUGH (Alex)

### 1.1 — Operator install view 🟢 `[§A]`
- **Resource:** `ClusterServiceVersion/rhods-operator.3.5.0` — namespace `redhat-ods-operator`
- **Where:** OpenShift Console → **Operators → Installed Operators** → filter project `redhat-ods-operator` → click **Red Hat OpenShift AI**
- **Expect to see:** Version `3.5.0`, Status `Succeeded`
- **Say:** "OpenShift AI installs like any OpenShift Operator — OperatorHub, one click, then it manages everything else declaratively."
- **Fallback:** screenshot (see capture list below) if the console is slow.

### 1.2 — DataScienceCluster 🟢 `[§B]`
- **Resource:** `DataScienceCluster/default-dsc`
- **Where:** same CSV → **Data Science Cluster** tab → `default-dsc` → **YAML** or **Details**
- **Expect to see:** Status `Ready` (re-confirmed live: `phase=Ready`). Components `Managed`: `kserve`, `workbenches`, `datasciencepipelines`, `dashboard`, `modelregistry`, `ogx`, `trustyai`.
- **Say:** "Every capability — pipelines, serving, model registry, MLflow, and OGX — is a toggle on this one object."
- **Fallback:** screenshot of the YAML `spec.components` block.

### 1.3 — GPU node / Accelerator 🟢 `[§C]`
- **Resource:** node `ip-10-0-31-7.us-east-2.compute.internal`
- **Where:** OpenShift Console → **Compute → Nodes** → click the GPU node → **Details** tab → Labels
- **Expect to see:** `nvidia.com/gpu.product=NVIDIA-L4`, `nvidia.com/gpu.count=1`, `nvidia.com/gpu.memory=23034` (MiB), driver `580.82.07`, CUDA runtime `13.0`, family `ada-lovelace` — all re-confirmed live.
- **Say:** "One real NVIDIA L4. The GPU Operator auto-labels it; OpenShift AI schedules against it through a Hardware Profile."

### 1.4 — Hardware Profile ⚪ then 🟢 `[§D]`
- **Resource:** `HardwareProfile/gpu-profile` — namespace `redhat-ods-applications`
- **Where:** OpenShift AI dashboard → **Settings → Hardware profiles**
- **Clicks:** **Create hardware profile** → fill fields below → **Cancel** → click existing **gpu-profile** row
- **Fields to narrate (re-confirmed live values):**

  | Field | Value |
  |---|---|
  | Name | `gpu-profile` |
  | CPU | default `1`, min `1`, max `8` |
  | Memory | default `12Gi`, min `1Gi`, max `16Gi` |
  | Accelerator (`nvidia.com/gpu`) | default `1`, min `1`, max `4` |

- **Say:** "A reusable 'shape' of compute that data scientists pick from a dropdown."
- **Fallback:** screenshot of the `gpu-profile` detail page.

### 1.5 — Project 🔵 then 🟢 `[§E]`
- **Resource to open after:** `knowledge-advisor` project (namespace `knowledge-advisor`, Active)
- **Where:** OpenShift AI dashboard → **Data Science Projects**
- **Clicks:** **Create project** → type `demo-scratch-live` → **Cancel** (or actually create it and delete right after if you want a truly live create — it's a bare namespace, harmless either way) → click **knowledge-advisor** in the list
- **Expect to see on knowledge-advisor Overview:** tiles for Workbenches (1), Pipelines (1 server), Connections (3)
- **Say:** "A Data Science Project is just an OpenShift namespace with dashboard conventions layered on."

### 1.6 — LLM deployment ⚪ then 🟢 `[§F]`
- **Resource to open after:** `InferenceService/llama-32-3b-instruct` — namespace `my-first-model`
- **Where:** project `my-first-model` → **Models** tab → **Deploy model**
- **Clicks:** walk fields → **Cancel** → open existing `llama-32-3b-instruct` row
- **Expect to see (re-confirmed live):** conditions `IngressReady=True`, `PredictorReady=True`, `Ready=True`; pod `llama-32-3b-instruct-predictor-97fdb759b-jvwqw` `3/3 Running`; internal endpoint `http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080`
- **Say:** "Pick a source, a runtime, a hardware profile, hit deploy — KServe does the rest. We're opening the one that's been serving traffic all along instead of waiting several minutes for a fresh GPU warm-up."
- **Fallback:** screenshot of the Models tab row showing `Ready`.

### 1.7 — Embedding deployment ⚪ then 🟢 `[§G]`
- **Resource to open after:** `InferenceService/all-minilm-l6-v2` — namespace `my-first-model`
- **Where:** **Model Catalog** → search `minilm` → tile → **Deploy model**
- **Clicks:** walk fields → **Cancel** → open existing `all-minilm-l6-v2` row
- **Expect to see (re-confirmed live):** `Ready=True`; label `opendatahub.io/genai-asset: "true"`; endpoint `http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings`
- **Say:** "Same wizard as the LLM, straight from the catalog, CPU-only footprint — this is what turns text into the 384-number vectors pgvector searches over."

### 1.8 — MaaS discovery view 🟢 `[§H]`
- **Resource:** `MaaSModelRef/llama-32-3b-instruct-external` — namespace `models-as-a-service` — status `Ready`, endpoint `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`, gateway `maas-default-gateway`
- **Where:** OpenShift AI dashboard → **Gen AI Studio → Models** → point at `llama-32-3b-instruct` MaaS badge
- **Say:** "Alex's Llama deployment, registered once with MaaS — from here it's discoverable like a commercial model API."
- **⚠️ Say out loud, don't hide it:** "The governed inference call through this endpoint with an API key currently hits a platform bug — HTTP 500 on credential passthrough. Our RAG app calls the direct predictor instead. Filed and documented — I'd rather show you the real state than fake it."

### 1.9 — Subscription & quota 🟢 `[§I]`
- **Resource:** `MaaSSubscription/llama-32-3b-instruct-subscription` — namespace `models-as-a-service`
- **Where:** same model detail page → Access & Quota tab
- **Expect to see (re-confirmed live):** Status `Active`, Priority `1`, rate limit **`100,000` tokens / `1h`** (exact spec: `tokenRateLimits: [{limit: 100000, window: "1h"}]`)
- **Say:** "Every consumer is metered — 100k tokens/hour, enforced by Kuadrant's Limitador before the request reaches vLLM."

### 1.10 — Authorization policy 🟢 `[§J]`
- **Resource:** `MaaSAuthPolicy/llama-32-3b-instruct-access` — namespace `models-as-a-service` — status `Active` (re-confirmed live)
- **Where:** same page as 1.9
- **Say:** "Authorino checks identity/subscription before Limitador checks quota — two policy engines, one gateway hop."

---

# PART 2 — DATA SCIENTIST WALKTHROUGH (Maya)

### 2.1 — Discover MaaS model 🟢 `[§K]`
- **Where:** **Gen AI Studio → Models** → click `llama-32-3b-instruct` card
- **Expect to see:** endpoint `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`, an **API Keys** action
- **Say:** "Looks exactly like discovering a model on a commercial marketplace."

### 2.2 — API key 🔵 (create + revoke) `[§L]`
- **Where:** model detail page → **API Keys** tab
- **Clicks:** **Create API key** → name `demo-live-key` → **Create** (key shown once) → **Revoke** immediately after showing it
- **Fallback / what the app actually uses:** pre-created `Secret/maas-api-key` — namespace `knowledge-advisor` — keys `api-key`, `endpoint`, `model-name` (re-confirmed present live; **values never shown**)
- **Say:** "Maya creates her own key with one click. I'm revoking this one right after — the app itself runs on a key we provisioned ahead of time, so nothing depends on a 30-second-lived credential."

### 2.3 — Project (Maya's view) — same as 1.5, `[§M]`, skip repeating live if already shown.

### 2.4 — Connection: vector database 🔵 or ⚪ `[§N]`
- **Resource to open after:** `Secret/vector-database` — namespace `knowledge-advisor` — annotation `connection-type-ref: uri-v1`, display name `vector-database`
- **Where:** project `knowledge-advisor` → **Connections** tab → **Create connection** → type **URI**
- **Clicks:** fill fields below → **Cancel** (or create-and-delete a duplicate for a true live create) → open existing `vector-database`
- **Fields:**

  | Field | Value |
  |---|---|
  | Connection name | `vector-database` |
  | Type | URI |
  | URI | `postgresql://ragadmin:••••••••@pgvector-db.knowledge-advisor.svc.cluster.local:5432/ragdb` *(password never shown)* |

- **Backing DB (re-confirmed live):** PostgreSQL **16.15** with `pgvector` extension, pod `pgvector-db-5844bdf9ff-k4rk5` `1/1 Running`
- **Say:** "A Connection is 'here's how to reach an external service.' Attach once to a Workbench, every notebook reads `os.environ['URI']` — no hardcoded credentials."

### 2.5 — Connection: object storage 🟢 (show, don't duplicate) `[§O]`
- **Resources:** `Secret/company-documents` and `Secret/pipeline-artifacts` — namespace `knowledge-advisor` — both annotated `connection-type-ref: s3` (re-confirmed present)
- **Where:** same Connections tab
- **Expect to see:** both listed, endpoint `http://minio.knowledge-advisor.svc.cluster.local:9000`, bucket `documents` (for company-documents)
- **Backing MinIO (re-confirmed live):** pod `minio-667ffb4dc5-8q2p4` `1/1 Running`; bucket `documents/raw/` contains exactly 4 folders: `employee-benefits-guide.md`, `hr-remote-work-policy.md`, `it-security-policy.md`, `onboarding-guide.md`
- **Say:** "Same Connection pattern, S3-flavored — works identically against AWS S3 or Ceph."

### 2.6 — Workbench ⚪ then 🟢 `[§P]`
- **Resource to open after:** `Notebook/knowledge-advisor-workbench` — pod `knowledge-advisor-workbench-0` `2/2 Running` (re-confirmed live, up 24h)
- **Where:** project `knowledge-advisor` → **Workbenches** tab → **Create workbench**
- **Clicks:** walk fields → **Cancel** → open existing row → **Open**
- **Fields:**

  | Field | Value |
  |---|---|
  | Name | `knowledge-advisor-workbench` |
  | Image | `s2i-generic-data-science-notebook:3.5` |
  | Hardware profile | `default-profile` |
  | Connections | ✅ `vector-database`, ✅ `company-documents` |

- **Say:** "Pick an image, a profile, which Connections to attach — env vars get wired automatically."

### 2.7 — Embedding request 🟡 `[§Q]`
- **Where:** in the open JupyterLab tab → `02_semantic_search_test.py` → **Run All Cells** (~2 seconds)
- **Expect to see:** top-3 pgvector matches, top hit `hr-remote-work-policy.md`, cosine score **`0.7189`**
- **Backing data (re-confirmed live):** `document_chunks` table has **26 rows** across 4 documents
- **Say:** "Retrieval half of RAG in isolation — embed the question, pgvector finds the 3 closest policy chunks."

### 2.8 — LLM request 🟡 `[§R]`
- **Where:** JupyterLab Terminal
- **Clicks:** run the direct-predictor curl:
  ```bash
  curl -s http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"llama-32-3b-instruct","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":30}'
  ```
- **Say:** "Direct in-cluster call — this is the path our RAG app actually uses for generation."
- *(Optional, candid)* run the MaaS gateway curl with `$MAAS_API_KEY` pre-exported — narrate the known 500 if you show it.

### 2.9 — Pipeline server 🟢 (view only, do not resubmit) `[§S]`
- **Resource:** `DataSciencePipelinesApplication/dspa` — namespace `knowledge-advisor` — pod `ds-pipeline-dspa-7d7cbdb955-wwfrl` `2/2 Running` (re-confirmed live)
- **Where:** **Pipelines** tab → gear icon → **Configure pipeline server**
- **Expect to see:** object storage connection `pipeline-artifacts`, bucket `pipelines`
- **⚠️ Do not click Save/Submit** — would restart the server mid-demo.

### 2.10 — Pipeline import 🟢 (or 🔵 additive re-import) `[§T]`
- **Where:** **Pipelines** tab → **Pipelines** sub-tab → open `knowledge-advisor-ingestion`
- **Expect to see:** 4-node graph: `load-documents → chunk-documents → embed-chunks → store-vectors`

### 2.11 — Pipeline run 🟡 (real new run) `[§U]`
- **Where:** pipeline detail → **Create run**
- **Fields:** Run name `knowledge-advisor-ingestion-run-live`, Experiment `knowledge-advisor`, defaults for `bucket`/`prefix`/`embed_model`
- **Expect to see:** graph turns green node-by-node (~35–45s), ends `Succeeded` — matches the last real run `knowledge-advisor-ingestion-k8r5z` (re-confirmed `Succeeded` live)
- **Say:** "A real run, right now — reading the 4 documents, chunking, embedding, rewriting the vector table."

### 2.12 — OGXServer 🔴 create / 🟡 use `[§V]`
- **Resource:** `OGXServer/knowledge-advisor-ogx` — pod `knowledge-advisor-ogx-7f4cc9d646-xhg6q` `1/1 Running` — status **`Ready`, 1 replica available** (re-confirmed live)
- **Creation:** `YAML/CLI REQUIRED` — no dashboard wizard in this build. Do not recreate live.
- **Where to click to use it:** Gen AI Studio → project switcher → `knowledge-advisor` → model dropdown shows both models via `knowledge-advisor-ogx`
- **Live curl (safe, read-only):**
  ```bash
  curl -s http://knowledge-advisor-ogx-service.knowledge-advisor.svc.cluster.local:8321/v1/models
  ```
  **Expect exactly (re-confirmed live seconds ago):**
  ```json
  {"object":"list","data":[
    {"id":"llama-32-3b-instruct/llama-32-3b-instruct","object":"model","owned_by":"ogx",
     "custom_metadata":{"model_type":"llm","provider_id":"llama-32-3b-instruct"}},
    {"id":"all-minilm-l6-v2/all-minilm-l6-v2","object":"model","owned_by":"ogx",
     "custom_metadata":{"model_type":"embedding","provider_id":"all-minilm-l6-v2","embedding_dimension":384}}
  ]}
  ```
- **Say:** "One OpenAI-compatible server in front of inference and vector store. Creating it is still YAML on this release; using it is pure dashboard."

### 2.13 — Playground 🟡 `[§W]`
- **Where:** **Gen AI Studio → Playground** → Server `knowledge-advisor-ogx` → Model `llama-32-3b-instruct` → type prompt → **Send**
- **Say:** "Zero-code sanity check of any OGX-registered model."

### 2.14 — RAG with visible retrieval 🟡 `[§X]` — **the money shot**
- **Where:** Streamlit tab (already open, `HTTP 200` re-confirmed) → question box pre-filled → **Ask Knowledge Advisor**
- **Expect to see, in order:**
  1. "📄 Retrieved context" cards — top hit `hr-remote-work-policy.md`, score `0.719`
  2. "✅ Answer" containing **"Monday"** and **"Friday"** — **re-confirmed by health check run seconds before this document was finalized**
- **Say:** "Retrieval visible before generation — no hallucination risk, and you know instantly whether a wrong answer is a retrieval or generation problem."

### 2.15 — Application (generalization) 🟡 `[§Y]`
- Same Streamlit tab, optional second question, e.g. *"What is the process for requesting new hardware?"*

### 2.16 — MLflow 🟢 + optional 🔵 `[§Z]`
- **Resource:** experiment `knowledge-advisor-rag`, workspace `knowledge-advisor` — **3 `FINISHED` runs re-confirmed live**: `builtin-satoken-test`, `auto-injected-env-test`, `connectivity-test`
- **Where:** MLflow URL → workspace `knowledge-advisor` → experiment → open a run
- **Optional live create (2 seconds, in JupyterLab terminal):**
  ```python
  import mlflow
  mlflow.set_experiment("knowledge-advisor-rag")
  with mlflow.start_run(run_name="live-demo-run"):
      mlflow.log_param("question", "Which days can employees work remotely?")
      mlflow.log_metric("retrieval_top1_score", 0.719)
      mlflow.log_metric("answer_correct", 1)
  ```

### 2.17 — MCP Catalog 🟢 `[§AA]`
- **Where:** left nav → **MCP Catalog** (flag `mcpCatalog: true`, re-confirmed enabled)

### 2.18 — Agents Catalog 🟢 `[§AB]`
- **Where:** left nav → **Agents Catalog** (flags `agentsCatalog: true`, `agentConfigManagement: true`, re-confirmed enabled)

---

## Absolute must-not-fail moment

**Streamlit app → "Ask Knowledge Advisor"** with the pre-filled question.
Expected: context cards citing `hr-remote-work-policy.md`, then an answer containing
**"Monday and Friday"**. Re-validated by a full `PREDEMO-HEALTHCHECK.sh` run immediately
before this document was written (30 PASS / 1 WARN / 0 FAIL). Run the health check once
more, 15–30 minutes before you go on stage.

## Fallbacks quick-reference

| If this fails live... | ...do this instead |
|---|---|
| API key creation form errors | "Here's one I created earlier" — `Secret/maas-api-key`, never reveal value |
| Pipeline run doesn't finish in time | Open run `knowledge-advisor-ingestion-k8r5z` (Succeeded) from history |
| Playground can't reach the model | JupyterLab terminal curl against the OGX service directly (2.12) |
| Streamlit app slow/down | Run `03_rag_end_to_end.py` in JupyterLab — identical output |
| MLflow UI slow | `mlflow.search_runs()` snippet in a notebook cell |
| Any dashboard page 500s | Refresh once; if it persists, narrate from a captured screenshot |

---

## Screenshots to capture NOW, before the demo (fallback insurance)

Capture these full-screen, in light mode matching your theme, and save them somewhere you
can pull up instantly if a live click fails:

1. CSV detail page — `rhods-operator.3.5.0`, `Succeeded` (§1.1)
2. `default-dsc` YAML — `spec.components` block with all `Managed` (§1.2)
3. GPU node **Labels** tab showing `NVIDIA-L4` / driver / CUDA (§1.3)
4. `gpu-profile` Hardware Profile detail page (§1.4)
5. `knowledge-advisor` project **Overview** tab with all tiles populated (§1.5)
6. `llama-32-3b-instruct` Models tab row — `Ready`, endpoint shown (§1.6)
7. `all-minilm-l6-v2` Models tab row — `Ready` (§1.7)
8. Gen AI Studio → Models list with the MaaS badge on `llama-32-3b-instruct` (§1.8)
9. Access & Quota tab — `Active`, `100,000 tokens/hour` (§1.9)
10. API Keys tab — the one-time key reveal dialog (capture with a fake/expired key only!) (§2.2)
11. Connections tab — all 3 connections listed (§2.4/2.5)
12. Workbenches tab — `Running` status + JupyterLab file browser open (§2.6)
13. `02_semantic_search_test.py` output cell — top-3 matches with scores (§2.7)
14. Terminal — direct predictor `curl` JSON response (§2.8)
15. Pipeline **graph view** — 4-node DAG (§2.10)
16. Pipeline run — fully green graph, `Succeeded` badge (§2.11)
17. Terminal — OGX `/v1/models` curl output (§2.12)
18. Playground — a sent prompt + response (§2.13)
19. **Streamlit app — full page: question, retrieved-context cards, answer card** (§2.14) — the single most important screenshot
20. MLflow run detail — params + metrics panel (§2.16)
21. MCP Catalog tile grid (§2.17)
22. Agents Catalog tile grid (§2.18)

---

*Last live-verified: 2026-09-18. Cluster frozen at commit `a911df5`. Re-run
`./PREDEMO-HEALTHCHECK.sh` before presenting — do not trust this document's "expect to see"
values if that script shows a new FAIL.*
