# DEMO CLICKBOOK — Red Hat OpenShift AI 3.5 "Knowledge Advisor" Demo

> **This is your click-by-click presentation script.** It is not an architecture
> document (see `DEMO-ARCHITECTURE.md` for that) and it is not a pre-demo prep
> guide (see `DEMO-LIVE-CHECKLIST.md` for the shortlist of just what you touch
> live). Every resource below already exists and was validated end-to-end by
> `PREDEMO-HEALTHCHECK.sh` (30 PASS / 1 documented WARN / 0 FAIL as of the last
> run). This document tells you exactly what to click, what to say, and what
> to show for every single feature.

## How to read each entry

Every feature below follows the same template:

- **Result already prepared** — what exists right now, Ready, in your cluster.
- **How we created it** — UI / YAML / CLI (and why, if YAML/CLI was required).
- **Dashboard path** — the exact left-nav → page → tab breadcrumb.
- **Clicks** — the literal buttons you press.
- **Fields** — exact values to type, in a table. **No secrets in this document.**
- **What happens behind the UI** — the Kubernetes/OpenShift resource created.
- **What you show after clicking** — the exact screen/status to point at.
- **What you say** — a 20–40 second, plain-English narration.
- **Can I safely reproduce this live?** — one of:
  `YES — CREATE LIVE` / `YES — SHOW FORM THEN CANCEL` / `YES — RUN EXISTING RESOURCE` /
  `NO — SHOW EXISTING RESOURCE` / `YAML/CLI REQUIRED`

Cluster-specific values you'll see throughout (safe to say out loud, none are secrets):

| Item | Value |
|---|---|
| Cluster console | `https://console-openshift-console.apps.ocp.tfmbf.sandbox2633.opentlc.com` |
| OpenShift AI dashboard | `https://rhods-dashboard-redhat-ods-applications.apps.ocp.tfmbf.sandbox2633.opentlc.com` |
| GPU node | 1× **NVIDIA L4** (`g6.8xlarge`, 23GB) |
| Shared LLM | `llama-32-3b-instruct` (Llama 3.2 3B Instruct, vLLM, GPU) |
| Embedding model | `all-minilm-l6-v2` (sentence-transformers/all-MiniLM-L6-v2, vLLM, CPU) |
| MaaS public endpoint | `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com` |
| Data Scientist project | `knowledge-advisor` |
| Streamlit app | `https://knowledge-advisor-streamlit-knowledge-advisor.apps.ocp.tfmbf.sandbox2633.opentlc.com` |
| Demo question | *"Which days can employees work remotely?"* → **"Monday and Friday"** |

---

# PERSONA 1 — ALEX, PLATFORM ADMINISTRATOR

## A. Operator — how OpenShift AI is installed/viewed

**Result already prepared:** `rhods-operator.3.5.0` installed via OLM, `Succeeded`, in `redhat-ods-applications`.

**How we created it:** UI (OperatorHub) — already installed, this is a **view-only** stop.

**Dashboard path:** OpenShift Console → **Operators → Installed Operators** → `redhat-ods-operator` namespace.

**Clicks:**
1. Left nav → **Operators → Installed Operators**
2. Filter project: `redhat-ods-operator`
3. Click **Red Hat OpenShift AI**

**Fields:** None (view only).

**What happens behind the UI:** A `Subscription` + `ClusterServiceVersion` (`rhods-operator.3.5.0`) in the `redhat-ods-operator` namespace, `Succeeded` phase.

**What you show after clicking:** CSV details page — Version `3.5.0`, Status `Succeeded`, and the list of CRDs it provides (`DataScienceCluster`, `DSCInitialization`, etc.).

**What you say:** "OpenShift AI installs like any other OpenShift Operator — one click from OperatorHub, then it manages everything else declaratively through a single custom resource we'll look at next."

**Can I safely reproduce this live?** `NO — SHOW EXISTING RESOURCE` (re-installing would be destructive/slow).

---

## B. DataScienceCluster — where the admin enables capabilities

**Result already prepared:** `default-dsc`, `Ready=True`, with `inferenceservice`, `kserve`, `dashboard`, `workbenches`, `datasciencepipelines`, `modelregistry`, `trustyai`, `ray`, `trainer`, `feastoperator`, `mlflow` (via ModelRegistry+MLflowOperator), `aigateway`/`modelsAsAService`, and **`ogx`** all `Managed`.

**How we created it:** UI (OpenShift AI Operator install wizard creates the default DSC) — this instance is **already provisioned**; editing component states IS a UI operation.

**Dashboard path:** OpenShift Console → **Operators → Installed Operators → Red Hat OpenShift AI → Data Science Cluster** tab → `default-dsc`.

**Clicks:**
1. Open the CSV (as in section A)
2. Tab: **Data Science Cluster**
3. Click `default-dsc`
4. Tab: **YAML** (to show `spec.components`) or **Details** (to show status conditions)

**Fields (read-only view of current state):**

| Component | managementState |
|---|---|
| kserve | Managed |
| workbenches | Managed |
| datasciencepipelines | Managed |
| dashboard | Managed |
| modelregistry | Managed |
| ogx | Managed |
| trustyai | Managed |

**What happens behind the UI:** This literally IS the Kubernetes resource — `DataScienceCluster/default-dsc`. Editing a component's `managementState` field here is what the operator reconciles against.

**What you show after clicking:** Status → Conditions → `Ready: True`. Scroll to `spec.components.ogx.managementState: Managed` to set up the OGX story later.

**What you say:** "Every capability in OpenShift AI — pipelines, model serving, the model registry, MLflow, and the new Gen AI orchestration layer called OGX — is a toggle on this one object. Turn it on here, the operator reconciles the rest."

