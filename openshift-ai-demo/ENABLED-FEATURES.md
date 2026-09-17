# ENABLED FEATURES — OpenShift AI 3.5 Demo Sandbox

Tracks every configuration change applied to this sandbox during the enablement pass on 2026-09-16, in the order it was applied. Each entry has the exact command/YAML used, verification performed, resulting UI location, current health, and a rollback command.

Legend: ✅ Enabled & healthy · ⚠️ Enabled, partial/limited · ❌ Attempted, rolled back (not available)

> **Correction log:** OGX (§1) was initially misdiagnosed as unavailable on this build. It was actually blocked by the pre-existing `llamastackoperator: Managed` setting — OGX is the renamed successor to Llama Stack per official Red Hat docs, and the two cannot coexist as `Managed`. Removing `llamastackoperator` fixed it in under a minute. This also unblocked the four Gen AI Studio flags in §5 that were originally left disabled pending OGX.

---

## 1. OGX — ✅ Enabled and healthy (initial failure diagnosed and corrected — see below)

**Initial attempt failed** (`ogx: Managed` alone — `OGXReady` never turned `True`, no CRD, no pod). I initially concluded this was a platform gap in this specific build. **That conclusion was wrong**, as pointed out and confirmed against official Red Hat documentation.

**Root cause (per official docs):** Per [Chapter 1. Llama Stack to OGX migration](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/working_with_ogx/llama-stack-to-ogx-migration_rag):

> Starting in OpenShift AI version 3.5EA1, Llama Stack is being fully renamed to OGX... In order to migrate to the newly named `ogx-operator`, you must **remove the Llama Stack Operator** and create new `OGXServer` custom resources.
>
> 1. Remove the Llama Stack Operator: `dsc.spec.components.lls = "Removed"`
> 2. Install the new OGX operator: `dsc.spec.components.ogx = "Managed"`

This cluster had `llamastackoperator: Managed` set (a pre-existing, inert setting). Live schema confirms it: `oc explain datasciencecluster.spec.components.llamastackoperator` → *"LlamaStack Operator component configuration. **Deprecated: Use OGX instead.**"* OGX and Llama Stack are the same operator lineage (renamed) and cannot both be `Managed` on this build.

**DSC configuration applied (corrected sequence):**
```bash
# Step 1: remove the deprecated/conflicting Llama Stack component
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Removed"}}}}'
# (confirmed harmless: no LlamaStackDistribution CRD/instances existed on this cluster to migrate)

# Step 2: enable OGX
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"ogx":{"managementState":"Managed"}}}}'
```

**What happened:** Reconciled in under 60 seconds this time.

