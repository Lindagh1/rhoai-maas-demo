> **UPDATE 3 (2026-09-16, correction):** **OGX is actually available and is now enabled and healthy.** UPDATE 2 below (and the original §23) incorrectly concluded OGX was a platform gap. The real cause: the pre-existing `llamastackoperator: Managed` setting blocked it — per official Red Hat docs, OGX is the renamed successor to Llama Stack and the two cannot both be `Managed`. Removing `llamastackoperator` and re-enabling `ogx` fixed it in under a minute: `OGXReady=True`, CRDs registered, operator pods `Running`. The four Gen AI Studio flags that were deferred because of "no OGX" (`agentConfigManagement`, `agentOps`, `genAiTracing`, `promptManagement`) are now enabled too. No `OGXServer` CR has been created yet (still deferred pending your approval — it needs an external PostgreSQL 14+ not yet provisioned). Full detail in `ENABLED-FEATURES.md` §1 and §5.
>
> **UPDATE 2 (2026-09-16, final pass):** **Models-as-a-Service is now fully enabled and verified working.** Red Hat Connectivity Link (Kuadrant/Authorino/Limitador) was installed, `aigateway.modelsAsAService` is `Managed` and `Ready`, and the existing `llama-32-3b-instruct` model was **reused** (not redeployed) by wiring it into MaaS via an `ExternalProvider`/`ExternalModel`/`MaaSModelRef` pointing at its existing in-cluster service, plus a `MaaSAuthPolicy` and `MaaSSubscription` for governance. End state: `MaaSModelRef` → `Ready=True`, `"Governed and runtime-healthy"`, servable at `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`. Full detail in [`ENABLED-FEATURES.md`](./ENABLED-FEATURES.md) §3.
>
> **UPDATE 1 (2026-09-16, earlier same day):** **MLflow** is now `Managed` and healthy with a working tracking server; **Agents Catalog**, **guardrails**, **toolCalling**, **mcpCatalog**, and **mcpRegistry** dashboard flags are now enabled and verified safe. **OGX** was attempted but its CRD is missing from this specific RHOAI 3.5.0 build — rolled back, documented as a platform gap, not a config error.
>
> The sections below (1–30) reflect the *original* read-only audit state from before any of this configuration work. Treat [`ENABLED-FEATURES.md`](./ENABLED-FEATURES.md) as the source of truth for current state, and the **updated capability table at the bottom of this file** for the final summary.

# SANDBOX AUDIT — OpenShift AI 3.5 Demo Sandbox

**Cluster:** `api.ocp.tfmbf.sandbox2633.opentlc.com:6443`
**Audited as:** `admin` (cluster-admin confirmed via `oc auth can-i '*' '*' --all-namespaces` → `yes`)
**Audit date:** 2026-09-16
**Mode:** READ-ONLY. No resources were created, modified, deleted, scaled, or patched during this audit. One read-only HTTP query attempt was made against the deployed model's public route (see §11 — it timed out from this shell's network, not necessarily from the cluster).

---

## 1. OpenShift version

```
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.20.36    True        False         24h     Cluster version is 4.20.36
```

Single-node cluster (`ip-10-0-31-7`, control-plane+master+worker), AWS (`g6.8xlarge`), 25h old — a fresh temporary sandbox.

## 2. OpenShift AI version

**Red Hat OpenShift AI 3.5.0** (`rhods-operator.3.5.0`), CSV phase `Succeeded`, upgraded from 3.4.3. Release name reported by the `DataScienceCluster` status: `OpenShift AI Self-Managed`, version `3.5.0`.

## 3. Installed operators (subscriptions)

