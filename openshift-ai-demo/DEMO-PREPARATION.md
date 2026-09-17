# DEMO-PREPARATION.md — Cursor prep vs. Live action split

> **⚠️ SUPERSEDED (2026-09-17): strategy changed from "build live" to "build now, demo the result."**
> Every resource that this document originally described as a *future* live-build step has
> now been **created and validated end-to-end** (30 PASS / 1 documented WARN / 0 FAIL —
> run `./PREDEMO-HEALTHCHECK.sh` to reconfirm). This includes: `all-minilm-l6-v2`,
> `knowledge-advisor` project, PostgreSQL+pgvector, MinIO, Connections, Workbench, 4
> documents, ingestion pipeline (Succeeded run), `OGXServer` (Ready), Streamlit app
> (Running), and a logged MLflow experiment.
>
> **Use these documents instead as the current source of truth:**
> - `DEMO-CLICKBOOK.md` — click-by-click narration for every feature, including exactly
>   what's safe to re-create live vs. what to only show/use.
> - `DEMO-LIVE-CHECKLIST.md` — the pure click list for the stage, nothing else.
> - `DEMO-ARCHITECTURE.md` — how everything is wired, including two sandbox-specific
>   platform bugs found and worked around while building `OGXServer`, and the known MaaS
>   API-key inference bug.
>
> The content below is kept for historical reference (it documents the original
> "prep vs. live" planning approach) but many specifics (e.g. Streamlit build method,
> pipeline component code, OGXServer creation flow) were superseded during the actual
> build — see `DEMO-ARCHITECTURE.md` §5 and §6 for what actually shipped and why.

Companion to `DEMO-RUNBOOK.md`. Purpose: **you should never discover live, on stage, that you were expected to create a database, secret, pipeline backend, model, or OGX resource yourself.** Everything in the left column below must exist and be verified healthy *before* you start presenting. Everything in the right column is yours to click/type in front of the audience.

---

## Platform / GPU / Hardware (Admin Steps 1–3)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing — operator, DSC, GPU Operator, and both Hardware Profiles (`gpu-profile`, `default-profile`) already exist and are healthy. | Navigate and narrate: Installed Operators page, DataScienceCluster YAML, Node labels, GPU ClusterPolicy, Hardware profiles page. Optionally live-create a throwaway `demo-cpu-profile` to prove the wizard (delete after). |

## Model project (Admin Step 4)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing — `knowledge-advisor` and `shared-ai-services` must NOT exist yet so they can be created live. | Click **Create project**, type `Shared AI Services` / description, click **Create**. |

## LLM deployment (Admin Step 5)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing new — `llama-32-3b-instruct` already running in `my-first-model` (from earlier sandbox setup). | Open **Deploy model** wizard, fill every field while narrating, click **Cancel**, open the real running deployment instead. |

## Embedding model (Admin Step 6)

| Cursor prepares beforehand | I perform live |
|---|---|
| **Deploy `all-minilm-l6-v2` `InferenceService`** in `my-first-model`: `oci://quay.io/redhat-ai-services/modelcar-catalog:all-minilm-l6-v2`, runtime `vllm-cpu-x86-runtime-template`, hardware profile `default-profile` (2 CPU/4Gi, no GPU), marked as AI asset (`opendatahub.io/genai-asset: "true"`). Verify `Ready=True` and a test `/v1/embeddings` call returns a 384-dim vector before the demo. | Open **Deploy model** wizard, fill fields while narrating, click **Cancel**, open the real pre-created deployment instead. |

## Models-as-a-Service (Admin Steps 7–8)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing new — MaaS is already fully wired (`ExternalProvider`/`ExternalModel`/`MaaSModelRef`/`MaaSAuthPolicy`/`MaaSSubscription`, all `Ready`). **Verify once before the demo whether `Settings → Subscriptions` and `Settings → Authorization policies` are visible in the dashboard nav on this build** (there's a documented flag/schema mismatch — see Admin Step 7 caveat) so you know which path to use live. | Click through **Gen AI studio → AI asset endpoints**, **Settings → Subscriptions**, **Settings → Authorization policies** (or the terminal fallback if those pages aren't visible). |