**Verification performed:**
```
$ oc get datasciencecluster default-dsc -o jsonpath='{.status.installedComponents.ogx}'
```
This exact path from the original ask **does not exist** on this DSC API version (`datasciencecluster.opendatahub.io/v2` uses `.status.components`, not `.status.installedComponents`) — used the equivalent:
```
$ oc get datasciencecluster default-dsc -o jsonpath='{.status.components.ogx}'
{"managementState":"Managed"}
$ oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[?(@.type=="OGXReady")]}{.status} {.reason}{end}'
True AllDependentsHealthy
```
- CRDs now registered: `ogxs.components.platform.opendatahub.io` (platform component) **and** `ogxservers.ogx.io` (the actual `OGXServer` CR you'd create to deploy an instance).
- Pods in `redhat-ods-applications`: `ogx-k8s-operator-controller-manager-*` (`1/1 Running`) and `opendatahub-ogx-operator-*` (`1/1 Running`).
- `DataScienceCluster` `phase: Ready`, `Ready=True`, full cluster health sweep clean (0 CrashLoopBackOff, 0 Pending, 0 failed CSVs — only the 2 pre-existing benign `installer-*` pods remain, unrelated).
- **No `OGXServer` CR created** — per the original instruction, intentionally deferred pending your approval.

**Supporting resources:** none beyond the two DSC component flags above — no `OGXServer`, no PVC, no PostgreSQL yet.

**Resulting UI location:** `Operators → Installed Operators → Red Hat OpenShift AI → Data Science Cluster → default-dsc` now shows `ogx: Managed`. The Gen AI Studio Playground nav entries (§5) are now backed by a real operator, but will likely show an empty "create your first server" state until an `OGXServer` CR exists — that CR needs a reachable external PostgreSQL 14+, which this sandbox does not have provisioned yet.

**Current health:** Fully healthy, `Ready=True` throughout. `llamastackoperator` cleanly retired with zero data loss (nothing existed to migrate).

**Demo click path:** Admin: `Operators → Red Hat OpenShift AI → Data Science Cluster → default-dsc` YAML, point at `ogx: Managed` and `llamastackoperator: Removed` — good talking point on the Llama Stack→OGX rename. Do not click into the Playground/OGX pages expecting live content yet — no `OGXServer` instance exists, so there is nothing to show there until you approve creating one.

**Rollback commands:**
```bash
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"ogx":{"managementState":"Removed"}}}}'
# only if you also want the old (deprecated, currently inert) Llama Stack component back:
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Managed"}}}}'
```
---

## 2. MLflow — ✅ Enabled and healthy

**DSC configuration applied:**
```yaml
spec:
  components:
    mlflowoperator:
      managementState: Managed
```
Applied via:
```bash
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'
```

**Supporting resources created** (`yaml/mlflow-cr.yaml`):
```yaml
apiVersion: mlflow.opendatahub.io/v1
kind: MLflow
metadata:
  name: mlflow          # cluster-scoped, must be named "mlflow"
spec:
  storage:
    accessModes: [ReadWriteOnce]
    resources:
      requests:
        storage: 10Gi
  backendStoreUri: "sqlite:////mlflow/mlflow.db"
  artifactsDestination: "file:///mlflow/artifacts"
  serveArtifacts: true
```
This is Red Hat's own documented **"Minimal development or test deployment"** example — SQLite backend store + PVC-backed file artifact storage. Deliberately chosen over the PostgreSQL/S3 example to avoid adding external dependencies to a temporary sandbox.

**What it created automatically:**
- PVC `mlflow-pvc` (10Gi, `gp3-csi`, `Bound`)
- Migration Job `mlflow-mg-3140-g1` → `Completed`
- Deployment `mlflow` (tracking server, `2/2 Running`)
- `HTTPRoute` `mlflow` in `redhat-ods-applications`
- Service `mlflow` (ClusterIP :8443)
- The RHOAI Operator automatically set `MLFLOW_ENABLED=true` on the notebook controller and configured `GATEWAY_URL` — no manual notebook-controller edits needed.

**Verification performed:**
- `MLflowOperatorReady=True`, `MLflow` CR `Available=True` conditions.
- `mlflow-ui` micro-frontend log line: `"MLflow CR discovered at runtime" url=https://mlflow.redhat-ods-applications.svc:8443/mlflow` (previously logged `503`/"no MLflow CR found" before the CR existed).
- No errors in tracking-server pod logs.
- `DataScienceCluster` `Ready=True` maintained throughout (one transient dashboard pod rollout, self-healed in ~90s).

**Resulting UI location:** RHOAI Dashboard → **Applications** menu → **MLflow**, or the dedicated Experiments/MLflow tab (`internalRoute: mlflowExperiments`). Click **Start Demo** on first visit to load sample runs if you want data to show without waiting for a real experiment.

**Connecting a Workbench to this MLflow instance** (no cluster changes needed — this is a per-workbench, data-scientist-level step during the demo):
1. Create/edit a Workbench in the OpenShift AI dashboard.
2. The dashboard automatically offers to attach the `opendatahub.io/mlflow-instance` annotation (pointing at CR name `mlflow`) when MLflow is enabled platform-wide — no manual tracking URI, token, or RBAC setup required.
3. Once attached, the notebook controller injects `MLFLOW_TRACKING_URI` and related env vars automatically; `import mlflow; mlflow.autolog()` in the notebook will log straight to this instance.

**Current health:** Fully healthy.

**Rollback command:**
```bash
oc delete mlflows.mlflow.opendatahub.io mlflow
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Removed"}}}}'
# PVC mlflow-pvc will be left orphaned by the delete; remove separately if desired:
oc delete pvc mlflow-pvc -n redhat-ods-applications
```

---

## 3. Models-as-a-Service — ✅ Enabled, governed, and verified end-to-end

**Prerequisite inspection (performed before touching anything):**

| Prerequisite | Status on this cluster |
|---|---|
| Gateway API (CRDs, `v1`/`v1beta1`) | ✅ Present (native to OCP 4.20) |
| `GatewayClass` for `openshift.io/gateway-controller` | ✅ `data-science-gateway-class`, `openshift-ai-inference` both `Accepted=True` |
| A `maas-default-gateway` Gateway in `openshift-ingress` | Created automatically by the `aigateway` component controller once enabled — now `Programmed=True`, AWS ELB address, TLS via `cert-manager-ingress-cert` (`mode: Terminate`) |
| Red Hat Connectivity Link (RHCL) — provides Kuadrant `AuthPolicy`/`TokenRateLimitPolicy` CRDs | **Installed** — `rhcl-operator` subscription in `kuadrant-system` (already present in the `redhat-operators` catalog, no new CatalogSource needed). Supported on OCP 4.19–4.22 (we're on 4.20.36 ✅). |
| Authorino | **Resolved without conflict.** RHCL deployed its own `authorino` instance inside `kuadrant-system` (1/1 Running). The pre-existing **standalone** `authorino-operator.v1.4.3` (`openshift-operators` OperatorGroup) is still installed but has **0 `Authorino` CR instances of its own** — verified no competing `ValidatingWebhookConfiguration`/`MutatingWebhookConfiguration` named for Authorino exist, and cluster-wide pod health/CSV health stayed 100% clean through and after the install. No conflict materialized. |
| cert-manager (for TLS policies) | ✅ Already installed, used directly by the new Gateway's TLS |
| DNS Operator (installed automatically by RHCL) | Installed as part of RHCL (`dns-operator-controller-manager`, 1/1 Running in `kuadrant-system`) — accepted as part of the RHCL blast radius |
| Existing model to reuse | ✅ `llama-32-3b-instruct` in `my-first-model` — **reused as-is, no second model deployed** |

**DSC configuration applied:**
```bash
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"aigateway":{"managementState":"Managed","modelsAsAService":{"managementState":"Managed"}}}}}'
```
⚠️ **Important correction vs. the field path in common docs/examples:** the real, effective spec path in this exact 3.5.0 build is `spec.components.aigateway.modelsAsAService.managementState`. The older-looking path `spec.components.kserve.modelsAsService.managementState` **also exists in the schema but stays `Removed` and does nothing for MaaS** — it's a legacy/no-op field on this build. Verified live: `AIGatewayReady=True`, `ModelsAsAServiceReady=True`, message `"modelsAsAService is Managed and deployments are available"`.

**What it created automatically:** `ai-gateway-operator` pod, `maas-controller`, `maas-postgres`, `maas-api` (all `redhat-ods-applications`), Gateway `maas-default-gateway`, `AuthPolicy maas-gateway-auth`, `TokenRateLimitPolicy gateway-default-deny` (default-deny until a subscription grants access), `Kuadrant` CR (`kuadrant-system`, `Ready`), `AITenant models-as-a-service` (`ai-tenants` ns) → `MaasTenantConfig default-tenant` (`models-as-a-service` ns) — both `Ready`/`Active`.

**Reusing the existing `llama-32-3b-instruct` model (supporting resources, `yaml/maas-reuse-llama-model.yaml`):**

The native MaaS path (`MaaSModelRef` → `kind: LLMInferenceService`) only supports the newer `LLMInferenceService` CRD, not the classic `InferenceService` our model uses. To reuse it **without redeploying**, it's wired in as a self-hosted "external" OpenAI-compatible provider — this is exactly what `ExternalProvider`/`ExternalModel` are designed for:

```yaml
apiVersion: v1
kind: Secret
metadata: {name: llama-32-3b-instruct-external-auth, namespace: models-as-a-service}
type: Opaque
stringData: {api_key: "not-used-backend-has-no-auth"}   # backend has enable-auth: "false"; required field only
---
apiVersion: inference.opendatahub.io/v1alpha1
kind: ExternalProvider
metadata: {name: llama-32-3b-instruct-provider, namespace: models-as-a-service}
spec:
  provider: self-hosted-vllm
  endpoint: llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local   # in-cluster Service, no scheme/path allowed by CRD validation
  auth: {type: apikey, secretRef: {name: llama-32-3b-instruct-external-auth}}
---
apiVersion: inference.opendatahub.io/v1alpha1
kind: ExternalModel
metadata: {name: llama-32-3b-instruct-external, namespace: models-as-a-service}
spec:
  modelName: llama-32-3b-instruct
  externalProviderRefs:
    - ref: {name: llama-32-3b-instruct-provider}
      apiFormat: openai-chat
      path: /v1/chat/completions
      targetModel: llama-32-3b-instruct
      weight: 1
---
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSModelRef
metadata: {name: llama-32-3b-instruct-maas, namespace: models-as-a-service}
spec:
  modelRef: {kind: ExternalModel, name: llama-32-3b-instruct-external}
```

Plus governance (`yaml/maas-governance-llama.yaml`) — without this, `MaaSModelRef` sits in `Pending`/`Awaiting governance pairing` forever:

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata: {name: llama-32-3b-instruct-access, namespace: models-as-a-service}
spec:
  modelRefs: [{name: llama-32-3b-instruct-maas, namespace: models-as-a-service}]
  subjects: {groups: [{name: "system:authenticated"}]}   # smallest safe default: any logged-in OpenShift user, no new users/groups to create or clean up
---
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata: {name: llama-32-3b-instruct-subscription, namespace: models-as-a-service}
spec:
  owner: {groups: [{name: "system:authenticated"}]}
  priority: 1
  modelRefs:
    - name: llama-32-3b-instruct-maas
      namespace: models-as-a-service
      tokenRateLimits: [{limit: 100000, window: 1h}]
      billingRate: {perToken: "0"}
  tokenMetadata: {costCenter: demo, organizationId: rhoai-3-5-demo}
```

**Verification performed (final live status):**
- `ExternalProvider` → `Ready=True`, `"All resources created successfully"`
- `ExternalModel` → `Ready=True`, `"HTTPRoute created successfully"` (auto-created `llama-32-3b-instruct-external` HTTPRoute on `maas-default-gateway`)
- `MaaSModelRef` → **`RuntimeReady=True` ("Backend is healthy") + `GovernanceAttached=True` ("Active governance pairing found") + `Ready=True` ("Governed and runtime-healthy")**, `phase: Ready`, `endpoint: https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`
- `MaaSAuthPolicy` → `Ready=True`, no conflicting AuthPolicies on MaaS-managed HTTPRoutes
- `MaaSSubscription` → `Ready=True`, `tokenRateLimitStatuses[0].ready=true` (`maas-trlp-llama-32-3b-instruct-maas` accepted)
- `oc get pods -n kuadrant-system / redhat-ai-gateway-infra / redhat-ods-applications` → everything `Running`/`Completed`, 0 new restarts, `DataScienceCluster Ready=True` maintained throughout

**Resulting UI location:** RHOAI Dashboard → **AI hub → Models as a Service** should list `llama-32-3b-instruct` as a governed asset; **Gen AI Studio → AI asset endpoints** should show the MaaS endpoint. (Not click-verified in a browser from this environment — see connectivity note in `SANDBOX-AUDIT.md`; all backend conditions are confirmed `Ready` via the API.)

**Demo click path:** Admin: `OpenShift AI → Models as a Service → llama-32-3b-instruct` → point at Subscription (100k tokens/hr, `system:authenticated`) and AuthPolicy. Data Scientist: query `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com/v1/chat/completions` with an OpenShift user token as Bearer auth (governed path) vs. the original direct route (ungoverned) to contrast "before/after MaaS."

**Dashboard flags status:** `genAiStudio: true` and `modelAsService: true` were **already set** before this pass (pre-existing, UI-tab-only flags — now backed by a real component). `maasAuthPolicies` is confirmed via the live `OdhDashboardConfig` CRD schema (`oc explain`) to be **`DEPRECATED: This field is no longer used and will be removed in a future version`** — intentionally left unset; setting it would be a no-op.

**Current health:** Fully healthy, governed, and reachable per API status. `DataScienceCluster Ready=True` throughout.

**Rollback commands:**
```bash
# Remove the reuse-wiring and governance (additive resources only, does not touch llama-32-3b-instruct itself)
oc delete -f yaml/maas-governance-llama.yaml --ignore-not-found
oc delete -f yaml/maas-reuse-llama-model.yaml --ignore-not-found

# Disable MaaS component (leaves RHCL/Kuadrant installed; add a second command to remove RHCL too if desired)
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"aigateway":{"modelsAsAService":{"managementState":"Removed"}}}}}'

