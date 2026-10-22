ROLE
You are helping me write the speaker script for a live technical demo of Red Hat OpenShift AI (RHOAI) 3.5. I will give you everything that was actually built and verified on a real cluster. Do not invent any UI label, click path, or feature that isn't in the context below. Answer in English (the entire demo — UI, code, documents — is in English).

DEMO NAME AND GOAL
"Knowledge Advisor" — an internal RAG (Retrieval-Augmented Generation) assistant for a fictional company, NovaTech, that answers employee questions about company policy (travel expenses, remote work, security) using only NovaTech's own documents, never hallucinating. It runs entirely on Red Hat OpenShift AI 3.5.

The demo has exactly TWO personas, and I need the script split cleanly into two parts:
1. ALEX — the Platform Administrator. His job: govern and expose AI models safely to data science teams (Models-as-a-Service), and provide platform-level observability.
2. MAYA — the Data Scientist / AI engineer. Her job: build, evaluate, and ship the actual RAG application on top of what Alex published.

For EVERY step, I need four things stated explicitly:
- Where to click (exact navigation path in the OpenShift / OpenShift AI console)
- What to show on screen
- What this corresponds to underneath, in OpenShift / OpenShift AI terms (which Kubernetes/RHOAI resource or concept it maps to, and why it matters)
- What to say out loud (a natural spoken line, not a bullet list — like real speaker notes)

Target total run time: 10-13 minutes. Audience: technical (platform engineers / architects), no marketing fluff, confident and concrete, mention real resource/CRD names when useful but keep it spoken, not a wall of YAML.

