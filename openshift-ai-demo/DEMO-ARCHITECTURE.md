# DEMO ARCHITECTURE — Red Hat OpenShift AI 3.5 "Knowledge Advisor"

This is the architectural reference for the demo — read this to understand
*why* things are wired the way they are. For click-by-click presentation
instructions, see `DEMO-CLICKBOOK.md`. For the pure click list, see
`DEMO-LIVE-CHECKLIST.md`.

## 1. High-level component diagram

```
                              ┌─────────────────────────────────────────┐
                              │        OpenShift AI Dashboard            │
                              │  (Data Science Projects, Gen AI Studio,  │
                              │   Model Catalog, MCP/Agents Catalog)     │
                              └───────────────┬───────────────────────────┘
                                              │
                 ┌────────────────────────────┼────────────────────────────┐
                 │                            │                            │
        ┌────────▼────────┐        ┌──────────▼──────────┐      ┌──────────▼──────────┐
        │  my-first-model  │        │  knowledge-advisor    │      │ models-as-a-service  │
        │  (shared models) │        │  (Maya's project)     │      │  (MaaS governance)   │
        │                  │        │                        │      │                      │
        │ InferenceService │◄───────┤ Workbench (JupyterLab) │      │ ExternalModel         │
        │ llama-32-3b-     │  vLLM  │  - 4 notebooks         │      │ MaaSModelRef          │
        │  instruct (GPU)  │  calls │  - 4 company docs      │      │ MaaSAuthPolicy        │
        │                  │        │                        │      │ MaaSSubscription      │
        │ InferenceService │◄───────┤ Connections:            │      │  (100k tok/hr)        │
        │ all-minilm-l6-v2 │  vLLM  │  - vector-database      │      └──────────┬───────────┘
        │  (CPU)           │  calls │  - company-documents    │                 │
        └──────────────────┘        │  - pipeline-artifacts   │        AI Gateway (Envoy +
                 ▲                  │                        │         Kuadrant: Authorino +
                 │ vLLM calls       │ PostgreSQL 14 + pgvector│         Limitador)
                 │                  │  (pgvector-db, table    │                 │
        ┌────────┴────────┐        │   document_chunks)      │        Public HTTPS endpoint
        │  OGXServer       │        │                        │      maas.apps...opentlc.com
        │ knowledge-       │◄───────┤ MinIO (S3-compatible)   │
        │  advisor-ogx     │ pgvector│  buckets: documents,   │
        │ (Ready, 1 pod)   │ queries │           pipelines    │
        │                  │        │                        │
        │ providers:       │        │ DataSciencePipelines-   │
        │ - vLLM (LLM)     │        │  Application (dspa)     │
        │ - vLLM (embed)   │        │  - MariaDB (KFP meta)   │
        │ - pgvector       │        │  - ingestion pipeline    │
        └──────────────────┘        │    (Load→Chunk→Embed→   │
                 ▲                  │     Store), Succeeded   │
                 │ /v1/chat/        │                        │
                 │  completions     │ Streamlit app            │
                 │ /v1/embeddings   │  (Deployment+Route)      │
                 │ /v1/vector_stores│  embed→retrieve→generate │
        ┌────────┴────────┐        │                        │
        │ Gen AI Studio /  │        │ MLflow experiment        │
        │  Playground      │        │  knowledge-advisor-rag   │
        └──────────────────┘        └────────────────────────┘
```

## 2. The two "planes" of this demo

**Platform plane (Alex, cluster admin):**
- `DataScienceCluster` toggles capabilities on/off cluster-wide: `kserve`, `workbenches`,
  `datasciencepipelines`, `dashboard`, `modelregistry`, `ogx`, `modelsAsAService`, `trustyai`.
- `HardwareProfile`s abstract "what compute shapes exist" (`default-profile` = CPU-only,
  `gpu-profile` = 1× NVIDIA L4) away from "who can request what."
- Two `InferenceService`s are deployed once and shared by every Data Science Project on the
  cluster: `llama-32-3b-instruct` (generation) and `all-minilm-l6-v2` (embedding). Both are
  served by vLLM through KServe, one GPU-scheduled, one CPU-scheduled.
- MaaS governance (`ExternalModel`, `MaaSModelRef`, `MaaSAuthPolicy`, `MaaSSubscription`)
  wraps the shared Llama deployment with an externally-reachable, quota-and-auth-enforced
  API product, via an Envoy Gateway fronted by Kuadrant (Authorino for auth, Limitador for
  rate limiting).

**Project plane (Maya, data scientist):**
- Everything lives inside the `knowledge-advisor` namespace/Data Science Project:
  a Workbench, three Connections, a PostgreSQL+pgvector instance, a MinIO instance, a
  Data Science Pipelines server, an `OGXServer`, and a Streamlit application.
- Maya never deploys her own LLM or embedding model — she *consumes* the two shared
  ones via internal ClusterIP Services, and (optionally) via the MaaS gateway.

## 3. Data flow — ingestion (offline / pipeline)

```
MinIO (documents bucket, raw/*.md)
   │  boto3.get_object
   ▼
load_documents  (KFP component)  → Dataset artifact (JSON list of {source, text})
   │
   ▼
chunk_documents (KFP component)  → header-aware markdown chunking (## sections,
   │                                packed to ≤600 chars, prefixed with doc title
   │                                + heading for retrieval context)
   ▼
embed_chunks    (KFP component)  → batched POST to all-minilm-l6-v2 /v1/embeddings
   │                                (384-dim vectors)
   ▼
store_vectors   (KFP component)  → psycopg: CREATE EXTENSION vector; TRUNCATE +
                                    INSERT into document_chunks; CREATE INDEX
                                    ... USING hnsw (embedding vector_cosine_ops)
```