# Full RHCL/Kuadrant removal (only if you want to fully undo the operator install, not required to disable MaaS)
oc delete subscription rhcl-operator -n kuadrant-system
oc delete kuadrant kuadrant -n kuadrant-system
```

---

## 4. Agents Catalog — ✅ Enabled (Developer Preview, nav-only)

**Dashboard configuration applied:**
```yaml
spec:
  dashboardConfig:
    agentsCatalog: true
```
Applied via:
```bash
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{"spec":{"dashboardConfig":{"agentsCatalog":true}}}'
```

**Supporting resources:** none needed — this is a pure navigation-visibility flag, not tied to OGX/Playground per the documented flag description ("Shows the Agents Catalog page in the dashboard navigation menu").

**Resulting UI location:** **AI hub → Agents** in the left nav.

**Current health:** Dashboard pods stayed `3/3 Running` throughout, `DataScienceCluster` `Ready=True`.

**Demo click path:** Navigate to AI hub → Agents. Expect a Developer Preview banner and a catalog of agent templates/patterns (the "Agentic Starter Kits" content — LangGraph, LlamaIndex, CrewAI, AutoGen, Langflow, Google ADK, A2A, vanilla Python). There is **no deploy/runtime backend** behind this — it is a curated links/templates catalog, not a live agent runtime. Say so explicitly if asked.

**Rollback command:**
```bash
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{"spec":{"dashboardConfig":{"agentsCatalog":false}}}'
```

---

## 5. Gen AI Studio flags — ✅ All six requested flags now enabled (dependency was OGX, now resolved)

**Update:** Originally, `agentConfigManagement`, `agentOps`, `genAiTracing`, and `promptManagement` were left disabled because they're documented as living inside the Gen AI Studio Playground, which requires the OGX Operator — and OGX initially failed to enable (see §1). Once §1's real root cause (Llama Stack/OGX conflict) was fixed and OGX became genuinely healthy, this blocking dependency no longer applies, so all four are now enabled too.

| Flag | Action | Reason |
|---|---|---|
| `guardrails` | ✅ Enabled | Model-deployment-wizard guardrails config UI; backing component (`trustyai`) is `Managed`/`Ready`. Not part of the Playground. |
| `toolCalling` | ✅ Enabled | Model Catalog UI only (shows validated vLLM args); no runtime backend dependency at all. |
| `agentConfigManagement` | ✅ Enabled | Lives in the Gen AI Studio Playground; dependency (OGX Operator, §1) is now `Ready`. |
| `agentOps` | ✅ Enabled | Same — Gen AI Studio/Playground feature, OGX now healthy. |
| `genAiTracing` | ✅ Enabled | "Tracing support in the Gen AI Studio playground" — OGX dependency now satisfied. |
| `promptManagement` | ✅ Enabled | Lives in the Gen AI Studio Chat Playground; OGX dependency now satisfied, and the MLflow prompt registry backing it (§2) is also `Managed`/healthy. |

**Applied via:**
```bash
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge \
  -p '{"spec":{"dashboardConfig":{"guardrails":true,"toolCalling":true}}}'