PRIMARY DEMO QUESTION (use exactly this, everywhere it's relevant):
"What is the hotel expense limit in Paris, and how long do employees have to submit expense reports?"
Expected answer must contain: 220 EUR and 15 calendar days. Expected top retrieved source: travel-policy.txt.

Also use a second, out-of-corpus question to prove the assistant doesn't hallucinate:
"What color is the NovaTech company logo?" → correct behavior: the app honestly says it could not find this information in the knowledge base, instead of making something up.

===========================================================
ARCHITECTURE (what actually exists on the cluster, verified live)
===========================================================

- OpenShift 4.20, RHOAI operator 3.5.0, single node with 1 NVIDIA L4 GPU (23GB), so only ONE GPU-backed model can run at a time.
- Models-as-a-Service (MaaS): a governed-access layer built on Red Hat Connectivity Link (Kuadrant + Authorino for auth + Limitador for rate-limiting) and the Gateway API. It exposes models through an external gateway URL with API-key auth, quota, and permission checks — completely separate from the raw internal Kubernetes service URL.
- Two models are published as shared MaaS assets, both deployed as the new `LLMInferenceService` resource kind (required for MaaS; the legacy `InferenceService` kind cannot be published to MaaS):
  - `llama-32-3b-instruct-maas` — Llama 3.2 3B Instruct, served by vLLM on the GPU.
  - `all-minilm-l6-v2-embeddings` — MiniLM embedding model, served on CPU only.
- Governance objects (namespace `models-as-a-service`):
  - `MaaSModelRef` — registers a deployed model with MaaS (created via the "Publish as MaaS" checkbox in the Deploy model wizard).
  - `MaaSSubscription` (name `data-scientist`) — grants a QUOTA: how many tokens/hour a group can consume, per model (currently 200,000/hour for Llama, 1,000,000/hour for embeddings — intentionally generous for demo rehearsal).
  - `MaaSAuthPolicy` (name `data-scientist-policy`) — grants PERMISSION: which group is allowed to reach which model endpoint through the gateway at all. Both objects are required: a subscription without a matching auth policy still gets `403 Forbidden`; an auth policy without a subscription lets requests through unbounded.
- OGX: OpenShift AI's native RAG orchestration engine (successor to LlamaStack in this build; the `llamastackoperator` DSC component must be `Removed` for OGX to reconcile). An `OGXServer` resource (`rag-ogx`, in project `rag-agentic-demo`) provides vector store management, document ingestion, embeddings, and a `/v1/responses` API with a `file_search` tool that grounds Llama's answers in retrieved documents.
- Vector store: PostgreSQL + pgvector extension, holding a vector store named `novatech-knowledge-base` with 3 ingested documents: `travel-policy.txt`, `remote-work-policy.txt`, `security-policy.txt`.
- Maya's Data Science Project: `rag-agentic-demo`, containing:
  - Connections (credentials to pgvector, and to S3/MinIO for the pipeline).
  - A Code Server workbench (`rag-workbench`) — VS Code in the browser, not Jupyter.
  - A Data Science Pipeline (`novatech-ogx-rag-pipeline-en`) that automates the whole ingestion + validation flow.
  - A standalone application deployment (`knowledge-advisor`), a Gradio chat UI, packaged as its own container image, deployed independently of the workbench, fronted by its own `Route` protected by an `oauth-proxy` sidecar (OpenShift OAuth/SSO login required — no anonymous access).
  - MLflow experiment tracking (`knowledge-advisor-rag-demo` experiment).
  - A RAG-quality evaluation script (`evaluate_rag.py`) — new, added this session, described in detail below.
- MaaS Observability Dashboard (Technology Preview) — new, added this session, described in detail below.

===========================================================
PART 1 — ALEX, PLATFORM ADMINISTRATOR: what he installed/configured, and what it maps to
===========================================================

Use this to write the "Alex" section of the script, roughly 4-5 minutes, ending with a bridge line to Maya.

A1. Platform prerequisites (already done, just verify/mention, don't reinstall):
- Installed: Red Hat Connectivity Link operators — `rhcl-operator` (Kuadrant), `authorino-operator`, `limitador-operator` — plus a Gateway API `Gateway` resource (`maas-default-gateway`, backed by a real external AWS load balancer).
- Maps to: this is the actual network/security plumbing MaaS is built on — Kuadrant is the policy engine, Authorino does authentication, Limitador does rate-limiting, all sitting in front of the Gateway API.
- Say: this is one-time, cluster-level plumbing that a platform admin installs before any model governance is possible.

A2. Enabling MaaS itself:
- Configured: `DataScienceCluster` (`default-dsc`) → `spec.components.aigateway.modelsAsAService.managementState: Managed`.
- Maps to: this single field turns on the entire MaaS control plane — deploys `maas-controller`, `maas-ui`, `maas-postgres`, and reconciles a `MaasTenantConfig` (the tenant object for the whole cluster).
- Say: one field, and the whole governance subsystem — gateway, metering database, tenant — comes online.

A3. Feature flag for GPU model publishing:
- Configured: `OdhDashboardConfig` (`odh-dashboard-config`) → `spec.dashboardConfig.vLLMDeploymentOnMaaS: true`.
- Maps to: unlocks, in the dashboard's "Deploy model" wizard, the "vLLM NVIDIA CUDA GPU LLMInferenceServiceConfig" deployment option plus the "Publish as MaaS" checkbox — without this flag only distributed/llm-d deployments are MaaS-eligible.
- Say: this is a Technology Preview feature flag — off by default, one YAML flip to try it — exactly how OpenShift AI ships Tech Preview capabilities safely.

A4. Publishing the two models:
- Did: Data Science Projects → Create project → Deployments → Deploy model, twice: once for Llama (GPU hardware profile, `LLMInferenceService`, "Publish as MaaS" checked), once for the MiniLM embedding model (CPU/default hardware profile). Custom vLLM runtime args for Llama: `--enable-auto-tool-choice --tool-call-parser=llama3_json --chat-template=...tool_chat_template_llama3.2_json.jinja` (needed for structured tool-calling used later by OGX's file_search).
- Maps to: each click creates an `LLMInferenceService` object; checking "Publish as MaaS" additionally creates a `MaaSModelRef` in the same step — no separate publish step exists once a model is already deployed without that checkbox (would require YAML).
- Say: one form, one click, and I get a running vLLM pod on the GPU AND its MaaS registration at the same time.

A5. Governance — quota and permission:
- Did: OpenShift AI dashboard → Settings → MaaS governance (a single page with two buttons: "Create subscription" and "Create authorization policy" — NOT two separate nav items, despite what some doc versions imply).
  - Create subscription: name `data-scientist`, add both models, set a token limit per model per hour.
  - Create authorization policy: name `data-scientist-policy`, same group, same models.
- Maps to: `MaaSSubscription` (quota) and `MaaSAuthPolicy` (permission) — two independent CRDs that must BOTH exist for a group to actually call a model through the gateway.
- Say: subscription = how much you can consume; authorization policy = whether you're allowed to consume it at all. A generous quota with no matching policy still gets you a 403 — I need both.

A6. MaaS Observability Dashboard (NEW — Technology Preview):
- Installed: Cluster Observability Operator + Red Hat build of OpenTelemetry + Tempo Operator, all three in a dedicated namespace `openshift-cluster-observability-operator` (required — RHOAI's built-in `NetworkPolicy` only allows the Perses dashboard-sync operator to reach the dashboard backend from pods in that exact namespace).
- Configured: `DSCInitialization` (`default-dsci`) → `spec.monitoring.metrics.storage` (size + retention) to provision the metrics stack; `OdhDashboardConfig` → `spec.dashboardConfig.observabilityDashboard: true`; `Kuadrant` CR → `spec.observability.enable: true` (creates a `PodMonitor` scraping Limitador's rate-limiting counters); `MaasTenantConfig` (`default-tenant`) → `spec.telemetry.enabled: true` with `captureOrganization`/`captureUser`/`captureGroup`/`captureModelUsage` (creates an Istio `Telemetry` + `TelemetryPolicy` so per-request metrics get labeled by subscription/user/model).
- Maps to: this whole chain feeds Prometheus with metrics like `authorized_calls_total` and `authorized_hits_total` (tokens), tagged with `subscription`, `model`, and `user` labels, which the dashboard then renders through Perses.
- Where to click to show it live: OpenShift AI dashboard → left nav "Observe & monitor" → "Dashboard" → tab "Usage" (the other two tabs are "Cluster" and "Models"). Filters available: Time period, User, Subscription, Model.
- Say: I can now see, per subscription and per model, exactly how many tokens have been consumed and whether anyone has hit a rate limit — without touching Prometheus directly. This is genuinely useful for a shared, multi-tenant cluster: I can see who's consuming what, and dial quotas up or down with real data instead of guessing.
- Small caveat worth mentioning if asked: this dashboard is Technology Preview in 3.5, and getting it working required installing three additional cluster-level operators — this is real infrastructure, not a checkbox.

A7. Bridge to Maya:
- Say: so MaaS gives me governed, observable access to raw models. But a real assistant needs more than a raw LLM — it needs to answer from our own company documents without hallucinating. That's what OGX, OpenShift AI's RAG capability, adds on top. Let's switch hats and look at this as Maya, the data scientist who builds on what I just published.

===========================================================
PART 2 — MAYA, DATA SCIENTIST: click-by-click walkthrough
===========================================================

Use this to write the "Maya" section, roughly 6-8 minutes.

M1. Project overview:
- Click: Data Science Projects → open `rag-agentic-demo`.
- Say: this project holds everything I need — my workbench, my OGX server, my vector database connection, my pipeline, and my deployed application.

M2. Discovering the shared models (contrast with Alex's world):
- Click: Gen AI Studio → AI asset endpoints → locate `llama-32-3b-instruct-maas` and `all-minilm-l6-v2-embeddings`, both carrying a "Model as a Service" badge → click View under Endpoints.
- Maps to: this badge means a `MaaSModelRef` exists; the Subscription dropdown here is gated by `MaaSSubscription`/`MaaSAuthPolicy` existing for my group.
- Say: I didn't create these models — Alex published them. I just discover them here, pick my subscription, and (if needed) generate an API key.

M3. Quick raw-LLM sanity check (no RAG, contrast point):
- Click: Gen AI Studio → Playground → select `llama-32-3b-instruct-maas` → ask a generic question ("Explain Kubernetes in one sentence").
- Say: this is direct model access through MaaS — no document lookup at all. Watch how this differs from the real assistant in a moment.

M4. Workbench + vector search:
- Click: Workbenches tab → `rag-workbench` → Open (Code Server IDE) → open a terminal → run:
  ```
  cd /opt/app-root/src/ogx-rag-demo
  .venv/bin/python -c "
  import rag_service as rag
  client, store = rag.bootstrap()
  for hit in rag.search(client, store, rag.DEFAULT_QUESTION):
      print(hit.filename, hit.score)
  "
  ```
- Show: `travel-policy.txt` printed first, highest score.
- Maps to: `OGXServer/rag-ogx` doing a similarity search against PostgreSQL/pgvector — pure retrieval, before the LLM is even called.
- Say: OGX already knows which document is relevant, purely from the vector similarity — before Llama ever sees the question.

M5. Full RAG answer (CLI):
- Click: same terminal, run `bash run-demo.sh`.
- Show: exit code 0, printed answer containing "220 EUR" and "15 calendar days".
- Maps to: the script calls OGX's `/v1/responses` API with the `file_search` tool, which retrieves the document AND invokes Llama grounded in it, in one call.
- Say: this is the actual RAG chain — retrieval and generation combined — and the answer is grounded in `travel-policy.txt`, not invented by the model.

M6. Automated pipeline:
- Click: Pipelines tab → `novatech-ogx-rag-pipeline-en` → latest run → show the 6-task graph: prepare-corpus, check-ogx, get-or-create-vector-store, ingest-documents, validate-search, generate-rag-answer, all green. Click `generate-rag-answer` → Logs.
- Say: everything I just did by hand is also a repeatable Kubeflow pipeline. It's idempotent — re-running it never duplicates documents — and if either the retrieval check or the generated answer fails validation, the whole pipeline fails loudly, so regressions get caught automatically.

M7. From prototype to standalone deployment:
- Click (prototype): open the app inside the workbench via Code Server's authenticated proxy.
- Click (production): open the standalone URL (`https://knowledge-advisor-...`) in a new tab — if not logged in, browser redirects to OpenShift OAuth/SSO login first.
- Show: same UI, ask the primary question → correct grounded answer with source + score + duration; then ask the out-of-corpus logo-color question → app honestly says it couldn't find the information.
- Maps to: a dedicated `Deployment` + `Service` + `Route`, independent of the workbench pod, protected by an `oauth-proxy` sidecar doing a `SubjectAccessReview` against OpenShift's own SSO — no anonymous access, ever.
- Say: this closes the loop — I prototype in my workbench, and the platform runs the validated result as its own independent, authenticated service that survives even if my workbench is deleted. And critically, when I ask something outside our documents, it doesn't make something up.

M8. MLflow:
- Click: open the MLflow UI → experiment `knowledge-advisor-rag-demo`.
- Show: the "Knowledge Advisor Demo" run — question, models used, retrieved document, score, duration.
- Say: every interaction can be logged for observability — which question, which models answered, which document was retrieved, how confident the search was, how long it took. No secrets, only demo-relevant metadata.

M9. RAG quality evaluation (NEW — added this session, this is the closing technical highlight):
- Context to explain: OpenShift AI's own documentation chapter "Evaluating RAG systems with OGX" names three pluggable evaluation providers: Ragas, AutoRAG, and TrustyAI. We specifically tried wiring up the real Ragas Python library (not a mock), pointing it at our existing OGX/Llama endpoint.
- What happened (be honest and specific, this is a genuinely interesting finding, not a failure to hide): Ragas connected to our model without any issue — the HTTP calls succeeded. But Ragas's scoring mechanism depends on a library called `instructor` asking the model to fill a strict JSON schema (structured output). Our Llama-3.2 3B model, on this exact vLLM configuration, could not reliably do that — it kept echoing the JSON schema back instead of filling it in, across every retry. This is a real capability limit of a small 3B model doing strict structured-output extraction, not a bug in our setup; fixing it would mean enabling vLLM's guided-decoding backend, a bigger infrastructure change we chose not to make for this evaluation.
- What we ran instead, successfully, live on the cluster: a lightweight custom evaluation script (`evaluate_rag.py`) implementing the same metric families the OGX doc describes — context precision, answer correctness, and LLM-as-judge faithfulness — but using a trivial one-line "SCORE: <number>" text format instead of complex JSON, which this same 3B model handles reliably (using the exact same OGX/Llama endpoint, no extra infrastructure).
- Click: in the workbench terminal, run `.venv/bin/python evaluate_rag.py`.
- Show: 6 test questions (including the same logo-color hallucination trap), 6/6 passed, average context precision 1.00, average answer correctness 1.00, average LLM-judge faithfulness 0.83, results logged to MLflow as a new run "RAG Evaluation Suite".
- Say: we didn't just build a demo, we validated it objectively, with a real evaluation harness, against a real (if small) production model — and we're transparent that "just use Ragas" isn't always a drop-in answer when your model is small; you have to test the actual chain end-to-end, on the actual model, which is exactly what we did here.

M10. Closing line (tie both personas together):
- Say: end to end — Alex governs and observes model access through MaaS; I build the actual retrieval-augmented assistant on top of it using OGX, pgvector, a repeatable pipeline, and a simple authenticated web app — and I can prove, with real evaluation numbers, that it answers correctly and doesn't make things up. All inside OpenShift AI, all backed by real infrastructure, nothing faked.

===========================================================
WHAT I NEED FROM YOU
===========================================================
Turn all of the above into a polished, ready-to-read speaker script, structured exactly as:
1. A short 20-30 second opening hook (what is Knowledge Advisor, why it matters).
2. "PART 1 — Alex, Platform Administrator" — walk through A1 to A7 as numbered steps, each with: Where to click / What to show / What it maps to in OpenShift/OpenShift AI / What to say (as a natural spoken paragraph, not bullets).
3. "PART 2 — Maya, Data Scientist" — walk through M1 to M10 the same way.
4. A short closing line.
Keep the total reading time around 10-13 minutes. Do not add any click path, menu label, or feature not present in the context above — if something is ambiguous, say so explicitly rather than inventing it.