Inter-component data (steps 1→2→3→4) is passed as **KFP Dataset artifacts** (files on the
run's backing volume), not inline pipeline parameters — the embeddings payload for all 26
chunks is too large to pass as a CLI argument without hitting the container runtime's argv
size limit (this was an actual bug encountered and fixed during environment build-out; see
the pipeline source file `notebooks/build_ingestion_pipeline.py` for the comment).

## 4. Data flow — RAG query (online / interactive)

```
User question ("Which days can employees work remotely?")
   │
   ▼
POST all-minilm-l6-v2-predictor.../v1/embeddings   → 384-dim query vector
   │
   ▼
SELECT source, content FROM document_chunks
  ORDER BY embedding <=> '<query_vector>'::vector   (pgvector cosine distance,
  LIMIT 3                                             HNSW index)
   │
   ▼
Prompt = "Answer using ONLY this context: <top-3 chunks>. Question: <question>"
   │
   ▼
POST llama-32-3b-instruct-predictor.../v1/chat/completions
   │
   ▼
Answer: "...employees can work remotely on Monday and Friday..."
```

This exact 3-step flow is implemented identically in three places, all validated:
1. `notebooks/03_rag_end_to_end.py` (Workbench notebook)
2. `streamlit-app/app.py` (the Knowledge Advisor web app)
3. `PREDEMO-HEALTHCHECK.sh` §11 (automated regression check)

## 5. OGX (Gen AI orchestration layer)

`OGXServer/knowledge-advisor-ogx` is Red Hat's rebrand of Llama Stack — a single
OpenAI-compatible server that fronts multiple providers:

- **Inference providers** (`remote::vllm` × 2): `llama-32-3b-instruct` and `all-minilm-l6-v2`,
  each pointing at the shared predictors' internal Service + `/v1` path.
- **Vector I/O provider** (`remote::pgvector` × 1): the same `pgvector-db` Postgres instance
  Maya's pipeline writes into — proven via a live create→search→delete OpenAI Vector Stores
  API round-trip during environment validation.
- **Storage backends**: sqlite for OGX's own operational metadata (KV + SQL stores), fully
  independent of the RAG data in `document_chunks`.

This gives Gen AI Studio's Playground and any MCP/agent tooling a single, uniform API surface
regardless of how many underlying model servers or vector stores exist behind it.

### Known sandbox-specific platform gaps encountered building OGXServer (documented for transparency)

1. **Registry-auth gap in the OGX operator's own OCI-label resolution.** When no
   `baseConfig`/`overrideConfig` is supplied, the operator tries to derive a base config by
   fetching OCI image labels directly from `registry.redhat.io` using its own HTTP client —
   which is unauthenticated in this build, even though the *node's* kubelet pulls the same
   image successfully using the cluster's global pull secret. **Workaround used:** supply a
   full `overrideConfig` ConfigMap, bypassing OCI-label resolution entirely.
2. **Missing `persistence` field in the declarative pgvector provider mapping.** The operator's
   `spec.providers.vectorIo.remote.pgvector` → generated-config mapping omits the
   `persistence` (`KVStoreReference`) field the `remote::pgvector` provider implementation
   requires at startup, causing a crash (`AttributeError: 'NoneType' object has no attribute
   'backend'`). **Workaround used:** the same `overrideConfig` includes
   `persistence: {backend: kv_default, namespace: vector_io::pgvector}` explicitly.
3. **vLLM provider `base_url` must include `/v1`.** Declaratively-generated configs from
   `spec.providers.inference.remote.vllm` set `base_url` to the bare predictor host:port
   without the `/v1` suffix the OpenAI SDK expects — the fix is included directly in the
   `overrideConfig`.

None of these affect the *demo*: the resulting `OGXServer` is fully `Ready` and was validated
end-to-end (inference, embeddings, and a live vector-store round trip against pgvector).

## 6. Known platform bug — MaaS governed inference (documented, not a demo blocker)

Calling the *governed* MaaS chat-completions endpoint with an API key currently returns
`HTTP 500 — inference error: Internal - authType 'apikey' credentials not found`, after
routing, authentication (Authorino), and quota (Limitador) checks all pass. Root-caused to
the `ExternalProvider`'s handling of the backend `secretRef` credentials for API-key auth
type. The demo's actual RAG generation calls use the direct in-cluster predictor endpoint;
the MaaS portion of the demo is scoped to discovery, subscription/quota, and API-key
creation — all of which work correctly.

## 7. Resource inventory (namespaces)

| Namespace | Key resources |
|---|---|
| `redhat-ods-applications` | RHOAI operator, DSC, dashboard, Hardware Profiles, OGX/ogx-k8s operators |
| `my-first-model` | `llama-32-3b-instruct`, `all-minilm-l6-v2` InferenceServices |
| `models-as-a-service` | `ExternalModel`, `MaaSModelRef`, `MaaSAuthPolicy`, `MaaSSubscription` |
| `openshift-ingress` | `maas-default-gateway`, `openshift-ai-inference`, `data-science-gateway` Gateways |
| `knowledge-advisor` | Workbench, Connections, pgvector-db, MinIO, DSPA, pipeline, OGXServer, Streamlit app, MLflow experiment data |

## 8. Documents used for RAG (all four, chunked and embedded)

| File | Topic | Chunks |
|---|---|---|
| `hr-remote-work-policy.md` | Remote work eligibility (Monday/Friday) | 6 |
| `it-security-policy.md` | IT security policy | 7 |
| `employee-benefits-guide.md` | Employee benefits | 7 |
| `onboarding-guide.md` | New hire onboarding | 6 |

Total: **26 chunks**, header-aware chunked (split on markdown `##` sections, packed to
≤600 chars, each chunk prefixed with `<Doc Title> — <Section Heading>` for retrieval context).