# after OGX (§1) was fixed:
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge \
  -p '{"spec":{"dashboardConfig":{"agentConfigManagement":true,"agentOps":true,"genAiTracing":true,"promptManagement":true}}}'
```

**Resulting UI location:**
- `guardrails`: Model Serving deployment wizard → Advanced settings → Guardrails.
- `toolCalling`: AI hub → Catalog → any validated model → Model Details → "Validated Arguments"/"Tool Calling" panel.
- `agentConfigManagement`, `agentOps`, `genAiTracing`, `promptManagement`: Gen AI Studio → Playground (and its sub-tabs). **Important caveat:** the Playground itself needs an `OGXServer` CR to have any live content — none has been created yet (§1, intentionally deferred pending your approval, since it needs an external PostgreSQL 14+ that isn't provisioned in this sandbox). Expect an empty/"create your first server" state on these specific pages until that CR exists, not a broken page — the nav entries themselves are legitimate now.

**Current health:** No new pods, no rollout disruption, `Ready=True` maintained throughout both patches.

**Rollback command:**
```bash
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{"spec":{"dashboardConfig":{"guardrails":false,"toolCalling":false,"agentConfigManagement":false,"agentOps":false,"genAiTracing":false,"promptManagement":false}}}'
```


## 6. MCP — ⚠️ Catalog/registry browsing enabled; lifecycle intentionally NOT installed

Per your explicit instruction, the **MCP Lifecycle Operator was not installed** — Red Hat's own 3.4/3.5 docs confirm the MCP Catalog's "Deploy MCP server" action is hard-gated on the presence of the `MCPServer` CRD, which only the MCP Lifecycle Operator provides, and that operator's supported OpenShift baseline is beyond what this cluster (4.20.36) needs to be to run it safely per your stated 4.22+ constraint.

**Dashboard configuration applied:**
```yaml
spec:
  dashboardConfig:
    mcpCatalog: true
    mcpRegistry: true