| Namespace | Operator | Channel | Purpose |
|---|---|---|---|
| `redhat-ods-operator` | `rhods-operator` (3.5.0) | stable-3.x | Core RHOAI |
| `nvidia-gpu-operator` | `gpu-operator-certified` (v25.3) | v25.3 | GPU support |
| `openshift-nfd` | `nfd` | stable | Node Feature Discovery (GPU labeling) |
| `openshift-operators` | `authorino-operator` | stable | Auth policy engine (used by KServe auth) |
| `openshift-operators` | `openshift-pipelines-operator-rh` | latest | Tekton, backs AI Pipelines |
| `openshift-serverless` | `serverless-operator` | stable | Knative, backs KServe serverless mode |
| `openshift-jobset-operator` | `job-set` | stable-v1.0 | Backs Kubeflow Trainer |
| `keycloak` | `rhbk-operator` | stable-v26.4 | Red Hat Build of Keycloak (present but not confirmed wired into RHOAI auth) |
| `cert-manager-operator` | `openshift-cert-manager-operator` | stable-v1 | Certificates |

All CSVs cluster-wide: **`Succeeded`**. No failed install plans, no pending operators.

## 4–6. DataScienceCluster (`default-dsc`) and DSCInitialization (`default-dsci`)

`default-dsc` status: `Ready = True`, `phase: Ready`. Full component matrix (this is the ground truth for "what's real" — ignore any dashboard UI cards that suggest otherwise):

| Component | managementState | Notes |
|---|---|---|
| `dashboard` | **Managed** | Ready |
| `workbenches` | **Managed** | Ready, namespace `rhods-notebooks` |
| `kserve` | **Managed** | Ready — vLLM, KServe v0.19.0, TGIS, Caikit, OVMS, MLServer all available as runtimes |
| `aipipelines` | **Managed** | Ready — Kubeflow Pipelines 2.16.0 |
| `modelregistry` | **Managed** | Ready — namespace `rhoai-model-registries` |
| `trustyai` | **Managed** | Ready — includes Guardrails orchestrator, LMEval, EvalHub |
| `ray` | **Managed** | Ready — KubeRay 1.4.2 |
| `trainer` / `trainingoperator` | **Managed** | Ready — Kubeflow Trainer/Training Operator |
| `feastoperator` | **Managed** | Ready — Feast 0.65.0 operator installed, **no FeatureStore instance created yet** |
| `llamastackoperator` | **Managed** (spec) | Status object empty `{}` — **no `LlamaStackDistribution` CRD registered on the cluster**. Effectively inert. |
| `modelsAsAService` (MaaS) | **Removed** | `ModelsAsAServiceReady=False, reason=Removed` |
| `kserve.modelsAsService` (sub-field) | **Removed** | Same |
| `ogx` | **Removed** | `OGXReady=False, reason=Removed` |
| `mlflowoperator` | **Removed** | `MLflowOperatorReady=False, reason=Removed` |
| `mcplifecycleoperator` | **Removed** | `MCPLifecycleOperatorReady=False, reason=Removed` |
| `kueue` | **Removed** | |
| `sparkoperator` | **Removed** | |
| `aigateway` / `batchGateway` | **Removed** | |
| `kserve.wva` (workload variant autoscaler) | **Removed** | |

Also flagged in DSC conditions (informational, not errors):
- `KserveLLMInferenceServiceDependencies = False`: **Red Hat Connectivity Link (Kuadrant) is not installed** → no rate-limiting/quota policies possible → this is *why* MaaS governance features can't work here even if MaaS were Managed.
- `KserveLLMInferenceServiceWideEPDependencies = False`: LeaderWorkerSet not installed either.

`DSCInitialization` (`default-dsci`): `Ready = True`. `applicationsNamespace: redhat-ods-applications`, `monitoring: Managed` but **Metrics/Traces/Alerting are NOT configured** (`MonitoringStackAvailable=False`, `TempoAvailable=False`, `AlertingAvailable=False`) — so no Grafana/Perses dashboards or traces are usable for a demo.

## 7. Nodes / CPU / RAM

1 node only (single-node OpenShift):

| Node | CPU | RAM | GPU |
|---|---|---|---|
| `ip-10-0-31-7` (g6.8xlarge) | 32 cores | ~127 GiB | 1× `nvidia.com/gpu` |

## 8. Accelerators / GPUs

**1× NVIDIA L4 GPU** (23 GiB VRAM, Ada Lovelace, compute capability 8.9), MIG not capable, no sharing strategy, `nvidia.com/gpu.replicas: 1`. Driver 580.82.07, CUDA 13.0 — fully functional, currently consumed by the pre-deployed `llama-32-3b-instruct` model (see §17).