## MLflow / OGX capability (Admin Steps 9–10)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing new — `mlflowoperator: Managed`, `ogx: Managed`, both `Ready`. | Navigate and narrate: MLflow empty experiments page, DSC YAML `ogx: Managed`, operator pods. |

---

## Data Scientist project + infra (DS Steps 2–5)

| Cursor prepares beforehand | I perform live |
|---|---|
| **Nothing for the project itself** — `knowledge-advisor` must not exist yet. | Click **Create project**, `Knowledge Advisor` / `knowledge-advisor` / description, click **Create**. |
| **PostgreSQL + pgvector**: `Deployment/pgvector-db` (image `pgvector/pgvector:pg16`), `Service/pgvector-db` (:5432), `PVC/pgvector-db-data` (5Gi, `gp3-csi`), `Secret/pgvector-db-credentials` (`POSTGRES_USER=ragadmin`, generated `POSTGRES_PASSWORD`, `POSTGRES_DB=ragdb`), `vector` extension enabled, second database `ogx` created for the future `OGXServer`. All in `knowledge-advisor`. Verify `\dx` shows `vector` extension and both DBs exist. | Point at the running pod (optional `psql` peek); create the actual `vector-database` **Connection** live (Step 4). |
| **MinIO object storage**: `Deployment/minio` (image `quay.io/minio/minio`), `Service/minio` (:9000/:9001), `Secret/minio-credentials`, two buckets pre-created: `documents` and `pipelines`. All in `knowledge-advisor`. | Create the `company-documents` **Connection** live (Step 4), pointing at the `documents` bucket. Reuse the same MinIO for the Pipelines object-storage connection (Step 10), pointed at the `pipelines` bucket. |
| **Workbench**: create + start `knowledge-advisor-workbench` (image `Jupyter \| Standard Data Science`, `default-profile`, both connections attached) ahead of time so it's `Running`, not cold-starting on stage. Pre-install `psycopg2-binary` into the image or confirm it's already present, so no live `pip install` is needed. | Open the **Create workbench** form and narrate every field (optionally Cancel and open the pre-created one instead of waiting ~60–90s for a live start). Open JupyterLab and run all notebook cells live. |

## MaaS / embedding calls (DS Steps 6–7)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing — confirm the MaaS endpoint and the embedding endpoint both respond with a quick test call before the demo starts. | Run both notebook cells live (MaaS chat call, embedding call). |

## Documents (DS Step 8)

| Cursor prepares beforehand | I perform live |
|---|---|
| Write and upload all four `.txt` files (`remote-work-policy.txt`, `expenses-policy.txt`, `security-policy.txt`, `onboarding.txt`) into both the MinIO `documents` bucket and `~/documents/` inside the workbench's persistent storage. | `!ls` / `!cat` one file live to show real content. |

## Ingestion + Pipeline (DS Steps 9–10)

| Cursor prepares beforehand | I perform live |
|---|---|
| Write the ingestion notebook cells (load/chunk/embed/store) — already drafted in `DEMO-RUNBOOK.md` Step 9, ready to paste. Compile the equivalent KFP pipeline (`document-ingestion-pipeline.yaml`) with four components matching that same logic; save it into the workbench's `~/pipelines/` folder or attach it as a downloadable file for the Import step. | Run the notebook cells live (Step 9). Configure the pipeline server live (fill the MinIO connection form), import the pre-compiled pipeline YAML live, start a run live, open the run graph live (Step 10). |

## OGXServer (DS Step 11)

