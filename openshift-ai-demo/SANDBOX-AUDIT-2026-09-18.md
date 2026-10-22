# Red Hat OpenShift AI 3.5 — Sandbox Read-Only Audit

**Date:** 2026-09-18
**Method:** 100% read-only (`oc get`, `oc explain`, `oc describe`, `oc logs`). No cluster writes performed during this audit.
**Cluster:** `api.ocp.tfmbf.sandbox2633.opentlc.com` — OpenShift `4.20.36`, RHOAI (`rhods-operator`) `3.5.0`.

> This document is the source of truth for "what actually exists" in the sandbox right now. Where the live cluster disagrees with the official docs, it is called out explicitly under **Discrepancies** — never silently reconciled.

---

## A. Cluster / RHOAI

| Item | Value |
|---|---|
| OpenShift version | `4.20.36` |
| RHOAI Operator (CSV) | `rhods-operator.3.5.0` — `Succeeded` |
| Key Operators (all `Succeeded`) | Authorino `1.4.3`, Red Hat Connectivity Link (Kuadrant) `1.4.3`, Limitador `1.4.2`, OpenShift Serverless `1.37.1`, OpenShift Pipelines `1.24.0`, NVIDIA GPU Operator `25.3.4` |
| `DataScienceCluster` (`default-dsc`) | Present, mostly healthy |
| `DSCInitialization` (`default-dsci`) | `serviceMesh: None`, `monitoring: Managed` |
| `OdhDashboardConfig` (`odh-dashboard-config`, ns `redhat-ods-applications`) | Present |

### DSC component states (`spec.components.*.managementState`)

| Component | State | Notes |
|---|---|---|
| `kserve` | `Managed` | |
| `kserve.modelsAsService` | `Removed` (default) | **Deprecated field** — see Discrepancy #1 |
| `aigateway` | `Managed` | The **real** MaaS toggle |
| `aigateway.modelsAsAService` | `Managed` | ✅ MaaS is genuinely enabled |
| `ogx` | `Managed` | ✅ |
| `llamastackoperator` | `Removed` | ✅ Correct — must be `Removed` for OGX to reconcile |
| `trustyai` | `Managed` (guardrails mode off) | |
| `modelregistry` | `Managed` (`rhoai-model-registries` ns) | |
| `nim` | `Managed` | |
| `wva` | `Removed` | |

### DSC non-Ready conditions (all expected/benign)

```
BatchGatewayReady=False        — "Submodule ManagementState is set to Removed" (not used by us)
KueueReady=False               — "Component ManagementState is set to Removed" (not used by us)
KserveLLMInferenceServiceWideEPDependencies=False — "LeaderWorkerSet not installed"
```

The last one only matters for **multi-node "wide expert-parallelism"** LLM deployments. Our single-GPU vLLM deployment does not need it. No action required.

### `OdhDashboardConfig` — all relevant feature flags (current values)

```
agentConfigManagement: true       aiAssetCustomEndpoints: true      genAiStudio: true
agentOps: true                    agentsCatalog: true                genAiTracing: true
guardrails: true                  mcpCatalog: true                   mcpRegistry: true
modelAsService: true              promptManagement: true             toolCalling: true
vLLMDeploymentOnMaaS: true   ← enabled by us this session (was false)
disableKServeMetrics/disableModelCatalog/disableModelRegistry/disableTracking: all false (i.e. those pages are visible)
```

Flags that exist in the CRD but are **not** enabled and have no live backend seen yet: `externalModels`, `llmGatewayField`, `llmdTemplates`, `autorag`, `externalVectorStores`, `featureStoreAdmin`, `gpuaas`, `trainingJobs`.

Flags confirmed **deprecated / no-op** in this build: `maasAuthPolicies`, `disableAcceleratorProfiles`, `disableHardwareProfiles`, `disableFineTuning`, `disableModelMesh`, `mlflow`.

---

## B. Compute

| Item | Value |
|---|---|
| Nodes | 1 (`ip-10-0-31-7`, `g6.8xlarge`) |
| CPU allocatable | 31500m |
| Memory allocatable | ~120 GiB |
| GPU | **1× NVIDIA L4** (23 GB VRAM, Ada Lovelace, no MIG, no vGPU, no sharing) |
| NVIDIA GPU Operator | `25.3.4`, all daemonsets `Running` (device-plugin, dcgm, toolkit, driver, gfd) |