## 9. GPU operators / device plugins

NVIDIA GPU Operator fully deployed and healthy in `nvidia-gpu-operator` namespace: driver daemonset, device-plugin, DCGM + DCGM exporter, container-toolkit, GFD, node-status-exporter, operator-validator — **all `Running`/`Completed`**, 0 restarts. NFD (Node Feature Discovery) also healthy and is what's labeling the GPU node.

## 10. Hardware Profiles

Two `HardwareProfile` CRs (`infrastructure.opendatahub.io/v1`) in `redhat-ods-applications`:

| Name | CPU | Memory | GPU | Used by |
|---|---|---|---|---|
| `default-profile` *(unnamed default)* | 1–4 | 2–8 Gi | none | — |
| `gpu-profile` | 1–8 | 1–16 Gi | 1–4× `nvidia.com/gpu` | **Already used by the existing `llama-32-3b-instruct` InferenceService** |

## 11. Existing OpenShift AI projects

No namespace carries the `opendatahub.io/dashboard=true` label (i.e., **no project has been created through the RHOAI dashboard "Data Science Projects" flow yet**). However, one plain namespace exists with a real deployed model:

- **`my-first-model`** — created 24h ago, contains a running KServe `InferenceService`. It is *not* currently registered as a Dashboard "Data Science Project" (missing the dashboard label), so the Data Scientist persona will likely need to either adopt/label it or create a fresh project.

## 12. Existing Workbenches

**None.** `oc get notebooks -A` → no resources. `rhods-notebooks` namespace exists but is empty. The Data Scientist persona will need to create one live.

## 13. Existing Data Science Pipelines

**None.** No `DataSciencePipelinesApplication` (DSPA) CR anywhere, no Tekton `PipelineRun`s related to AI Pipelines. The pipelines operator/controller is healthy and ready to use, but no pipeline server has been provisioned in any project yet.

## 14. Existing Connections / Secrets

No dashboard "Connection" secrets exist (`opendatahub.io/connection-type-*` annotations not found on any project secret). The only model-related secret is `llama-32-3b-instruct` (Opaque, in `my-first-model`) which backs the InferenceService's `opendatahub.io/connections` annotation — this is the OCI/modelcar reference, not an S3 connection.

## 15. Existing object storage

**None found.** No MinIO/NooBaa/ODF pods or services anywhere in the cluster. `my-first-model`'s model was pulled via `storageUri: oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct` (OCI modelcar image), **not S3** — so no object storage was needed for that model and none is provisioned for a pipeline/RAG use case either.

## 16. Existing PostgreSQL / pgvector / vector databases

Two Postgres instances exist, **neither is a general-purpose/vector DB you should reuse**:
- `openshift-pipelines/tekton-results-postgres-0` — internal Tekton Results store.
- `rhoai-model-registries/model-catalog-postgres` — internal backing store for the RHOAI Model Catalog UI.

**No pgvector extension, no standalone vector database instance exists.** The dashboard's "Resources" catalog lists an **EDB Postgres AI / Pgvector** card, but it is purely a documentation/marketing pointer (`third party support`, external `docsLink`/`getStartedLink`, no deployable YAML, no `route`) — clicking it does not install anything.

## 17. Existing models

**One real, working, GPU-backed model:**

| Field | Value |
|---|---|
| Namespace | `my-first-model` |
| InferenceService | `llama-32-3b-instruct` |
| Model | Llama 3.2 3B Instruct, served via **vLLM** (`--dtype=half`, `--max-model-len=20000`, `--gpu-memory-utilization=0.95`, tool-calling enabled with llama3.2 json template) |
| Runtime image | `registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.2.4` (**Red Hat AI Inference Server**, i.e. supported vLLM, not a random community image) |
| Status | `Ready=True`, `activeModelState=Loaded`, `PredictorReady=True`, pod `3/3 Running`, 0 restarts, 24h uptime |
| Hardware | 1× GPU, `gpu-profile` hardware profile |
| Auth | `security.opendatahub.io/enable-auth: "false"` (open endpoint, no token needed) |
| API | OpenAI-compatible (`protocolVersion: v2`, `/v1/chat/completions`, `/v1/models`) |
| Exposure | `HTTPRoute` `llama-32-3b-instruct-route` on Gateway `openshift-ai-inference`, hostname `inference-gateway.apps.ocp.tfmbf.sandbox2633.opentlc.com`, **requires header `X-Model: llama-32-3b-instruct`** |