| Cursor prepares beforehand | I perform live |
|---|---|
| Save a pre-verified-working copy of the `OGXServer` YAML to `yaml/ogx-server-knowledge-advisor.yaml` (exact contents in `DEMO-RUNBOOK.md` Step 11) as a paste-ready fallback, but do **not** apply it — creating it live is the whole point of this step and only takes ~20–30 seconds. | Open **Import YAML** in the OpenShift console, paste, click **Create**, wait ~20–30s, verify `Ready=True`. |

## Playground + RAG (DS Steps 12–13)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing beyond the `OGXServer` existing (Step 11) and both models being AI asset endpoints. | Create the playground live, ask the un-augmented question live, run the retrieval cell live, paste the augmented prompt live, read the grounded answer live. |

## Simple application (DS Step 14)

| Cursor prepares beforehand | I perform live |
|---|---|
| Write `app.py` (Streamlit): embed question → pgvector similarity search → augmented prompt → MaaS chat call → render answer. Build a container image, push to an accessible registry (or build via `oc new-build`/BuildConfig in-cluster), deploy as `Deployment` + `Service` + `Route` in `knowledge-advisor`. Verify the Route answers the sample question correctly before the demo. | Open the Route URL, type the question, click **Ask**, read the answer aloud. |

## MLflow logging (DS Step 15)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing — logging the first real run live is the point of this step. | Run the `mlflow.start_run(...)` cell live; open **Develop & train → Experiments (MLflow)** live and inspect the run. |

## MCP Catalog / Agents Catalog (DS Steps 16–17)

| Cursor prepares beforehand | I perform live |
|---|---|
| Nothing — both are enabled, browse-only by design. | Click through both catalogs live, point at the disabled Deploy button (MCP) and the Developer Preview banner (Agents). |

---

## Net-new Kubernetes objects this plan would create (nothing applied yet)

| # | Object | Namespace | Purpose |
|---|---|---|---|
| 1 | `InferenceService/all-minilm-l6-v2` (+ auto-created `ServingRuntime`) | `my-first-model` | CPU embedding model for RAG |
| 2 | `Project/knowledge-advisor` | — | Maya's application project (created **live**, not pre-staged) |
| 3 | `Deployment`+`Service`+`PVC`+`Secret` — `pgvector-db` | `knowledge-advisor` | PostgreSQL + pgvector (RAG storage + OGX metadata) |
| 4 | `Deployment`+`Service`+`Secret` — `minio` (+ 2 buckets) | `knowledge-advisor` | S3-compatible storage for documents + pipeline artifacts |
| 5 | Two `Connection` secrets — `vector-database`, `company-documents` | `knowledge-advisor` | Created **live** in the demo (Step 4), not pre-staged |
| 6 | `Notebook` (workbench) — `knowledge-advisor-workbench` | `knowledge-advisor` | Maya's JupyterLab environment |
| 7 | 4× `.txt` files in MinIO + workbench storage | `knowledge-advisor` | Demo documents |
| 8 | `DataSciencePipelinesApplication` (pipeline server) | `knowledge-advisor` | Created **live** in the demo (Step 10) |
| 9 | Pipeline definition — `document-ingestion-pipeline.yaml` | `knowledge-advisor` | Imported **live** in the demo (Step 10) |
| 10 | `OGXServer/knowledge-advisor-ogx` | `knowledge-advisor` | Created **live** in the demo (Step 11) |
| 11 | `Deployment`+`Service`+`Route` — `knowledge-advisor-app` (Streamlit) | `knowledge-advisor` | The "Knowledge Advisor" front-end app |
| 12 | (Optional, throwaway) `HardwareProfile/demo-cpu-profile` | `redhat-ods-applications` | Only if you choose to prove the Hardware Profile wizard live in Admin Step 3 |
| 13 | (Optional, throwaway) `Project/shared-ai-services` | — | Created live in Admin Step 4; safe to delete or keep afterward |

**Do NOT apply any of this until you approve it.** Nothing above has been created — this is the full delta between "sandbox as it is right now" and "sandbox ready for the richest possible demo."