**⚠️ Critical constraint for the whole demo: there is exactly ONE GPU on this cluster.** Any GPU-based model deployment (LLM, and any GPU embedding model) competes for that single GPU. Two GPU models cannot run simultaneously.

### Hardware Profiles (`redhat-ods-applications` ns)

| Name | CPU (min/default) | Memory (min/default) | GPU |
|---|---|---|---|
| `default-profile` | 1 / 2 | 2Gi / 4Gi | none |
| `gpu-profile` | 1 / 1 | 1Gi / 12Gi | `nvidia.com/gpu`: 1/1 |

These are the only two Hardware Profiles available — both are cluster-scoped (visible to any project). This is exactly what the "Deploy model" wizard's **Hardware profile** dropdown will offer.

---

## C. Storage

| Item | Value |
|---|---|
| StorageClasses | `gp2-csi`, `gp3-csi` (default) — both AWS EBS, `WaitForFirstConsumer` |
| MinIO / S3 pods | **None currently running** (the previous `knowledge-advisor` MinIO instance was deleted with the project) |
| PostgreSQL instances | `maas-postgres` (MaaS backend), `model-catalog-postgres` (Model Catalog backend), `tekton-results-postgres` (pipelines), `keycloak-pgsql` (SSO) |
| pgvector | **Not present anywhere yet** — will need to be created by Maya for the RAG demo |
| Existing OpenShift AI Connections | None (no Data Science Project exists yet — see Section D) |
| Relevant PVCs | `maas-postgres-pvc` (2Gi), `mlflow-pvc` (10Gi) |

---

## D. Model Serving

| Item | Value |
|---|---|
| Data Science Projects (`opendatahub.io/dashboard=true` namespaces) | **0** |
| `InferenceService` objects (cluster-wide) | 1 → `llama-32-3b-instruct` in ns `my-first-model`, `Ready=True` |
| `LLMInferenceService` objects (new architecture) | **0** |
| `ServingRuntime` objects | 1 → `llama-32-3b-instruct` (vLLM NVIDIA GPU ServingRuntime, image `registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.2.4`) |
| ModelMesh | Not present (single-model serving only, as expected in 3.5) |
| KServe controllers | `kserve-controller-manager`, `kserve-module-controller-manager` — both `Running` |
| Model Catalog | `model-catalog` + `model-catalog-postgres` pods `Running` in `rhoai-model-registries` |
| Embedding model | **None deployed** (the previous `all-minilm-l6-v2` was intentionally deleted for the rebuild) |

**⚠️ Important gap found:** namespace `my-first-model` does **not** carry the `opendatahub.io/dashboard=true` label. This means it was created via `oc`/YAML, **not** through the dashboard's "Create project" flow, and it will likely **not appear under "Data Science Projects → Projects"** in the UI. For a clean, fully-clickable demo, Llama should live inside a proper dashboard-created project.

`llama-32-3b-instruct` details relevant for redeployment:
- Storage: `oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct` (OCI ModelCar, no S3 needed)
- Runtime args: `--dtype=half --max-model-len=20000 --gpu-memory-utilization=0.95 --enable-auto-tool-choice --tool-call-parser=llama3_json --chat-template=/opt/app-root/template/tool_chat_template_llama3.2_json.jinja`
- Resources: `1× nvidia.com/gpu`, 6-16Gi RAM, 1-4 CPU
- Labels: `opendatahub.io/genai-asset: "true"` (shows as an AI asset), `security.opendatahub.io/enable-auth: false` (no token auth on the direct predictor)

---

## E. MaaS (Models-as-a-Service)