**This is your ready-made "deployed LLM" for the Data Scientist persona.** No route was reachable from *this terminal* when tested (see §Connectivity note below) — verify from a browser or `oc port-forward` before the live demo.

## 18. Existing KServe deployments

Same as §17 — exactly one `InferenceService`, `llama-32-3b-instruct`, deployment mode `Standard`, no other InferenceServices anywhere on the cluster.

## 19. Existing ServingRuntimes

One project-scoped `ServingRuntime`: `llama-32-3b-instruct` in `my-first-model`, template `vllm-cuda-runtime-template` ("vLLM NVIDIA GPU ServingRuntime for KServe"), `opendatahub.io/serving-runtime-scope: global`. Standard out-of-the-box templates (vLLM, OVMS, Caikit, MLServer, TGIS...) are available cluster-wide via RHOAI's built-in templates (confirmed via DSC `kserve` release list) even though only this one instance is deployed.

## 20. Existing Red Hat AI Inference Server / vLLM containers

Confirmed: the running model uses `registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.2.4` — this **is** Red Hat AI Inference Server (RHAIIS), Red Hat's supported vLLM distribution. No other vLLM/RHAIIS containers are running elsewhere.

## 21. MaaS status and configuration

- **Backend: `Removed`** at the `DataScienceCluster` level (`modelsAsAService`, and the `kserve.modelsAsService` sub-component). No MaaS-specific CRDs exist on the cluster (checked `oc get crd | grep -i maas` → nothing beyond the naming inside DSC status fields).
- **UI: present but non-functional.** A `maas-ui` pod (`registry.redhat.io/rhoai/odh-mod-arch-maas-rhel9`) is `Running` in `redhat-ods-applications`, and `OdhDashboardConfig.spec.dashboardConfig.modelAsService: true`. This means **the "Models as a Service" nav entry will likely appear in the dashboard**, but since the backing component is `Removed`, it should be expected to show empty/error/"not configured" state.
- **Verdict: MaaS is NOT available in this sandbox as a working capability.** Do not promise or attempt to demo MaaS subscription/governance flows here without first enabling the component (Phase 5 candidate, out of scope for now).

## 22. MaaS subscriptions / authorization policies

- No `AuthConfig` (Authorino) instances exist anywhere (`oc get authconfig -A` → none), despite the `authorino-operator` being installed.
- **Red Hat Connectivity Link (Kuadrant) is explicitly reported as "not installed"** in the DSC `KserveLLMInferenceServiceDependencies` condition — this is the component that would provide rate-limiting/quota/subscription enforcement for MaaS. Its absence is consistent with MaaS being `Removed`.
- **Verdict: no governance/subscription layer exists or can be demoed today.**

## 23. OGX availability and existing OGXServer resources

> **Superseded — see UPDATE 3 at the top of this file.** This section reflects the original point-in-time read-only audit only. OGX is now `Managed`/`Ready`; the root cause (conflict with `llamastackoperator`) and fix are documented in `ENABLED-FEATURES.md` §1.

- **`Removed`** at DSC level (`OGXReady=False, reason=Removed`).
- No OGX-related CRDs found anywhere on the cluster (`oc get crd | grep -i ogx` → nothing).
- **Verdict: OGX is NOT available in this sandbox.** No `OGXServer` resource type even exists to create.

## 24. MLflow availability and instances

- **`Removed`** at DSC level (`MLflowOperatorReady=False, reason=Removed`). No MLflow CRDs on the cluster.
- **UI card present, non-functional:** dashboard `OdhApplication` "MLflow" exists (`category: Red Hat managed`, `internalRoute: mlflowExperiments`) — this is the dashboard's built-in "Experiments" nav concept, but with no MLflow backend deployed it has nothing to show.
- **Verdict: MLflow is NOT available today.** Could be enabled later (Phase 5) by setting `mlflowoperator.managementState: Managed` in the DSC — but that is a cluster mutation, deferred until you approve it.