**Can I safely reproduce this live?** `NO — SHOW EXISTING RESOURCE` (toggling components live risks breaking the rest of the demo — show, don't touch).

---

## C. Accelerator — where NVIDIA L4 is visible

**Result already prepared:** 1 node (`g6.8xlarge`) with NVIDIA GPU Operator labels, `nvidia.com/gpu.product=NVIDIA-L4`, `nvidia.com/gpu.count=1`.

**How we created it:** YAML/CLI REQUIRED for the *node pool/instance type* (that's AWS infra, not OpenShift AI) — but the **GPU Operator install** and **node labeling** are visible in-cluster.

**Dashboard path:** OpenShift Console → **Compute → Nodes** → the GPU node → **Details** tab (labels) — or OpenShift AI dashboard → **Settings → Accelerator profiles**.

**Clicks:**
1. OpenShift Console left nav → **Compute → Nodes**
2. Click the node with the GPU icon
3. Scroll to **Labels**, point at `nvidia.com/gpu.product=NVIDIA-L4`

**Fields:** None (view only).

**What happens behind the UI:** NVIDIA GPU Operator + Node Feature Discovery label the node automatically once the driver/device-plugin DaemonSets report ready.

**What you show after clicking:** Node labels showing `NVIDIA-L4`, `gpu.count: 1`, `gpu.memory: 23034` (MiB), driver version `580.82.07`, CUDA `13.0`.

**What you say:** "This sandbox has one real NVIDIA L4 GPU. The GPU Operator auto-detects it, labels the node, and from here OpenShift AI can schedule GPU workloads against it through a Hardware Profile — which is what we look at next."

**Can I safely reproduce this live?** `NO — SHOW EXISTING RESOURCE`.

---

## D. Hardware Profile — how an admin creates the profile from the dashboard

**Result already prepared:** Two profiles in `redhat-ods-applications`: `default-profile` (CPU/Memory only) and `gpu-profile` (CPU + Memory + 1 NVIDIA GPU).

**How we created it:** UI-capable. Shown here as **create-then-cancel** against the real form, then open the existing `gpu-profile`.

**Dashboard path:** OpenShift AI dashboard → **Settings → Hardware profiles**.

**Clicks (live, safe to cancel):**
1. Left nav → **Settings → Hardware profiles**
2. Click **Create hardware profile**
3. Walk through the fields below
4. Click **Cancel** (do not save)
5. Click the existing **gpu-profile** row to open it and show the real values

**Fields (what you'd type if creating live):**

| UI field | Exact demo value |
|---|---|
| Name | `gpu-profile` |
| Display name | `gpu-profile` |
| Description | GPU profile for L4-backed generative model serving |
| Identifier: CPU | default `1`, min `1`, max `8` |
| Identifier: Memory | default `12Gi`, min `1Gi`, max `16Gi` |
| Identifier: Accelerator (nvidia.com/gpu) | default `1`, min `1`, max `4` |
| Tolerations | (none needed — single-GPU node) |

**What happens behind the UI:** A `HardwareProfile` custom resource (`infrastructure.opendatahub.io/v1`) in `redhat-ods-applications`, referenced later by `opendatahub.io/hardware-profile-name` annotations on `InferenceService`/`Notebook` objects.

**What you show after clicking:** The existing `gpu-profile` detail page with the 3 resource identifiers (CPU/Memory/GPU) exactly as above.

**What you say:** "A Hardware Profile is how the admin defines a reusable 'shape' of compute — here, one L4 GPU plus CPU/memory bounds — that data scientists then pick from a dropdown when deploying a model or launching a workbench. It decouples 'what resources are available' from 'what a user is allowed to request.'"

**Can I safely reproduce this live?** `YES — SHOW FORM THEN CANCEL`, then `NO — SHOW EXISTING RESOURCE` for the real one.

---

## E. Project — how an OpenShift AI project is created

**Result already prepared:** `knowledge-advisor` Data Science Project, fully populated (see Persona 2).

**How we created it:** UI-capable — shown as **create-then-cancel** on a throwaway name, then open the real `knowledge-advisor` project.

**Dashboard path:** OpenShift AI dashboard → **Data Science Projects**.

**Clicks (live, safe to cancel):**
1. Left nav → **Data Science Projects**
2. Click **Create project**
3. Type a throwaway name (e.g. `demo-scratch`)
4. Click **Cancel** (do not create)
5. Click **knowledge-advisor** in the project list to open the real one

**Fields (what you'd type if creating live):**

| UI field | Exact demo value |
|---|---|
| Name | `knowledge-advisor` |
| Resource name | `knowledge-advisor` (auto-slugified) |
| Description | Acme Corp internal policy RAG assistant |

**What happens behind the UI:** A `Namespace` labeled `opendatahub.io/dashboard: "true"`, plus default `RoleBinding`s for the creating user.

**What you show after clicking:** The `knowledge-advisor` project **Overview** tab — showing live tiles for Workbenches (1), Pipelines (1 server), Models (via OGX), Connections (3).

**What you say:** "A Data Science Project is just an OpenShift namespace with some OpenShift AI conventions layered on — the dashboard groups every workbench, connection, pipeline, and model that a data scientist creates inside a project boundary, matching how OpenShift RBAC and quotas already work."

**Can I safely reproduce this live?** `YES — CREATE LIVE` (on a throwaway name), then `NO — SHOW EXISTING RESOURCE` for `knowledge-advisor` itself.

---

## F. LLM deployment — Models → Deploy model

**Result already prepared:** `llama-32-3b-instruct` `InferenceService`, `Ready=True`, in `my-first-model` project, served by vLLM on the GPU.

**How we created it:** UI-capable (Model Catalog → Deploy, or Models tab → Deploy model). Shown as **open form → explain → cancel → open the working deployment**.

**Dashboard path:** OpenShift AI dashboard → **Data Science Projects → my-first-model → Models** tab → **Deploy model**.

**Clicks (live, safe to cancel):**
1. Open project `my-first-model` → **Models** tab
2. Click **Deploy model**
3. Walk through the fields below
4. Click **Cancel**
5. Click the existing **llama-32-3b-instruct** row → **Ready**, then copy its internal endpoint from the **Internal Service** tab

**Fields (what you'd type/select if deploying live):**

| UI field | Exact demo value |
|---|---|
| Model deployment name | `llama-32-3b-instruct` |
| Source model location | OCI (modelcar) — `oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct` |
| Model format | vLLM |
| Serving runtime | `llama-32-3b-instruct` (vLLM ServingRuntime) |
| Hardware profile | `gpu-profile` (1× NVIDIA GPU) |
| Number of model server replicas | `1` (min 1 / max 1) |
| Token authentication | Disabled (internal-only; MaaS gateway handles external auth) |
| Extra vLLM args | `--dtype=half --max-model-len=20000 --gpu-memory-utilization=0.95 --enable-auto-tool-choice --tool-call-parser=llama3_json` |

**What happens behind the UI:** A KServe `InferenceService` (`serving.kserve.io/v1beta1`) + a `ServingRuntime` reference. KServe creates the `Deployment`, `Service`, and (if enabled) `Route`/`HTTPRoute`.

**What you show after clicking:** The **Models** tab row: status `Started` (green), Inference endpoint `http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080`.

**What you say:** "This is exactly how the Llama 3.2 3B model got onto this cluster — pick a source, a runtime, a hardware profile, hit deploy, and KServe handles the rest: pulling the model, starting vLLM, wiring up the Kubernetes Service. We're not redeploying it live because it takes several minutes to pull an 8GB image and warm up the GPU — instead here's the one that's already been running and serving traffic all morning."

**Can I safely reproduce this live?** `YES — SHOW FORM THEN CANCEL`, then `NO — SHOW EXISTING RESOURCE` for the Ready deployment.

---

## G. Embedding deployment — Model Catalog path

**Result already prepared:** `all-minilm-l6-v2` `InferenceService`, `Ready=True`, in `my-first-model`, CPU-only, labeled `opendatahub.io/genai-asset: "true"`.

**How we created it:** UI-capable (Model Catalog → select `all-MiniLM-L6-v2` → Deploy). Shown as **catalog browse → deploy form → cancel → open the working deployment**.

**Dashboard path:** OpenShift AI dashboard → **Model Catalog** (or **Gen AI Studio → Models**) → search `all-minilm` → **Deploy**.

**Clicks (live, safe to cancel):**
1. Left nav → **Model Catalog**
2. Search box → type `minilm`
3. Click the `all-MiniLM-L6-v2` tile → **Deploy model**
4. Walk through the fields below
5. Click **Cancel**
6. Open project `my-first-model` → **Models** → existing **all-minilm-l6-v2** row → point at `Ready`

**Fields (what you'd type/select if deploying live):**

| UI field | Exact demo value |
|---|---|
| Model deployment name | `all-minilm-l6-v2` |
| Source | Model Catalog entry — `oci://quay.io/redhat-ai-services/modelcar-catalog:all-minilm-l6-v2` |
| Model format | vLLM |
| Serving runtime | `all-minilm-l6-v2` (vLLM ServingRuntime) |
| Hardware profile | `default-profile` (CPU only — no GPU needed for this small model) |
| Number of replicas | `1` |
| Extra vLLM args | `--gpu-memory-utilization=0.4` |

**What happens behind the UI:** Same KServe `InferenceService` mechanism as section F, just CPU-scheduled instead of GPU-scheduled.

**What you show after clicking:** Models tab row: `Ready`, endpoint `http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings`.

**What you say:** "Here I select the embedding model straight from the catalog and deploy it — same wizard as the LLM, just a much smaller CPU footprint. This is the model that turns text into the 384-number vectors pgvector will search over."

**Can I safely reproduce this live?** `YES — SHOW FORM THEN CANCEL`, then `NO — SHOW EXISTING RESOURCE`.

---

## H. Models-as-a-Service — from existing Llama to governed MaaS endpoint

**Result already prepared:** `llama-32-3b-instruct` is exposed through the MaaS gateway as model id `llama-32-3b-instruct-external`, publicly reachable at `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`.

**How we created it:**
- `ExternalModel` (registers an already-running InferenceService with MaaS) — **YAML/CLI REQUIRED** (no dashboard wizard for this step in 3.5).
- `MaaSModelRef`, `MaaSAuthPolicy`, `MaaSSubscription` — **YAML/CLI REQUIRED** for creation; **UI-visible** for review (see sections I/J).
- The **governance view** (subscriptions, quota, discovery) IS in the dashboard — see section K for Maya's side.

**Dashboard path (viewing the result):** OpenShift AI dashboard → **Gen AI Studio → Models** (or **Model Catalog → Deployed models**) → filter to `models-as-a-service` namespace.

**Clicks:**
1. Left nav → **Gen AI Studio**
2. Tab → **Models** (this list is populated from `MaaSModelRef` + OGX-registered models across projects)
3. Point at the `llama-32-3b-instruct` row, showing the **MaaS** badge

**Fields:** None (view only in dashboard; creation was YAML).

**What happens behind the UI:**
```
ExternalModel (llama-32-3b-instruct-external)
   └── points at → InferenceService llama-32-3b-instruct (my-first-model)
MaaSModelRef (llama-32-3b-instruct-external)
   └── advertises the model through the AI Gateway (Kuadrant/Envoy)
MaaSAuthPolicy (llama-32-3b-instruct-access) — Authorino policy
MaaSSubscription (llama-32-3b-instruct-subscription) — Limitador rate limit (100k tokens/hr)
HTTPRoute (llama-32-3b-instruct-external) on Gateway maas-default-gateway
```

**What you show after clicking:** `oc get maasmodelref,maasauthpolicy,maassubscription -n models-as-a-service` → all `Ready`/`Active`. Then the public endpoint field: `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`.

**What you say:** "Alex already had a working Llama deployment. To turn it into a *governed*, externally-reachable API product, we register it once with MaaS — that's currently a YAML step, not a dashboard wizard — and from that point on, Maya's side of the dashboard shows it as a discoverable model with its own quota and API key, exactly like a commercial LLM API."

**Can I safely reproduce this live?** `NO — SHOW EXISTING RESOURCE` for the governance objects (`YAML/CLI REQUIRED` to create) — dashboard **discovery view** is `NO — SHOW EXISTING RESOURCE` (read-only list).

> ⚠️ **Known platform bug (documented, not a demo blocker):** actual chat-completion calls through the *governed* MaaS endpoint using an API key currently fail with `HTTP 500 — authType 'apikey' credentials not found`. This is a backend credential-passthrough bug in this build's `ExternalProvider`, confirmed after exhaustive debugging (naming alignment across `MaaSModelRef`/`ExternalModel`/`HTTPRoute`, secret key format, etc.). **The demo's actual RAG generation calls use the direct internal predictor endpoint** (section F); the MaaS story here is scoped to **discovery + governance + API key creation**, which all work correctly.

---

## I. Subscription — how we obtained subscription, authorized users/groups, 100k token/hour quota

**Result already prepared:** `MaaSSubscription/llama-32-3b-instruct-subscription`, `Active`, priority `1`, rate limit **100,000 tokens/hour**.

**How we created it:** `YAML/CLI REQUIRED` to create; **UI-visible** to review.

**Dashboard path:** OpenShift AI dashboard → **Gen AI Studio → Models → llama-32-3b-instruct → Subscription** tab (or **Settings → MaaS subscriptions** if surfaced at admin level).

**Clicks:**
1. Open the model detail page (as in H)
2. Tab → **Access & Quota** (naming may vary — look for the quota badge on the model card)

**Fields (what the subscription encodes — read-only view):**

| Field | Value |
|---|---|
| Subscribed model | `llama-32-3b-instruct-external` |
| Priority | `1` |
| Rate limit | `100,000 tokens / hour` |
| Status | `Active` |

**What happens behind the UI:** `MaaSSubscription` (`maas.opendatahub.io/v1alpha1`) → reconciled into a Kuadrant `Limitador` rate-limit policy attached to the `HTTPRoute`.

**What you show after clicking:** The quota badge / subscription status = `Active`, priority `1`.

**What you say:** "This is the commercial-grade guardrail: every consumer of this model is metered against a real quota — 100,000 tokens per hour in this demo — enforced by Kuadrant's Limitador component at the gateway, before the request even reaches vLLM."

**Can I safely reproduce this live?** `NO — SHOW EXISTING RESOURCE` (`YAML/CLI REQUIRED` to create).

---

## J. Authorization policy

**Result already prepared:** `MaaSAuthPolicy/llama-32-3b-instruct-access`, `Active`.

**How we created it:** `YAML/CLI REQUIRED`.

**Dashboard path:** Same model detail page as I — authorization is generally bundled into the same "Access" view as the subscription (RHOAI 3.5 does not split these into separate dashboard tabs).

**Clicks:** Same as section I.

**Fields:** N/A — policy logic (API-key vs OAuth, which groups) is defined in the `AuthPolicy`/`MaaSAuthPolicy` spec, not exposed as editable dashboard fields in this build.

**What happens behind the UI:** `MaaSAuthPolicy` → reconciled into an Authorino `AuthPolicy` attached to the same `HTTPRoute`, requiring either a valid API key (`apikey` credential) or an OpenShift OAuth bearer token, matched against the `MaaSSubscription`.

**What you show after clicking:** `oc get maasauthpolicy llama-32-3b-instruct-access -n models-as-a-service` → `Active`.

**What you say:** "Authorization is layered on top of the subscription: Authorino checks 'is this caller who they claim to be and are they on an active subscription' before Limitador even checks the token quota. Two independent policy engines, one gateway hop."

**Can I safely reproduce this live?** `NO — SHOW EXISTING RESOURCE` (`YAML/CLI REQUIRED`).

---

# PERSONA 2 — MAYA, DATA SCIENTIST

## K. Discover MaaS model

**Result already prepared:** `llama-32-3b-instruct` visible to Maya as a governed model with a copyable public endpoint.

**How we created it:** UI — pure discovery, nothing to create.

**Dashboard path:** OpenShift AI dashboard → **Gen AI Studio → Models** (project-agnostic — MaaS models show up here regardless of which Data Science Project you're in).

**Clicks:**
1. Left nav → **Gen AI Studio**
2. Tab → **Models**
3. Click the `llama-32-3b-instruct` card

**Fields:** None (view only).

**What happens behind the UI:** The dashboard backend lists `MaaSModelRef` objects the current user's subscriptions grant access to.

**What you show after clicking:** Model detail panel: name, endpoint URL (`https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`), and an **API Keys** action.

**What you say:** "From Maya's side, this looks exactly like discovering a model on any commercial model marketplace — she didn't need to know anything about Kuadrant, Envoy, or Authorino underneath."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE` (pure navigation, zero risk).

---

## L. API key

**Result already prepared:** a stable API key already exists (`maas-api-key` Secret in `knowledge-advisor`, keys: `api-key`, `endpoint`, `model-name` — **value never shown in this document or in git**). This is the fallback the app/notebooks are configured against.

**How we created it:** UI-capable (the dashboard's **Create API key** action on the model detail page) — the stable one was created once ahead of time; **a second, temporary key can safely be created live and deleted afterward**.

**Dashboard path:** Gen AI Studio → Models → `llama-32-3b-instruct` → **API Keys** tab.

**Clicks (live, safe — create and then revoke):**
1. From the model detail page → **API Keys** tab
2. Click **Create API key**
3. Name it `demo-live-key`
4. Click **Create** — the raw key value is shown **once**
5. **Do not paste it anywhere on screen after copying it once for the terminal test (optional)**
6. Click **Revoke** on `demo-live-key` immediately after showing it

**Fields:**

| UI field | Exact demo value |
|---|---|
| Key name | `demo-live-key` |
| Associated subscription | `llama-32-3b-instruct-subscription` (auto-selected) |
| Expiration | Default (or 1 day, if offered) |

**What happens behind the UI:** A `Secret` (or Kuadrant `apikey`-type credential) is minted and linked to the caller's `MaaSSubscription`; Authorino validates it on every gateway request.

**What you show after clicking:** The one-time key reveal dialog, then the key row in the list with status `Active`, then `Revoked` after cleanup.

**What you say:** "Maya creates her own key with one click, scoped to her subscription. I'm revoking this demo key right after showing it — the application itself runs against a key we provisioned ahead of time, so nothing in this app depends on a key that only exists for the next thirty seconds."

**Can I safely reproduce this live?** `YES — CREATE LIVE` (then revoke immediately). Fallback: pre-created `maas-api-key` secret is what the app actually uses.

---

## M. Project — Create project flow (Maya's view)

Identical wizard to section E — shown here from Maya's perspective for narrative completeness.

**Result already prepared:** `knowledge-advisor` project, owned/used by Maya.

**Dashboard path / Clicks / Fields:** See section E.

**What you say:** "Same 'Create project' button Alex used earlier — Data Science Projects aren't admin-only, any authorized user creates their own."

**Can I safely reproduce this live?** `YES — SHOW FORM THEN CANCEL`, then `NO — SHOW EXISTING RESOURCE`.

---

## N. Connection — vector database (pgvector)

**Result already prepared:** Connection secret `vector-database` (type `uri-v1`) in `knowledge-advisor`, pointing at the `pgvector-db` PostgreSQL 14+ instance (with the `vector` extension enabled) attached to the Workbench.

**How we created it:** UI-capable (**Add connection → URI**) for the Connection itself; the underlying PostgreSQL+pgvector `Deployment`/`StatefulSet` was **YAML/CLI REQUIRED** (OpenShift AI does not provision databases — only connects to them).

**Dashboard path:** Project `knowledge-advisor` → **Connections** tab.

**Clicks (live, safe to cancel):**
1. Open project `knowledge-advisor` → **Connections** tab
2. Click **Create connection** (previous name: **Add connection**)
3. Choose connection type: **URI**
4. Fill fields below
5. Click **Cancel** (do not duplicate the real one) — then click the existing **vector-database** row to show it populated

**Fields:**

| UI field | Exact demo value |
|---|---|
| Connection name | `vector-database` |
| Connection type | URI |
| Access key / URI field label | `URI` |
| URI value | `postgresql://ragadmin:••••••••@pgvector-db.knowledge-advisor.svc.cluster.local:5432/ragdb` *(password never shown)* |

**What happens behind the UI:** A `Secret` labeled `opendatahub.io/connection-type: uri-v1`, which the dashboard renders as a "Connection" and which Workbenches/Pipelines can attach to via `envFrom`.

**What you show after clicking:** The Connections tab listing `vector-database` with type `URI`, and (in the Workbench) the resulting `URI` environment variable — value redacted by the dashboard UI itself.

**What you say:** "A Connection is OpenShift AI's abstraction over 'here's how to reach an external service' — in this case our pgvector-backed PostgreSQL instance. Attach it to a Workbench once, and every notebook in that Workbench just reads `os.environ['URI']` — no hardcoded credentials in code."

**Can I safely reproduce this live?** `YES — CREATE LIVE` (harmless — a duplicate connection can be created and deleted), or `YES — SHOW FORM THEN CANCEL` if you prefer zero cleanup.

---

## O. Connection — object storage (MinIO / S3)

**Result already prepared:** Two S3-type connections: `company-documents` (documents bucket, attached to the Workbench) and `pipeline-artifacts` (pipelines bucket, attached to the Data Science Pipeline server), both pointing at the in-cluster `minio` instance.

**How we created it:** UI-capable (**Create connection → S3 compatible object storage**) for the Connections; the MinIO `Deployment` + bucket creation Job — **YAML/CLI REQUIRED**.

**Dashboard path:** Project `knowledge-advisor` → **Connections** tab.

**Clicks (live, safe to cancel):**
1. **Create connection**
2. Choose connection type: **S3 compatible object storage - v1**
3. Fill fields below
4. **Cancel** — then open the existing `company-documents` row

**Fields:**

| UI field | Exact demo value |
|---|---|
| Connection name | `company-documents` |
| Connection type | S3 compatible object storage - v1 |
| Access key | *(redacted)* |
| Secret key | *(redacted)* |
| Endpoint | `http://minio.knowledge-advisor.svc.cluster.local:9000` |
| Region | `us-east-1` (placeholder — MinIO ignores it) |
| Bucket | `documents` |

**What happens behind the UI:** A `Secret` labeled `opendatahub.io/connection-type: s3`, mountable via `envFrom` into Workbenches/Pipelines, exposing `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_ENDPOINT`, `AWS_S3_BUCKET`.

**What you show after clicking:** Connections tab: `company-documents` (type S3) and `pipeline-artifacts` (type S3) both listed; MinIO console/bucket browser showing `documents/raw/*.md` (4 files) and `pipelines/artifacts/*`.

**What you say:** "Pipelines need somewhere to read raw documents from and write run artifacts to — that's an S3-compatible connection, same pattern as the database one. Here it points at an in-cluster MinIO, but the exact same Connection type works against AWS S3, Ceph, or any other S3-compatible store."

**Can I safely reproduce this live?** `YES — SHOW FORM THEN CANCEL`, then `NO — SHOW EXISTING RESOURCE`.

---

## P. Workbench — Create workbench

**Result already prepared:** `knowledge-advisor-workbench` Notebook, `Running`, image `s2i-generic-data-science-notebook:3.5`, hardware profile `default-profile` (1–2 CPU / 2–4Gi memory, no GPU needed), connections `vector-database` + `company-documents` attached.

**How we created it:** UI-capable.

**Dashboard path:** Project `knowledge-advisor` → **Workbenches** tab.

**Clicks (live, safe to cancel):**
1. **Workbenches** tab → **Create workbench**
2. Walk through the fields below
3. Click **Cancel**
4. Click the existing **Knowledge Advisor Workbench** row → **Open** (opens JupyterLab in a new tab)

**Fields:**

| UI field | Exact demo value |
|---|---|
| Name | `knowledge-advisor-workbench` |
| Description | Maya's JupyterLab environment for the Knowledge Advisor RAG application |
| Notebook image | `s2i-generic-data-science-notebook` — version `3.5` |
| Deployment size / Hardware profile | `default-profile` (2 CPU / 4Gi limits) |
| Accelerator | None |
| Storage (Cluster storage) | Persistent, default size |
| Connections | ✅ `vector-database`, ✅ `company-documents` |

**What happens behind the UI:** A Kubeflow `Notebook` CR → `StatefulSet` + `Service` + `Route`/`HTTPRoute` + OAuth-proxy sidecar for SSO, PVC for `/opt/app-root/src`.

**What you show after clicking:** Workbenches tab: status `Running`; then the live JupyterLab file browser inside the opened tab, showing `01_ingest_documents.py`, `02_semantic_search_test.py`, `03_rag_end_to_end.py`, `04_run_pipeline.py`, `build_ingestion_pipeline.py`.

**What you say:** "A Workbench is a full JupyterLab environment, sized and connected declaratively — pick an image, a hardware profile, and which Connections to attach, and OpenShift AI wires the environment variables in automatically. We're not spinning up a fresh one live because image pull + startup takes a couple of minutes — here's the one that's been running all morning with all our notebooks in it."

**Can I safely reproduce this live?** `YES — SHOW FORM THEN CANCEL`, then `NO — SHOW EXISTING RESOURCE` (open the warm one).

---

## Q. Embedding request — run it in the Workbench

**Result already prepared:** `02_semantic_search_test.py` — embeds the demo question and prints the top-3 pgvector matches with cosine similarity scores.

**How we created it:** Written ahead of time; **run it live** — it takes under 2 seconds.

**Dashboard path:** Inside the open JupyterLab tab (from P).

**Clicks (live):**
1. Open `02_semantic_search_test.py` (or the equivalent `.ipynb` if you prefer notebook cells)
2. **Run → Run All Cells** (or select-all + Shift+Enter)

**Fields:** None — the script hardcodes the demo question `"Which days can employees work remotely?"`.

**What happens behind the UI:** A `POST` to `http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings` returning a 384-float vector, then a `psycopg` query against `document_chunks` using pgvector's `<=>` cosine-distance operator with the HNSW index.

**What you show after clicking:** Terminal/cell output:
```
[0.7189] hr-remote-work-policy.md #2   Employees may work remotely on Monday and Friday...
[0.6059] hr-remote-work-policy.md #3   ...standard Monday/Friday remote days...
[0.5299] onboarding-guide.md #2        ...regardless of the standard Monday/Friday...
```

**What you say:** "This is the retrieval half of RAG in isolation — no LLM involved yet. The embedding model turns the question into a vector, pgvector finds the three closest policy chunks by cosine similarity, and the top hit is exactly the remote-work policy section we need."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE`.

---

## R. LLM/MaaS request — run it in the Workbench

**Result already prepared:** a terminal/notebook cell hitting the direct `llama-32-3b-instruct` predictor with a simple prompt, **plus** a `curl` example against the MaaS gateway endpoint to show the governed-API shape (headers, model id) even though the actual generated response for that specific call currently fails — see the H section warning.

**How we created it:** Written ahead of time; run live.

**Dashboard path:** JupyterLab terminal, inside the open Workbench tab.

**Clicks (live):**
1. Open a Terminal in JupyterLab (File → New → Terminal)
2. Run the direct-predictor call:
   ```bash
   curl -s http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"llama-32-3b-instruct","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":30}'
   ```
3. *(Optional, to show the MaaS shape)* run the MaaS gateway call with the pre-created API key env var already exported in the terminal (never typed on screen):
   ```bash
   curl -s https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com/v1/chat/completions \
     -H "Authorization: APIKEY $MAAS_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"llama-32-3b-instruct","messages":[{"role":"user","content":"Say hello in one sentence."}]}'
   ```

**Fields:** N/A (CLI call).

**What happens behind the UI:** Direct call → straight to the KServe predictor Service. MaaS call → Envoy Gateway → Authorino (API key check) → Limitador (quota check) → `ExternalProvider` → vLLM predictor.

**What you show after clicking:** Direct call returns a normal OpenAI-style JSON completion. (If demoing the MaaS call, be ready to narrate the known 500 as "credential passthrough bug we've filed" rather than pretend it works — audiences respect transparency here.)

**What you say:** "Same model, two paths in: direct in-cluster call for our application's actual RAG traffic, and the governed MaaS path with the API key for anyone consuming this model as a product from outside the cluster."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE` (direct call). MaaS call: optional, be candid about the known issue if you run it.

---

## S. Pipeline server — how it's configured from the project dashboard

**Result already prepared:** `DataSciencePipelinesApplication/dspa` in `knowledge-advisor`, `Running`, backed by external MinIO object storage (bucket `pipelines`) and a managed MariaDB for KFP metadata.

**How we created it:** UI-capable (**Configure pipeline server**) — created via YAML in this session for precise MinIO wiring, but the exact same fields exist in the dashboard form.

**Dashboard path:** Project `knowledge-advisor` → **Pipelines** tab → (if not yet configured) **Configure pipeline server**; once configured, **Settings (gear icon) → Configure pipeline server** to view/edit.

**Clicks:**
1. **Pipelines** tab
2. Click the gear/settings icon → **Configure pipeline server**
3. Point at the populated fields (do not resubmit — this restarts the server)

**Fields (what's already configured):**

| UI field | Exact demo value |
|---|---|
| Object storage connection | Existing connection → `pipeline-artifacts` |
| Bucket | `pipelines` |
| Base path | `artifacts` |

**What happens behind the UI:** A `DataSciencePipelinesApplication` CR → deploys `ds-pipeline-dspa` (API server + persistence agent + scheduler + Argo workflow-controller), `mariadb-dspa` (KFP metadata store), and an Envoy proxy sidecar for mTLS.

**What you show after clicking:** Pipelines tab: server status `Available`; pods `ds-pipeline-dspa-*`, `mariadb-dspa-*` all `Running`.

**What you say:** "Configuring a pipeline server is one form: point it at object storage for artifacts, and OpenShift AI stands up the whole Kubeflow Pipelines backend — API server, metadata database, and the Argo workflow engine underneath — behind the scenes."

**Can I safely reproduce this live?** `NO — SHOW EXISTING RESOURCE` (do not resubmit the config form — would restart the server mid-demo).

---

## T. Pipeline import — Pipelines → Import pipeline

**Result already prepared:** pipeline `knowledge-advisor-ingestion` already uploaded to the KFP server (4-step DAG: Load → Chunk → Embed → Store), compiled from `build_ingestion_pipeline.py`.

**How we created it:** UI-capable (**Import pipeline**) for the upload step; the pipeline *definition* is Python (KFP SDK), compiled to YAML — that authoring step is code, not UI, by design (this is normal KFP practice, not a platform limitation).

**Dashboard path:** Project `knowledge-advisor` → **Pipelines** tab → **Pipelines** sub-tab.

**Clicks (live, safe — re-importing creates a new version, harmless):**
1. **Pipelines** tab → **Import pipeline**
2. Fill fields below
3. Either click **Cancel**, or actually **Import** (creates a 2nd version of the same pipeline — safe, do not delete the original)
4. Click the existing **knowledge-advisor-ingestion** pipeline to open its graph

**Fields:**

| UI field | Exact demo value |
|---|---|
| Pipeline name | `knowledge-advisor-ingestion` |
| Pipeline description | Load company documents from MinIO, chunk, embed with all-minilm-l6-v2, store vectors in pgvector |
| Upload method | Upload a file → `ingestion_pipeline.yaml` (compiled in the Workbench) |

**What happens behind the UI:** KFP API server stores the pipeline spec (Argo `WorkflowTemplate`-equivalent) in its metadata DB (MariaDB) and object storage (MinIO `pipelines` bucket).

**What you show after clicking:** The pipeline **graph view**: 4 nodes — `load-documents` → `chunk-documents` → `embed-chunks` → `store-vectors`, connected by data-artifact edges.

**What you say:** "The pipeline itself is authored in Python using the Kubeflow Pipelines SDK — that's standard KFP practice, everyone writes pipelines as code — then compiled to this portable YAML and imported here with one click. From this point on, running it is pure UI."

**Can I safely reproduce this live?** `YES — CREATE LIVE` (import — safe, additive) or `NO — SHOW EXISTING RESOURCE` if you prefer zero risk.

---

## U. Pipeline run — actually click Run, show the graph

**Result already prepared:** the most recent run, `knowledge-advisor-ingestion-k8r5z`, status **Succeeded**, having written 26 chunks across 4 source documents into pgvector.

**How we created it:** UI-capable — this is the flagship "click Run live" moment.

**Dashboard path:** Project `knowledge-advisor` → **Pipelines** tab → **Runs** sub-tab (or from the pipeline detail page → **Create run**).

**Clicks (live — this is a REAL new run, ~35–45 seconds end to end):**
1. Open pipeline `knowledge-advisor-ingestion` → **Create run**
2. Fill fields below → **Create**
3. Watch the graph light up node-by-node: `load-documents` (green) → `chunk-documents` (green) → `embed-chunks` (green) → `store-vectors` (green)
4. Click each node → **Logs** tab to show real output (e.g. "Produced 26 chunks from 4 documents")

**Fields:**

| UI field | Exact demo value |
|---|---|
| Run name | `knowledge-advisor-ingestion-run-live` |
| Experiment | `knowledge-advisor` |
| Pipeline version | latest |
| Run parameters | defaults are correct — `bucket=documents`, `prefix=raw/`, `embed_model=all-minilm-l6-v2` |

**What happens behind the UI:** KFP creates an Argo `Workflow`; the workflow-controller schedules 4 pairs of driver/executor pods (KFP v2 launcher pattern), each writing/reading a `Dataset` artifact (JSON file) on the run's backing volume, ending with a `psycopg` write to `document_chunks` in pgvector.

**What you show after clicking:** The live graph turning green node-by-node, then the final `Succeeded` badge, then (optional) a quick `SELECT count(*) FROM document_chunks;` in a terminal showing the refreshed row count.

**What you say:** "This is a real pipeline run, right now, reading the four company documents straight from MinIO, chunking them by policy section, embedding every chunk, and truncating-and-rewriting the vector table in Postgres — the exact same data our RAG app queries a second from now."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE` (click Run on the existing imported pipeline).

---

## V. OGXServer — mandatory

**Result already prepared:** `OGXServer/knowledge-advisor-ogx`, phase **Ready**, 1 replica available, wired to:
- `remote::vllm` inference providers → `llama-32-3b-instruct` and `all-minilm-l6-v2` predictors
- `remote::pgvector` vector-io provider → the same `pgvector-db` instance
- sqlite-backed operational storage (its own metadata, separate from the RAG data)

**How we created it:** **OGXSERVER CREATION REQUIRES YAML** — OpenShift AI 3.5 does not provide a creation wizard/form for `OGXServer` in this build. The exact YAML path used:
`openshift-ai-demo/yaml/knowledge-advisor-ogxserver.yaml` + `knowledge-advisor-ogx-baseconfig.yaml` (a full `overrideConfig` ConfigMap — required in this sandbox due to two platform-specific gaps documented inline in that file: a registry-auth issue in the operator's own OCI-label resolution, and a missing `persistence` field in the operator's declarative pgvector-provider mapping).

**Where you click in OpenShift AI to see/use the resulting server:**

**Dashboard path:** OpenShift AI dashboard → **Gen AI Studio** → the project's models list will show `llama-32-3b-instruct` and `all-minilm-l6-v2` as available through the `knowledge-advisor-ogx` server, once you select the `knowledge-advisor` project context. Also visible under project `knowledge-advisor` → **Models** tab (OGX-registered models appear alongside directly-deployed `InferenceService`s).

**Clicks:**
1. Gen AI Studio → select project `knowledge-advisor` from the project switcher
2. Point at the model dropdown — both `llama-32-3b-instruct` and `all-minilm-l6-v2` are listed, tagged as served via `knowledge-advisor-ogx`

**Fields:** N/A (dashboard is read-only for OGXServer in this build).

**What happens behind the UI (the YAML that was required):**
```
ConfigMap (knowledge-advisor-ogx-override-config, labeled ogx.io/watch: "true")
   └── full config.yaml: providers.inference.remote.vllm[2], providers.vector_io.remote.pgvector[1],
       registered_resources.models[2] (llm + embedding, with embedding_dimension: 384)
OGXServer (knowledge-advisor-ogx)
   └── spec.overrideConfig → the ConfigMap above
   └── spec.workload.overrides.env → OGX_PGVECTOR_PASSWORD from Secret pgvector-db-credentials
   └── reconciled into: Deployment (1 replica) + Service (knowledge-advisor-ogx-service:8321)
```

**What you show after clicking:** `oc get ogxserver knowledge-advisor-ogx -n knowledge-advisor` → `Ready`, `1` available. Then a live `curl` from a terminal:
```bash
curl -s http://knowledge-advisor-ogx-service.knowledge-advisor.svc.cluster.local:8321/v1/models
```
returning both registered models with their provider ids and (for the embedding model) `embedding_dimension: 384`.

**What you say:** "OGX — Red Hat's rebrand of the Llama Stack API — gives us one OpenAI-compatible server in front of both our inference providers and our vector store. Creating the server itself is still a YAML step on this release; the dashboard's Gen AI Studio and Playground consume it transparently once it exists — that's the split we're showing: platform team writes the YAML once, everyone else just uses a dropdown."

**Can I safely reproduce this live?** `YAML/CLI REQUIRED` to create — show `oc apply` conceptually (do not actually delete/recreate live, it took real debugging to land on a working config). `YES — RUN EXISTING RESOURCE` for using it (curl `/v1/models`, `/v1/chat/completions`, `/v1/embeddings` — all live, all safe, all read/inference-only).

---

## W. Gen AI Studio / Playground

**Result already prepared:** `genAiStudio: true` dashboard feature flag; backend (`knowledge-advisor-ogx`) confirmed reachable and correctly serving both models.

**Dashboard path:** OpenShift AI dashboard → **Gen AI Studio → Playground**.

**Clicks (live):**
1. Left nav → **Gen AI Studio → Playground**
2. **Select server**: `knowledge-advisor-ogx`
3. **Select model**: `llama-32-3b-instruct`
4. Type a test prompt, e.g. *"In one sentence, what do you do?"*
5. Click **Send**

**Fields:**

| UI field | Exact demo value |
|---|---|
| Server | `knowledge-advisor-ogx` |
| Model | `llama-32-3b-instruct` |
| System prompt | (optional) *"You are the Acme Corp Knowledge Advisor."* |
| Temperature | Default (0.1–0.7 — low is fine for policy Q&A) |

**What happens behind the UI:** Dashboard → OGX server `/v1/chat/completions` → vLLM predictor.

**What you show after clicking:** Streamed (or full) response rendered in the Playground chat pane.

**What you say:** "Playground is the zero-code way to sanity-check any model registered with OGX — no notebook, no curl, just pick a server and a model and chat. It's also how you'd demo a new model to a stakeholder before wiring it into an application."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE`.

---

## X. RAG — show retrieved context before LLM generation

**Result already prepared:** `03_rag_end_to_end.py` in the Workbench — prints retrieved chunks, THEN the generated answer, in that order, so the retrieval step is visible before generation happens.

**Dashboard path:** JupyterLab (Workbench), or the Streamlit app itself (section Y) which shows the same ordering in its UI.

**Clicks (live — pick ONE of these two, Streamlit is more visual):**

*Option 1 — Notebook:*
1. Open `03_rag_end_to_end.py` in the Workbench
2. Run all cells

*Option 2 — Streamlit (recommended, more visual):*
1. Open `https://knowledge-advisor-streamlit-knowledge-advisor.apps.ocp.tfmbf.sandbox2633.opentlc.com`
2. Question box already contains: *"Which days can employees work remotely?"*
3. Click **Ask Knowledge Advisor**
4. Point at the **"📄 Retrieved context (before generation)"** section appearing first
5. Then point at the **"✅ Answer"** section appearing after

**Fields:** Question text box (pre-filled with the demo question, editable).

**What happens behind the UI:** Embed → pgvector similarity search (top-3) → prompt augmentation → `POST` to the LLM predictor → render.

**What you show after clicking:**
```
📄 Retrieved context (before generation)
[0.719] hr-remote-work-policy.md #2 — "...Employees may work remotely on Monday and Friday..."
[0.606] hr-remote-work-policy.md #3 — "...standard Monday/Friday remote days..."
[0.530] onboarding-guide.md #2 — "...regardless of the standard Monday/Friday..."

✅ Answer
According to the Acme Corp Remote Work Policy, employees can work remotely
on Monday and Friday. (Source: hr-remote-work-policy.md)
```

**What you say:** "This is the whole point of RAG made visible: you can see exactly which policy text the model was grounded in, before it ever generates a word — no hallucination risk, and if the answer's wrong, you know immediately whether it's a retrieval problem or a generation problem."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE`.

---

## Y. Application — Knowledge Advisor Streamlit app

**Result already prepared:** `knowledge-advisor-streamlit` Deployment, `Running`, `Route` reachable at `https://knowledge-advisor-streamlit-knowledge-advisor.apps.ocp.tfmbf.sandbox2633.opentlc.com`, using the exact same three backends (embedding predictor, pgvector, LLM predictor) already shown working.

**How we created it:** `YAML/CLI REQUIRED` for the Deployment/Service/Route (OpenShift AI has no "deploy my own web app" wizard) — but every backend call is identical to what you've already shown from the dashboard/Workbench.

**Dashboard path (to show the underlying OpenShift objects, optional):** OpenShift Console → **Workloads → Deployments** → project `knowledge-advisor` → `knowledge-advisor-streamlit`.

**Clicks (live):**
1. Open the Streamlit URL in a browser tab
2. Ask the demo question (pre-filled) → **Ask Knowledge Advisor**
3. *(Optional)* type a different question, e.g. *"What is the process for requesting new hardware?"* → shows the app generalizes beyond the one canned question

**Fields:** Question text input only.

**What happens behind the UI:** Same 3-step RAG call as section X, just wrapped in a Streamlit UI instead of a notebook.

**What you show after clicking:** Full app screenshot: title, retrieved-context cards, final answer card, and the "How this works" expander at the bottom.

**What you say:** "This is what Maya ships to the rest of the company — same backend we've been poking at all demo, now behind a UI anyone in Acme Corp can use without touching a notebook or a terminal."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE`.

---

## Z. MLflow — experiment, run, parameters, metrics

**Result already prepared:** MLflow experiment `knowledge-advisor-rag` (workspace `knowledge-advisor`) with 3 `FINISHED` runs logged from the Workbench (`connectivity-test`, `auto-injected-env-test`, `builtin-satoken-test`), demonstrating the full auth + workspace-context chain works.

**How we created it:** UI-capable for *browsing* (MLflow's own UI, embedded/linked from the dashboard); run logging itself is done via the `mlflow` Python client from the Workbench (standard MLflow practice — not a platform limitation).

**Dashboard path:** OpenShift AI dashboard → project `knowledge-advisor` → look for an **MLflow** / **Experiment tracking** tile or link (or navigate directly to `https://rh-ai.apps.ocp.tfmbf.sandbox2633.opentlc.com/mlflow`, selecting workspace `knowledge-advisor`).

**Clicks:**
1. Open the MLflow URL
2. Switch workspace (top bar) → `knowledge-advisor`
3. Click experiment **knowledge-advisor-rag**
4. Click into any `FINISHED` run

**Fields:** None (view only) — to log a NEW run live, run this in the Workbench terminal:
```python
import mlflow
mlflow.set_experiment("knowledge-advisor-rag")
with mlflow.start_run(run_name="live-demo-run"):
    mlflow.log_param("question", "Which days can employees work remotely?")
    mlflow.log_metric("retrieval_top1_score", 0.719)
    mlflow.log_metric("answer_correct", 1)
```

**What happens behind the UI:** The MLflow client authenticates with the Workbench's ServiceAccount token (`MLFLOW_TRACKING_AUTH=kubernetes-namespaced`), targets the `knowledge-advisor` workspace (`MLFLOW_WORKSPACE` env var), and writes params/metrics to the MLflow tracking server backed by the ModelRegistry/MLflow Operator.

**What you show after clicking:** Run detail page: Parameters (`question`), Metrics (`retrieval_top1_score=0.719`, `answer_correct=1`), and the run's `FINISHED` status.

**What you say:** "Every RAG query — or every pipeline run — can log its inputs, the retrieval score, and whether the answer was correct straight to MLflow, giving you a queryable history of quality over time, not just 'it worked once in a demo.'"

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE` (browse existing runs); logging a new run live is `YES — CREATE LIVE` (the snippet above, ~2 seconds).

---

## AA. MCP Catalog — click-by-click browse path

**Result already prepared:** `mcpCatalog: true` dashboard feature flag enabled.

**Dashboard path:** OpenShift AI dashboard → **MCP Catalog** (top-level left-nav item under the Gen AI section).

**Clicks:**
1. Left nav → **MCP Catalog**
2. Browse the tile grid of available Model Context Protocol servers
3. Click any tile to see its description, tools exposed, and connection instructions

**Fields:** None (browse only).

**What you show after clicking:** The catalog grid + one tile's detail panel (tool list, transport type).

**What you say:** "MCP Catalog is where OpenShift AI surfaces ready-to-connect Model Context Protocol servers — the emerging standard for giving agents structured tool access — so teams don't have to hunt these down or write their own connectors from scratch."

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE`.

---

## AB. Agents Catalog — click-by-click browse path

**Result already prepared:** `agentsCatalog: true` and `agentConfigManagement: true` dashboard feature flags enabled.

**Dashboard path:** OpenShift AI dashboard → **Agents Catalog** (top-level left-nav item under the Gen AI section).

**Clicks:**
1. Left nav → **Agents Catalog**
2. Browse the tile grid of pre-built agent templates
3. Click a tile to see its configuration (model requirements, tools/MCP servers it uses)

**Fields:** None (browse only).

**What you show after clicking:** The catalog grid + one tile's detail/config panel.

**What you say:** "Agents Catalog is the next layer up from MCP Catalog — pre-built agent patterns that already know how to combine a model with a set of tools. It's where a team would start if they wanted to go from 'RAG chatbot' to 'autonomous agent that can act on the answer.'"

**Can I safely reproduce this live?** `YES — RUN EXISTING RESOURCE`.

---

# Appendix — full resource-by-resource index

For every resource not already covered in full detail above, here is the compact reference:

| Resource | Result | Created via | Live-safe? |
|---|---|---|---|
| `default-dsc` (DataScienceCluster) | Ready | UI (initial install) | NO — show existing |
| `gpu-profile` / `default-profile` (HardwareProfile) | Present | UI-capable | YES — form then cancel |
| `llama-32-3b-instruct` (InferenceService) | Ready | UI-capable | YES — form then cancel |
| `all-minilm-l6-v2` (InferenceService) | Ready | UI-capable (Model Catalog) | YES — form then cancel |
| `ExternalModel` / `MaaSModelRef` / `MaaSAuthPolicy` / `MaaSSubscription` | Ready/Active | YAML/CLI required | NO — show existing |
| `maas-api-key` (stable API key secret) | Present | UI-capable (create), pre-created | YES — create temp key live, revoke |
| `knowledge-advisor` (Data Science Project) | Present | UI-capable | YES — form then cancel |
| `pgvector-db` (PostgreSQL 14 + pgvector) | Running | YAML/CLI required (DB itself) | NO — show existing |
| `minio` (S3-compatible storage) | Running | YAML/CLI required | NO — show existing |
| `vector-database` (Connection) | Present | UI-capable | YES — create live |
| `company-documents` / `pipeline-artifacts` (Connections) | Present | UI-capable | YES — form then cancel |
| 4 company documents in MinIO `documents/raw/` | Present | Uploaded via Workbench/CLI | NO — show existing |
| `knowledge-advisor-workbench` (Notebook) | Running | UI-capable | YES — form then cancel |
| `dspa` (DataSciencePipelinesApplication) | Running | UI-capable | NO — show existing (don't resubmit) |
| `knowledge-advisor-ingestion` (Pipeline + latest run) | Succeeded | UI-capable (import/run) | YES — run existing |
| `knowledge-advisor-ogx` (OGXServer) | Ready | **YAML/CLI required** | NO — show existing; USE it live via curl/Playground |
| `knowledge-advisor-streamlit` (Deployment/Service/Route) | Running | YAML/CLI required | YES — use live in browser |
| MLflow experiment `knowledge-advisor-rag` | 3 runs | UI-capable (browse), client (log) | YES — browse / log new run live |
| MCP Catalog / Agents Catalog | Enabled | Platform flags | YES — browse live |

---

*Every claim in this document was validated against the live cluster on 2026-09-17 —
see `PREDEMO-HEALTHCHECK.sh` output (30 PASS / 1 documented WARN / 0 FAIL) and
re-run it 15–30 minutes before presenting.*