| Prerequisite (per official doc §1.1–1.9) | Live state | Ready? |
|---|---|---|
| Red Hat Connectivity Link (Kuadrant) installed | `rhcl-operator.v1.4.3` Succeeded, `Kuadrant` CR present in `kuadrant-system` | ✅ |
| Authorino | `authorino-operator.v1.4.3` Succeeded | ✅ |
| Limitador | `limitador-operator.v1.4.2` Succeeded | ✅ |
| Gateway API / GatewayClass | 3 Gateways programmed: `data-science-gateway`, `maas-default-gateway` (external ELB), `openshift-ai-inference` | ✅ |
| MaaS DB secret / Postgres | `maas-postgres` pod `Running`, PVC bound | ✅ |
| MaaS enabled in DSC | See Discrepancy #1 below | ✅ (via correct field) |
| Dashboard flag `modelAsService` | `true` | ✅ |
| Dashboard flag `genAiStudio` | `true` | ✅ |
| MaaS namespace `models-as-a-service` | `Active` | ✅ |
| MaaS control-plane pods | `maas-controller`, `maas-ui`, `maas-postgres` all `Running` | ✅ |
| Tenant reconciliation | `MaasTenantConfig/default-tenant` → `Ready=True`, `Reconciled` | ✅ (see Discrepancy #2) |

### Current MaaS governance objects

```
MaaSModelRef       : none  (deleted during the reset — clean slate)
MaaSSubscription    : none  (clean slate)
MaaSAuthPolicy       : none  (clean slate)
ExternalProvider/ExternalModel : none (created + deleted again this session — see Discrepancy #3)
```

MaaS is **structurally ready** but has **zero published models** right now. This is exactly the starting point requested for the guided rebuild.

### Discrepancies found (doc vs. this exact build)

1. **MaaS enable field moved.** Official doc §1.6 says: *"Set `spec.components.kserve.modelsAsService.managementState` to `Managed`."* On this build that field is **explicitly deprecated** (`oc explain` confirms: *"Deprecated... MaaS is now configured via `spec.components.aigateway.modelsAsAService`... Removed→Managed is blocked"*). The real, active field is `spec.components.aigateway.modelsAsAService.managementState`, and it is already `Managed`. **Net effect: no action needed, but the doc section is stale for this build.**

2. **`Tenant` CRD vs. `MaasTenantConfig` CRD.** Doc §1.9 tells you to verify with `oc get tenants.maas.opendatahub.io default-tenant`. On this cluster, no `Tenant` object exists; the actual reconciled resource is `MaasTenantConfig/default-tenant` in `models-as-a-service`, and it is `Ready=True`. Functionally equivalent, different resource kind on this build.

3. **`ExternalModel`/`ExternalProvider` cannot wrap a plain-HTTP internal `InferenceService`.** We tested this live: the CRD only supports HTTPS:443 upstream endpoints (hardcoded `DestinationRule` with `tls.mode: SIMPLE`, `ServiceEntry` port fixed to `443/HTTPS`, no port/scheme override field exists). Our vLLM predictor serves plain HTTP on port 80 — connecting would fail. **Conclusion: this Tech Preview mechanism is only usable for real external cloud providers (OpenAI/Bedrock/Vertex/Anthropic), not for wrapping a self-hosted model.** The officially correct path for self-hosted vLLM models is `vLLMDeploymentOnMaaS` + the `LLMInferenceService` deployment path (doc §1.10), which we found and enabled this session.

4. **`MaaSModelRef.spec.modelRef.kind` enum is `["LLMInferenceService", "ExternalModel"]` only** — confirmed via `oc explain`. A classic `InferenceService` (our current Llama) can never be referenced directly, regardless of method used (dashboard or YAML). This is a hard platform rule, not a bug.

---

## F. OGX / RAG

| Item | Live state |
|---|---|
| `ogx` DSC component | `Managed` |
| `llamastackoperator` DSC component | `Removed` (correct — must be Removed, confirmed earlier in this project) |
| OGX operator pods | `ogx-k8s-operator-controller-manager`, `opendatahub-ogx-operator` — both `Running` |
| OGX CRDs | `ogxs.components.platform.opendatahub.io`, `ogxservers.ogx.io` — both installed |
| `OGXServer` objects | **0** (deleted with `knowledge-advisor` project — clean slate) |
| Gen AI Studio UI pod | `gen-ai-ui` `Running` |
| MLflow | `mlflow`, `mlflow-operator-controller-manager`, `mlflow-ui` — all `Running` |
| Data Science Pipelines Application (DSPA) | **0** (no project exists yet) |
| MCP Catalog / Agents Catalog CRDs | **None found on cluster**, despite `mcpCatalog`/`mcpRegistry`/`agentsCatalog` dashboard flags being `true`. **Marked NEEDS BROWSER CONFIRMATION** — these may be dashboard-only static pages with no dedicated backend CRD, or the backend may not be installed. Will verify live in the browser before including in the demo. |
| Workbenches (`Notebook` CRs) | **0** |
| Data Science Projects | **0** |

---

## Audit Table (summary)

| Capability | Official 3.5 prerequisite | Live state | Ready? | UI available? | Action needed |
|---|---|---|---|---|---|
| OpenShift / RHOAI Operator | 4.14+ / RHOAI 3.5 | OCP 4.20.36 / RHOAI 3.5.0 | READY | — | none |
| GPU | NVIDIA GPU Operator + device plugin | 1× L4, operator healthy | READY | Admin/Hardware profiles | none (capacity-constrained: 1 GPU total) |
| Hardware Profiles | ≥1 GPU profile | `gpu-profile`, `default-profile` | READY | Settings → Hardware profiles | none |
| Storage classes | CSI-backed default SC | `gp3-csi` default | READY | — | none |
| Object storage (S3/MinIO) | required for pipelines/connections | none deployed | NEEDS CONFIGURATION | Connections (dashboard) | Maya deploys/connects one |
| PostgreSQL + pgvector | required for OGX vector store | none deployed | NEEDS CONFIGURATION | YAML/CLI (no managed Postgres service in dashboard) | Deploy for RAG phase |
| Data Science Project | required container for everything Maya does | none exists | NEEDS CONFIGURATION | Data Science Projects → Create project | Create `knowledge-advisor` |
| LLM serving (Llama) | vLLM + GPU | Deployed, `Ready=True`, but as legacy `InferenceService` in a non-dashboard namespace | NEEDS CONFIGURATION (for MaaS) | Deployments → Deploy model | Redeploy as `LLMInferenceService` in a proper project to enable MaaS |
| Embedding model | vLLM/sentence-transformers | none deployed | NEEDS CONFIGURATION | Deployments → Deploy model | Deploy fresh |
| MaaS platform (Gateway/Kuadrant/Tenant) | See §1.1–1.9 | All healthy | READY | — | none |
| MaaS model publication | `MaaSModelRef` | none exist | NEEDS CONFIGURATION | Deploy model wizard ("Publish as MaaS") | Do during LLM redeploy |
| MaaS Subscription | `MaaSSubscription` | none exist | NEEDS CONFIGURATION | Settings → Subscriptions | Create |
| MaaS Authorization Policy | `MaaSAuthPolicy` | none exist | NEEDS CONFIGURATION | Settings → Authorization policies | Create |
| MaaS API keys | dashboard-issued | 3 stale keys exist from earlier debugging, unrevoked | NEEDS CONFIGURATION | Gen AI Studio → API keys | Revoke stale, create fresh |
| OGX operator/CRDs | `ogx: Managed`, `llamastackoperator: Removed` | Correct | READY | — | none |
| OGXServer | 1 per RAG project | none exist | NOT INSTALLED | OpenShift Console UI + YAML (no dashboard wizard exists) | Create for `knowledge-advisor` |
| Pipelines | DSPA + pipeline server | none exist | NOT INSTALLED | Project → Pipelines → Configure pipeline server | Create |
| MLflow | operator + instance | `Managed`, pods Running | READY | Project settings → tracking | none (log real run later) |
| MCP Catalog / Agents Catalog | dashboard flags on | flags `true`, no backend CRD found | UNKNOWN / NEEDS BROWSER CONFIRMATION | Left nav (unconfirmed) | Verify live before promising in demo |
| Gen AI Studio / Playground | `genAiStudio: true` | Pod Running | READY | Gen AI Studio (left nav) | none |

---

## Bottom line for Phase 2

The platform (Alex's layer) is in genuinely good shape: GPU, Hardware Profiles, MaaS control plane, OGX operator, MLflow are all healthy. What's missing is entirely the **content layer**: no Data Science Project, no MaaS-publishable model, no embedding model, no vector DB, no OGXServer, no pipeline. This matches exactly the "clean slate, rebuild the right way" state you asked for.

The single biggest structural decision for the whole rebuild: **Llama needs to move from a legacy `InferenceService` (in a non-dashboard namespace) to a dashboard-created `LLMInferenceService` inside a real Data Science Project**, because that is the only backend kind MaaS can reference. This was confirmed by reading the CRD schema directly, not assumed.

Proceeding to **Phase 2 — MaaS Learning Guide** next.