## 25. TrustyAI availability

- **`Managed`, `Ready=True`.** Operator (`trustyai-service-operator-controller-manager`) running healthy. Includes: TrustyAI service, LMEval driver/job, **Guardrails orchestrator (fms-guardrails-orchestrator)**, builtin regex detectors, sidecar gateway, EvalHub.
- **No `TrustyAIService`, `GuardrailsOrchestrator`, `NemoGuardrail`, `LMEvalJob`, or `EvalHub` instances exist yet** — the component is ready but nothing has been configured/instantiated.
- **Verdict: READY for configuration**, but needs a `TrustyAIService`/`GuardrailsOrchestrator` CR to actually show anything — good candidate as the "optional final extension" per your storyline, not for the core 20-minute path.

## 26. NeMo Guardrails availability

CRD `nemoguardrails.trustyai.opendatahub.io` exists (part of the TrustyAI component), **no instances created**. Same verdict as §25 — technically available, needs configuration, keep as optional extension only.

## 27. MCP Catalog availability

- No MCP-specific CRDs found (`oc get crd | grep -i mcp` → only an unrelated `machineconfigpools` false match).
- `mcplifecycleoperator` is explicitly **`Removed`** at the DSC level.
- No dedicated "MCP" UI pod found among the dashboard micro-frontends (`agent-ops-ui`, `gen-ai-ui`, `autorag-ui`, `automl-ui`, `eval-hub-ui`, `maas-ui`, `model-registry-ui` are present; nothing named for MCP specifically).
- **Verdict: NOT AVAILABLE.** MCP Catalog cannot be demoed as a working, clickable feature in this sandbox. At most you can *talk about* MCP conceptually using the "Agentic Starter Kits" dashboard card (see §29) as a visual aid.

## 28. MCP Lifecycle Operator availability

**`Removed`** at DSC level, no CRDs. Confirmed **NOT AVAILABLE** — consistent with §27.

## 29. Agents Catalog availability

- No dedicated "Agents Catalog" backend CRD exists.
- There **is** an `agent-ops-ui` micro-frontend pod running, and a dashboard catalog card **"Agentic Starter Kits"** (`opendatahub.io/categories: Agent Templates,Getting started`, provider Red Hat, support: community) pointing to `github.com/red-hat-data-services/agentic-starter-kits` (LangGraph/LlamaIndex/CrewAI/AutoGen/Langflow/Google ADK/A2A templates). **This card has `hidden: true`** — meaning it is currently suppressed from the dashboard navigation by default.
- **Verdict: NOT AVAILABLE as a live, clickable "Agents Catalog" experience.** The GitHub starter-kit repo can be referenced verbally/via a browser tab as supporting material, but there is nothing to click inside the console today.

## 30. Feature Store / Feast availability

- **`Managed`, `Ready=True`.** Feast operator (v0.65.0) fully running (`feast-operator-controller-manager`, `opendatahub-feast-operator`), CRD `featurestores.feast.dev/v1` registered.
- **No `FeatureStore` instance created.** Not relevant to your RAG storyline — skip entirely unless you want a stretch goal.

---

## Broken resources / health sweep

- **No CrashLoopBackOff pods anywhere in the cluster.**
- Only 2 non-Running pods cluster-wide, both benign leftover `installer-*` pods from control-plane static-pod revisions in `openshift-kube-controller-manager` / `openshift-kube-scheduler` (`Error` status, 0 restarts, expected artifacts, not user-facing).
- Several RHOAI controller pods show 6–14 restarts (e.g. `dashboard-operator`, `feast-operator-controller-manager`, `kserve-controller-manager`, `trustyai-service-operator-controller-manager`, `kuberay-operator`, `llmisvc-controller-manager`) — **all are currently `1/1 Running`**, and restart timestamps cluster around "~89m/~6h ago," consistent with a single node reboot/control-plane event, not an active crash loop. Not a demo risk as-is, but worth a final `oc get pods -n redhat-ods-applications` sanity check right before you go live.
- No failed `ClusterServiceVersion`s, no stuck `InstallPlan`s.
- Storage: `gp3-csi` (default) and `gp2-csi` StorageClasses both healthy, dynamic provisioning via AWS EBS CSI — fine for a Workbench PVC or a self-hosted Postgres+pgvector PVC.