```

**Verification of the "read-only/catalog-only" claim:** confirmed no `MCPServer`-type CRD exists on this cluster (`oc get crd | grep -i mcp` → nothing besides the unrelated `machineconfigpools` false match), and Red Hat's own MCP Lifecycle Operator blog post states: *"The catalog UI requires the presence of the MCPServer CRD... The 'Deploy MCP Server' button will be disabled when the MCP Server custom resource definition (CRD) is absent from the cluster."* This is exactly the "read-only/catalog mode" behavior you asked for — Red Hat designed it to degrade gracefully like this by default.

**Resulting UI location:** **AI hub → MCP servers** → Catalog tab (browse Red Hat, Red Hat Partner, and Other MCP servers, with a disabled "Deploy" action) and Registry tab (register externally-run MCP server metadata for use in the Gen AI Studio playground's MCP tool list — this doesn't deploy anything either, just records connection info).

Separately, and unrelated to the Lifecycle Operator: the **Gen AI Playground's own MCP server list** (a different, older mechanism, not gated by OpenShift version) is driven by a plain `ConfigMap` named `gen-ai-aa-mcp-servers` in `redhat-ods-applications` — administrators can register external MCP server URLs there for use in chat/tool-calling once the Playground itself is reachable. We did **not** create this ConfigMap since the Playground is not usable on this sandbox without OGX (see §5); documenting it here as a known, cluster-version-independent path if you enable OGX in a different sandbox later.

**Current health:** No pods created, `Ready=True` maintained.

**Rollback command:**
```bash
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{"spec":{"dashboardConfig":{"mcpCatalog":false,"mcpRegistry":false}}}'
```

---

## Summary of net changes (final, validated pass)

| Component | Before | After |
|---|---|---|
| `ogx` (DSC) | Removed | **Managed** ✅ — blocked by `llamastackoperator: Managed` (OGX supersedes/renames Llama Stack, docs require removing it first); fixed by removing `llamastackoperator`. `OGXReady=True`, CRDs `ogxs.components.platform.opendatahub.io` + `ogxservers.ogx.io` registered, operator pods `Running`. No `OGXServer` CR created yet (deferred pending approval). |
| `llamastackoperator` (DSC, deprecated) | Managed (pre-existing, inert) | **Removed** ✅ — cleanly retired, no `LlamaStackDistribution` instances existed to migrate |
| `mlflowoperator` (DSC) | Removed | **Managed** ✅ + `MLflow` CR `mlflow`, `Available=True` |
| `aigateway` / `aigateway.modelsAsAService` (DSC) | Removed | **Managed** ✅ — RHCL/Kuadrant/Authorino/Limitador/DNS Operator installed, `maas-default-gateway` provisioned, existing `llama-32-3b-instruct` reused via `ExternalProvider`/`ExternalModel`/`MaaSModelRef`, governed by `MaaSAuthPolicy`+`MaaSSubscription`. Endpoint: `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com` |
| `kserve.modelsAsService` (DSC, legacy field) | Removed | Removed — confirmed no-op/legacy path on this build, real flag is `aigateway.modelsAsAService` above |
| `dashboardConfig.agentsCatalog` | unset(false) | **true** ✅ |
| `dashboardConfig.guardrails` | unset(false) | **true** ✅ |
| `dashboardConfig.toolCalling` | unset(false) | **true** ✅ |
| `dashboardConfig.mcpCatalog` | unset(false) | **true** ✅ |
| `dashboardConfig.mcpRegistry` | unset(false) | **true** ✅ |
| `dashboardConfig.genAiStudio` | true (pre-existing) | true (unchanged, now backed by a real MaaS/MLflow deployment instead of an empty shell) |
| `dashboardConfig.modelAsService` | true (pre-existing) | true (unchanged, now backed by a real deployment) |
| `dashboardConfig.maasAuthPolicies` | unset | **left unset** — confirmed via live `oc explain odhdashboardconfig.spec.dashboardConfig` to be `DEPRECATED: This field is no longer used` |
| `dashboardConfig.agentConfigManagement` / `agentOps` / `genAiTracing` / `promptManagement` | unset(false) | **true** ✅ — originally left unset pending OGX; now enabled since OGX (§1) is genuinely `Ready`. Playground pages will show an empty/onboarding state until an `OGXServer` CR is created (still deferred). |

`DataScienceCluster` `Ready=True` at all times except brief, deliberate, self-resolved transitions during each change (OGX attempt ~4 min, MLflow rollout ~90s, MaaS/RHCL install ~a few min). Full post-change health sweep (final pass): **0 CrashLoopBackOff, 0 Pending, 0 failed CSVs, 0 stuck InstallPlans** anywhere in the cluster; the only non-`Running` pods remain the two pre-existing benign `installer-*` artifacts noted in the original audit. `kuadrant-system` (authorino, dns-operator, kuadrant-operator, limitador ×2) and MaaS (`maas-controller`, `maas-postgres`, `maas-api`) stacks are all healthy. The pre-existing standalone `authorino-operator` (openshift-operators) and RHCL's own `authorino` (kuadrant-system) coexist without any webhook or CRD-ownership conflict observed.

**Known limitation, unresolved by design:** MCP Catalog is enabled in **browse/catalog-only mode**. Red Hat's own MCP Lifecycle Operator documentation states OpenShift 4.22+ is required; this cluster is 4.20.36, so the operator was deliberately **not installed**, and the `MCPServer` CRD is absent, which disables the "Deploy" action in the catalog UI by design (graceful degradation, not a bug).