## Connectivity note (read-only test performed)

A single `curl` to the model's public route (`https://inference-gateway.apps.ocp.tfmbf.sandbox2633.opentlc.com/v1/models`) **timed out at the TLS handshake stage** from this terminal, even though DNS resolved correctly to the AWS ELB IPs. The OpenShift API (port 6443) is reachable fine from here. This is most likely an **egress restriction of this local/agent shell environment**, not proof the route is broken on the cluster side — the `Gateway`/`HTTPRoute`/`InferenceService` objects all report healthy/`Ready` status. **Action for you:** verify `https://inference-gateway.apps.ocp.tfmbf.sandbox2633.opentlc.com/v1/chat/completions` (with header `X-Model: llama-32-3b-instruct`) directly from your own browser/laptop terminal before relying on it live.

---

## CAPABILITY TABLE — FINAL STATE (2026-09-16, post-enablement)

This supersedes the original table below it. See `ENABLED-FEATURES.md` for exact commands/YAML/rollback for every ✅ row that changed from the original audit.

| Capability | Available? | Current state | Existing resource | Safe for live demo? | Action needed |
|---|---|---|---|---|---|
| OpenShift AI Operator | ✅ Yes | 3.5.0, Succeeded | `rhods-operator.3.5.0` | **READY** | None |
| DataScienceCluster | ✅ Yes | Ready, well-documented component matrix | `default-dsc` | **READY** | None — great visual for admin persona |
| GPU / Accelerator | ✅ Yes | 1× NVIDIA L4, healthy operator | node `ip-10-0-31-7` | **READY** | None |
| Hardware Profiles | ✅ Yes | 2 profiles, `gpu-profile` in active use | `gpu-profile`, `default-profile` | **READY** | None |
| **Models-as-a-Service (MaaS)** | ✅ **Yes (now enabled)** | `aigateway.modelsAsAService: Managed`, `Ready`. Existing `llama-32-3b-instruct` reused via `ExternalProvider`→`ExternalModel`→`MaaSModelRef`, governed by `MaaSAuthPolicy`+`MaaSSubscription`. | `models-as-a-service` namespace, `maas-default-gateway` | **READY** | None — verify `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com` from a browser before going live |
| **Governance/subscriptions (Kuadrant/Authorino)** | ✅ **Yes (now enabled)** | RHCL/Kuadrant installed in `kuadrant-system`, `Kuadrant` CR `Ready`. `MaaSAuthPolicy` (subjects: `system:authenticated`) + `MaaSSubscription` (100k tokens/hr) both `Ready` | `kuadrant-system` ns | **READY** | None |
| OpenShift AI Project (Dashboard) | ⚠️ Partial | No dashboard-labeled project exists yet | `my-first-model` (unlabeled namespace) | **NEEDS CONFIGURATION** | Create a proper Dashboard project (new, or label `my-first-model`) |
| Connections | ⚠️ Partial | Feature ready, none created | — | **NEEDS CONFIGURATION** | Create 1 connection (e.g. URI-type pointing at model endpoint, or S3 if you stand up storage) |
| Object storage / S3 | ❌ No | None deployed | — | **NOT AVAILABLE** | Skip, or deploy MinIO if truly needed (extra risk) |
| Vector DB (pgvector) | ❌ No | Not deployed; dashboard card is doc-only | — | **NOT AVAILABLE (as-is)** | **NEEDS CONFIGURATION** if you want RAG — deploy a lightweight Postgres+pgvector via plain YAML |
| Workbench | ⚠️ Partial | Component ready, 0 instances | `rhods-notebooks` namespace (empty) | **NEEDS CONFIGURATION** | Create 1 workbench live during the demo |
| AI Pipelines | ⚠️ Partial | Component ready, no DSPA, no pipelines | — | **NEEDS CONFIGURATION** | Create a DSPA + a minimal ingestion pipeline if you want to show it live |
| Deployed LLM / vLLM endpoint | ✅ Yes | Running, Ready, GPU-backed, RHAIIS/vLLM | `llama-32-3b-instruct` in `my-first-model` | **READY** (pending browser connectivity check) | Verify route reachable from your presenting machine before going live |
| **OGX Operator** | ✅ **Yes (now enabled)** | `ogx: Managed`, `OGXReady=True`. Was blocked by `llamastackoperator: Managed` (deprecated, renamed to OGX) — fixed by removing it. | `ogx-k8s-operator-controller-manager`, `opendatahub-ogx-operator` pods | **READY (operator only)** | No `OGXServer` CR created yet — needs external PostgreSQL 14+; create only with your approval |
| **MCP Catalog** | ⚠️ **Partial (catalog/browse only)** | `mcpCatalog`+`mcpRegistry` dashboard flags `true`; MCP Lifecycle Operator intentionally **not installed** (needs OCP 4.22+, we're on 4.20.36) → `MCPServer` CRD absent → "Deploy" button disabled by Red Hat's own documented graceful-degradation design | dashboard nav only | **READY (as browse-only)** | Show "AI hub → MCP servers" catalog/registry tabs; explicitly say "Deploy" is disabled because of the OpenShift version, not broken |
| **Agents Catalog** | ✅ **Yes (nav enabled)** | `agentsCatalog: true`. Developer Preview, curated templates/links only, no runtime backend | dashboard nav only | **READY (Developer Preview, no live runtime)** | Show "AI hub → Agents"; say explicitly there's no deploy button, it's a template catalog |
| **MLflow** | ✅ **Yes (now enabled)** | `mlflowoperator: Managed`, `MLflow` CR `mlflow` `Available=True`, SQLite+PVC backend | `mlflow` deployment in `redhat-ods-applications` | **READY** | None — dashboard → Applications → MLflow |
| TrustyAI / Guardrails | ⚠️ Partial | Component ready + `guardrails` dashboard flag now `true`, 0 `GuardrailsOrchestrator` instances | — | **NEEDS CONFIGURATION** (optional) | Only attempt as stretch/extension |
| Feast / Feature Store | ⚠️ Partial | Component ready, 0 instances | — | **NOT NEEDED** | Skip — not in your storyline |
| Model Registry | ✅ Yes | Ready, `default-modelregistry` instance exists | `rhoai-model-registries` ns | **READY** | Could optionally show, not required |

---

## Recommended richest stable demo path (20–25 min), updated

With MaaS, MLflow, Agents Catalog nav, and MCP Catalog (browse-only) now genuinely working, the richest *safe* storyline is:

1. **Admin:** Operator → DataScienceCluster (show the full component matrix, point out `ogx: Managed` — recently renamed from Llama Stack — and `mcplifecycleoperator: Removed` as an "OpenShift-version-gated, this build" talking point) → GPU/Hardware Profile → **Models-as-a-Service governance** (`MaaSAuthPolicy`, `MaaSSubscription`, token rate limits) → hand over.
2. **Data Scientist:** show the existing `llama-32-3b-instruct` model, now also reachable as a **governed MaaS endpoint** (`https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`) → create/adopt a Dashboard project → create a Connection → create a Workbench → connect it to **MLflow** (`opendatahub.io/mlflow-instance` annotation) → deploy a small Postgres+pgvector (plain YAML) as the vector store → ingest + query for a simple RAG answer, logging the run to MLflow → browse **AI hub → MCP servers** (catalog/registry, explain "Deploy" is disabled due to OpenShift version) and **AI hub → Agents** (Developer Preview template catalog) as forward-looking closing points.
3. **Still not created (needs your approval), but the operator is ready:** the actual `OGXServer` instance — creating one needs a reachable external PostgreSQL 14+, which is not yet provisioned in this sandbox. Once approved, the Gen AI Studio Playground (`agentConfigManagement`, `agentOps`, `genAiTracing`, `promptManagement` — all now nav-enabled) would have real content to show instead of an empty state.

Full per-component config, verification evidence, dashboard click-paths and rollback commands: see `ENABLED-FEATURES.md`.
