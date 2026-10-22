# OpenShift AI 3.5 — Click-by-Click Demo Runbook

> **⚠️ SUPERSEDED (2026-09-17) — see `DEMO-CLICKBOOK.md` for the current, validated version.**
> This runbook was written when the strategy was "narrate the plan, build most things
> live." The strategy has since changed: **every resource below has now actually been
> built and validated end-to-end** (pipeline run Succeeded, OGXServer Ready, Streamlit app
> Running and returning the correct answer, MLflow experiment logged — see
> `PREDEMO-HEALTHCHECK.sh`, 30 PASS / 1 documented WARN / 0 FAIL).
>
> `DEMO-CLICKBOOK.md` is the up-to-date replacement for this file: same persona-based
> click-by-click structure, but every step now says exactly what's already `Ready` vs.
> what's genuinely safe to create/cancel live, and includes narration ("what you say") for
> every feature plus the two OGXServer platform workarounds and the MaaS API-key bug
> discovered while actually building this environment. Use `DEMO-LIVE-CHECKLIST.md` for
> the on-stage click list and `DEMO-ARCHITECTURE.md` for the "why" behind the wiring.
>
> This file is kept for historical reference only — some commands/paths below (e.g. the
> Streamlit build approach, the OGXServer YAML, the pipeline notebook code) do not match
> what was actually shipped.

**Cluster:** `api.ocp.tfmbf.sandbox2633.opentlc.com` · OCP 4.20.36 · RHOAI 3.5.0 (`rhods-operator.3.5.0`)
**Console:** https://console-openshift-console.apps.ocp.tfmbf.sandbox2633.opentlc.com
**RHOAI Dashboard:** https://rhods-dashboard-redhat-ods-applications.apps.ocp.tfmbf.sandbox2633.opentlc.com
**Node:** 1× `g6.8xlarge` (31.5 vCPU / 123 GiB allocatable / 1× NVIDIA L4 GPU) — this is a **single-node** sandbox, currently ~46% CPU / ~30% RAM / **100% of the GPU** already committed to the Llama deployment. Every new workload in this runbook is sized to fit in the remaining ~17 vCPU / ~85 GiB, and nothing new asks for the GPU.

Companion file: `DEMO-PREPARATION.md` (two-column prep split). Source of truth for backend state: `ENABLED-FEATURES.md`, `SANDBOX-AUDIT.md`.

Legend for **Demo mode**: `LIVE CREATE` (you actually click it into existence), `PRE-CREATED + SHOW` (already exists, you show/open it), `SHOW FORM ONLY` (you open the creation wizard, fill it in, then Cancel — nothing is created), `TERMINAL STEP` (no dashboard form exists; done via `oc`/YAML).

---

## PERSONA 1 — ALEX, PLATFORM ADMINISTRATOR

### Admin Step 1 — OpenShift AI Operator

**Persona:** Admin
**Demo mode:** PRE-CREATED — SHOW ONLY
**Current sandbox state:** `rhods-operator.3.5.0` installed in `redhat-ods-operator`, phase `Succeeded` (upgraded in-place from 3.4.3 earlier in this sandbox's life).
**Cursor must prepare before demo:** Nothing — confirm the CSV is still `Succeeded` right before you go live (`oc get csv -n redhat-ods-operator | grep rhods`).
**I must do during demo:**
1. Click **Operators → Installed Operators** in the left nav.
2. In the **Project** dropdown at top, select `redhat-ods-operator` (or "All Projects").
3. Click **Red Hat OpenShift AI**.

**Values to enter:** none — this is inspection only.

| Field | Value |
|---|---|
| — | — |

**What I point at:** the **Version** column (`3.5.0`) and **Status** (green check, `Succeeded`) on the Installed Operators row; then on the operator's own page, the **Subscription** tab showing the update channel.
**What I say:** "Everything you'll see today runs on Red Hat OpenShift AI 3.5, installed the same way any OpenShift Operator is — through OperatorHub, with Red Hat handling the CVE patching and upgrade path. I'm not going to reinstall it live, because that's a one-time, infrastructure-team action — but this is exactly what it looks like the day after install."
**Expected result:** Operator details page loads, green healthy status, version 3.5.0.
**Approximate wait time:** instant (page load only).
**Fallback:** If the console is slow to load, drop to a terminal and run `oc get csv -n redhat-ods-operator`, showing the same `Succeeded` phase and version string.
**Cleanup:** None.

---

### Admin Step 2 — DataScienceCluster

**Persona:** Admin
**Demo mode:** PRE-CREATED — SHOW ONLY
**Current sandbox state:** One cluster-scoped `DataScienceCluster` named `default-dsc`, phase `Ready`, condition `Ready=True`. Live component states right now:

| Component | State | Component | State |
|---|---|---|---|
| `dashboard` | Managed | `kserve` | Managed |
| `workbenches` | Managed | `aipipelines` | Managed |
| `modelregistry` | Managed | `trustyai` | Managed |
| `mlflowoperator` | Managed | `ogx` | Managed |
| `aigateway` (+`modelsAsAService`) | Managed | `feastoperator` | Managed |
| `ray` / `trainingoperator` / `trainer` | Managed | `kueue` | Removed |
| `llamastackoperator` | Removed (deprecated → renamed to `ogx`) | | |

**Cursor must prepare before demo:** Nothing to change. Have the YAML view pre-scrolled to the `spec.components` block so you don't hunt for it live.
**I must do during demo:**
1. From the Red Hat OpenShift AI operator page (Admin Step 1), click the **Data Science Cluster** tab (or search "DataScienceCluster" in the top **Search** box → **Resources**).
2. Click **default-dsc**.
3. Click the **YAML** tab.
4. Scroll to `spec.components`.

**Values to enter:** none — inspection only.

**What I point at:** `workbenches: Managed`, `kserve: Managed`, `trustyai: Managed`, `mlflowoperator: Managed`, `ogx: Managed`, `aigateway.modelsAsAService: Managed`, and the `status.conditions` entry `type: Ready, status: "True"`.
**What I say:** "The DataScienceCluster is the single control panel for the whole platform. Every capability you'll see today — model serving, pipelines, MLflow, the shared-model gateway, the new Gen AI orchestration layer called OGX — is just one line in this spec, set to `Managed` or `Removed`. I flip these once, centrally, and every project on the cluster inherits the capability. I'm not editing this live because a wrong edit here can take down inference for every team on the cluster — but here's exactly how you'd turn one on: **Operators → Red Hat OpenShift AI → Data Science Cluster → default-dsc → YAML tab**, add the component block, `Save`. It reconciles in under a minute for most components."
**Expected result:** YAML view renders, all listed components show the values above, `Ready: "True"` visible in status.
**Approximate wait time:** instant.
**Fallback:** `oc get datasciencecluster default-dsc -o yaml` in a terminal, or `oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'`.
**Cleanup:** None.

---

### Admin Step 3 — Accelerator / GPU and Hardware Profile

**Persona:** Admin
**Demo mode:** PRE-CREATED — SHOW ONLY (existing `gpu-profile`); optional tiny LIVE CREATE of a throwaway CPU-only profile if you want to prove the wizard live.
**Current sandbox state:** One worker node, `g6.8xlarge`, label `nvidia.com/gpu.product=NVIDIA-L4`, `status.allocatable["nvidia.com/gpu"]=1`. NVIDIA GPU Operator (`nvidia-gpu-operator` namespace) fully healthy: `gpu-feature-discovery`, `nvidia-driver-daemonset`, `nvidia-device-plugin-daemonset`, `nvidia-dcgm`, `nvidia-cuda-validator` all `Running`/`Completed`. Two `HardwareProfile` CRs exist in `redhat-ods-applications`: `gpu-profile` (CPU 1–8, default 1; Memory 1–16Gi, default 12Gi; `nvidia.com/gpu` 1–4, default 1) and `default-profile` (CPU 1–4, default 2; Memory 2–8Gi, default 4Gi, CPU-only).
**Cursor must prepare before demo:** Nothing — both profiles already exist and are enabled.
**I must do during demo:**
1. **Prove the GPU is real hardware, not just a label:** Click **Compute → Nodes** in the OpenShift console → click the node name → **Details** tab → scroll to **Labels**, point at `nvidia.com/gpu.product=NVIDIA-L4`. Then click **Operators → Installed Operators → NVIDIA GPU Operator → ClusterPolicy → gpu-cluster-policy**, point at status `Ready`.
2. **Show what OpenShift AI sees:** In the RHOAI dashboard, click **Settings → Hardware profiles**.
3. Click the row **gpu-profile**.

**Values to enter (for explaining "how an admin would create one" — do not submit if just narrating):**

| Field | Value |
|---|---|
| Name | `gpu-profile` (existing) or e.g. `demo-cpu-profile` if creating live |
| Resource name | auto-generated from Name (editable once, before Create) |
| Description | "1× NVIDIA L4 GPU profile for generative AI model serving" |
| Visibility | Visible everywhere |
| Resource 1 — label | `CPU` |
| Resource 1 — identifier | `cpu` |
| Resource 1 — type | CPU |
| Resource 1 — default / min / max | `1` / `1` / `8` |
| Resource 2 — label | `Memory` |
| Resource 2 — identifier | `memory` |
| Resource 2 — type | Memory |
| Resource 2 — default / min / max | `12Gi` / `1Gi` / `16Gi` |
| Resource 3 — label | `GPU` |
| Resource 3 — identifier | `nvidia.com/gpu` |
| Resource 3 — type | Accelerator |
| Resource 3 — default / min / max | `1` / `1` / `4` |

**What I point at:** the three resource rows in `gpu-profile`'s detail view, especially the `nvidia.com/gpu` identifier — "this string is what ties a workbench or model deployment to the physical L4 card."
**What I say:** "Before any team can request a GPU, I as the admin have to expose it as a Hardware Profile. This one says: up to 4 GPUs, up to 8 CPUs, up to 16 gigs of RAM, per pod. Once this exists, it just shows up as a dropdown option for every data scientist creating a workbench or deploying a model — they never touch node labels or resource YAML themselves." If creating live: "Watch — Name, add the three resources, Create. Ten seconds, and now anyone on the cluster can request an L4."
**Expected result:** `gpu-profile` detail page shows the three identifiers above; if a demo profile is created live, it appears immediately in the Hardware profiles table, toggled Enabled.
**Approximate wait time:** instant for viewing; ~15 seconds for a live create.
**Fallback:** `oc get hardwareprofile gpu-profile -n redhat-ods-applications -o yaml`.
**Cleanup:** If you created `demo-cpu-profile` live, delete it afterward: `oc delete hardwareprofile demo-cpu-profile -n redhat-ods-applications` (or the toggle-off + trash-can icon in the UI).

---

### Admin Step 4 — Create the model project

**Persona:** Admin
**Demo mode:** LIVE CREATE
**Current sandbox state:** Project `my-first-model` already exists and hosts the shared Llama deployment (created in an earlier setup pass, using the exact same mechanic shown below). No project named `shared-ai-services` exists yet.
**Decision:** Create a **new** project live called `shared-ai-services` to narrate the "how admins provision space for shared models" story cleanly, without touching or risking the already-running `my-first-model` project. After creating it, pivot to `my-first-model` and say plainly that it was created the identical way, earlier.
**Cursor must prepare before demo:** Nothing needed — this is safe and fast enough to do fully live.
**I must do during demo:**
1. Click **Projects** in the left nav.
2. Click **Create project**.
3. In the **Name** field, type `Shared AI Services`.
4. (Optional) Click **Edit resource name** to confirm it auto-slugs to `shared-ai-services` — leave it.
5. In the **Description** field, type the description below.
6. Click **Create**.

**Values to enter:**

| Field | Value |
|---|---|
| Name (display name) | `Shared AI Services` |
| Resource name (auto) | `shared-ai-services` |
| Description | `Central project for GPU-backed models exposed to every team via Models-as-a-Service.` |

**What I point at:** the resulting empty project detail page — tabs for **Overview, Workbenches, Deployments, Pipelines, Connections, Permissions** — "this is the same skeleton every project gets, whether it's platform-owned like this one or team-owned like Maya's will be."
**What I say:** "In OpenShift AI, a project is just an OpenShift namespace with extra guardrails — permissions, connections, and a place for models and pipelines to live. I create one exactly like this for any shared, platform-owned service. Our actual production Llama model — which we'll look at next — lives in a project called `my-first-model`, created the exact same way a bit earlier."
**Expected result:** New project `shared-ai-services` appears in the Projects list within a couple seconds, opens to an empty detail page with no workbenches/deployments/pipelines yet.
**Approximate wait time:** under 5 seconds.
**Fallback:** `oc new-project shared-ai-services --display-name="Shared AI Services"`.
**Cleanup:** `oc delete project shared-ai-services` after the demo (it's empty, safe to remove) — or leave it as a permanent "front door" project if you'd rather migrate the Llama model into it later.

---

### Admin Step 5 — Deploy the LLM

**Persona:** Admin
**Demo mode:** SHOW FORM → explain values → cancel → open existing running deployment. **Validated as the right pattern:** loading a 3B-parameter model onto the L4 takes ~3–5 minutes in this sandbox (image pull + weight load + vLLM warm-up) — dead air you don't want live, and the GPU is a single, already-fully-committed unit, so a second live deployment would either queue forever or evict the running one. Never actually submit this form.
**Current sandbox state:** `llama-32-3b-instruct` `InferenceService` running in `my-first-model`, `Ready=True`, `Loaded`, since earlier in this sandbox's setup.
**Cursor must prepare before demo:** Nothing further — it's already running and stable.
**I must do during demo:**
1. Click **Projects → my-first-model → Deployments** tab.
2. Click **Deploy model** — the wizard opens.
3. Walk through and fill in (do not click the final Deploy):
   - **Model type:** Generative AI model → Next.
   - **Model deployment name:** `llama-32-3b-instruct-demo` (not submitted).
   - **Hardware profile:** `gpu-profile`.
   - **Serving runtime:** select **vLLM NVIDIA GPU ServingRuntime for KServe** from the list (or leave on auto-select — the system matches it automatically because `gpu-profile` requests an NVIDIA accelerator).
   - **Number of model server replicas:** `1`.
   - **Model location:** OCI-compliant registry / URI — `oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct`.
   - **Advanced:** point at (don't necessarily toggle) **External route** and **Token authentication** checkboxes.
4. Click **Cancel** (top or bottom of the wizard) to discard.
5. Click into the existing **llama-32-3b-instruct** row in the Deployments list instead.

**Values to enter (shown in the form, matching the real running deployment):**

| Field | Value |
|---|---|
| Model type | Generative AI model |
| Model deployment name | `llama-32-3b-instruct` |
| Hardware profile | `gpu-profile` (1 GPU, up to 8 CPU, up to 16Gi RAM) |
| Serving runtime | vLLM NVIDIA GPU ServingRuntime for KServe |
| Runtime image (point at, don't type) | `registry.redhat.io/rhaiis/vllm-cuda-rhel9` |
| Replicas | 1 |
| Model location (OCI URI) | `oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct` |
| Custom runtime args (point at in the real deployment's YAML) | `--dtype=half --max-model-len=20000 --gpu-memory-utilization=0.95 --enable-auto-tool-choice --tool-call-parser=llama3_json` |
| Requests / Limits (real deployment) | 1 CPU / 6Gi / 1 GPU → 4 CPU / 16Gi / 1 GPU |

**What I point at:** after cancelling, open the real `llama-32-3b-instruct` row → **Status: Ready** (green), the **Internal Service** endpoint `llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local`, and the runtime's YAML showing the exact args table above and `registry.redhat.io/rhaiis/vllm-cuda-rhel9` as the container image.
**What I say:** "This is the wizard I'd use to deploy any generative model — point it at an image, pick a runtime and a hardware profile, set replicas, done. I'm not clicking Deploy, because loading a 3-billion-parameter model onto our one L4 GPU takes several minutes, and this GPU is already fully committed to the model we're about to use. So instead — here's the one that's already live: same wizard, same image family, `vLLM` on `registry.redhat.io/rhaiis/vllm-cuda-rhel9`, already `Ready` and serving traffic."
**Expected result:** Form renders correctly with all fields available; after Cancel, existing deployment opens showing `Ready`/`Loaded` status.
**Approximate wait time:** instant (form is just UI; no submission).
**Fallback:** If the wizard is slow, show the same information via `oc get inferenceservice llama-32-3b-instruct -n my-first-model -o yaml`.
**Cleanup:** None — nothing was created.

---

### Admin Step 6 — Deploy an embedding model

**Persona:** Admin
**Demo mode:** PRE-CREATED + SHOW FORM ONLY → open existing. Cursor deploys this ahead of time so it's warm; live, you show the wizard, Cancel, then open the real one — same safety pattern as Step 5, just because CPU model loads are slower to guarantee than the extra risk is worth for a scripted demo.
**Investigation performed before choosing this model (documented so you can repeat/defend the choice):**
- **Available serving runtime templates on this cluster:** `vllm-cuda-runtime-template`, `vllm-cpu-runtime-template`, **`vllm-cpu-x86-runtime-template`**, `vllm-gaudi/rocm/spyre-*`, `mlserver-runtime-template`, `mlserver-cuda-runtime-template`, `kserve-ovms`, `autogluon-runtime-template`, `guardrails-detector-huggingface-serving-template`. → **vLLM CPU (x86) ServingRuntime for KServe** (`vllm-cpu-x86-runtime-template`, image `registry.redhat.io/rhaii/vllm-cpu-rhel9`, vLLM v0.24.0) natively serves OpenAI-compatible `/v1/embeddings` for small transformer embedding models, with no GPU needed.
- **Available CPU/RAM:** node has 31.5 vCPU / 123 GiB allocatable; current usage is ~14.5 vCPU (46%) / ~37 GiB (30%) requested — comfortably enough headroom for a 2 CPU / 4Gi CPU-only pod.
- **Model chosen:** `sentence-transformers/all-MiniLM-L6-v2` — 22M parameters, 384-dimension vectors, one of the smallest widely-used embedding models, fast enough on CPU to feel instant in a live demo, and (bonus) a **pre-built ModelCar OCI image already exists** in the same public catalog used for Llama: `quay.io/redhat-ai-services/modelcar-catalog:all-minilm-l6-v2` — zero custom image build required.
**Current sandbox state (after Cursor's prep):** `all-minilm-l6-v2` `InferenceService` running in `my-first-model`, CPU-only, `default-profile`, `Ready=True`.
**Cursor must prepare before demo:** Deploy this `InferenceService` ahead of time (see `DEMO-PREPARATION.md`) — image pull + CPU load is only ~30–60 seconds, but don't burn that time live.
**I must do during demo:**
1. Click **Projects → my-first-model → Deployments → Deploy model**.
2. Fill in the form (values below), then **Cancel**.
3. Open the existing **all-minilm-l6-v2** row instead.

**Values to enter:**

| Field | Value |
|---|---|
| Model type | Generative AI model |
| Model deployment name | `all-minilm-l6-v2` |
| Hardware profile | `default-profile` (2 CPU / 4Gi, no accelerator) |
| Serving runtime | vLLM CPU (x86) ServingRuntime for KServe — Tech Preview |
| Runtime image (point at) | `registry.redhat.io/rhaii/vllm-cpu-rhel9` |
| Replicas | 1 |
| Model location (OCI URI) | `oci://quay.io/redhat-ai-services/modelcar-catalog:all-minilm-l6-v2` |
| Make available as AI asset | ✅ checked (so it shows in Gen AI Studio → AI asset endpoints, Type = Embedding) |

**What I point at:** the **Ready** status, and the fact that it requests **0 GPUs** — "look at the resource request: no accelerator at all. This runs happily next to the Llama model without competing for the L4."
**What I say:** "The LLM generates the answer. But before it can answer questions about *our* documents, we need a way to turn text — documents and questions alike — into vectors that capture meaning, so we can search by similarity instead of exact keywords. That's what an embedding model does. I picked the smallest reliable one — 22 million parameters — and it runs on plain CPU, so it doesn't compete with the GPU our chat model needs."
**Expected result:** Deployment shows `Ready`, appears in AI asset endpoints list with Type `Embedding`.
**Approximate wait time:** instant to view (pre-created); ~30–60s if you were to deploy it live instead.
**Fallback:** `oc get inferenceservice all-minilm-l6-v2 -n my-first-model -o yaml`; if it's not Ready, `oc logs -n my-first-model deploy/all-minilm-l6-v2-predictor -c kserve-container --tail=50`.
**Cleanup:** Keep running for the rest of the demo (Data Scientist steps depend on it).

---

### Admin Step 7 — Models-as-a-Service (admin journey)

**Persona:** Admin
**Demo mode:** PRE-CREATED + SHOW ONLY, with one confirmed **ADMIN TERMINAL STEP**.
**Current sandbox state:** MaaS is fully live end-to-end. Backend objects (all in namespace `models-as-a-service`):

| Backend object | Name | Status |
|---|---|---|
| `ExternalProvider` | `llama-32-3b-instruct-provider` | Ready |
| `ExternalModel` | `llama-32-3b-instruct-external` | Ready, HTTPRoute created |
| `MaaSModelRef` | `llama-32-3b-instruct-maas` | Ready — `RuntimeReady` + `GovernanceAttached` |
| `MaaSAuthPolicy` | `llama-32-3b-instruct-access` | Ready |
| `MaaSSubscription` | `llama-32-3b-instruct-subscription` | Ready, 100,000 tokens/hour |
| Gateway | `maas-default-gateway` (openshift-ingress) | Programmed, external ELB |
| Public endpoint | `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com` | Live |

**Mapping backend → dashboard:**

| Backend object | Where it appears in the UI |
|---|---|
| `MaaSModelRef` (`llama-32-3b-instruct-maas`) | **Gen AI studio → AI asset endpoints** — appears as a governed model row with endpoint URL, "Generate API key" button |
| `MaaSSubscription` | **Settings → Subscriptions** (admin) *and* **Gen AI studio → API keys → Subscriptions tab** (per-user view) |
| `MaaSAuthPolicy` | **Settings → Authorization policies** (admin) |
| `ExternalProvider` / `ExternalModel` | **No dashboard equivalent** — see terminal step below |

**Cursor must prepare before demo:** Nothing further — already applied. **Before you go live, open `Settings` in the left nav once and confirm whether `Subscriptions` and `Authorization policies` actually appear.** Red Hat's docs say these require `spec.dashboardConfig.maasAuthPolicies: true`, but a live schema check on this exact build (`oc explain odhdashboardconfig.spec.dashboardConfig.maasAuthPolicies`) reports it as **deprecated/no-op**. It's possible the pages are always-on now, or possible they're hidden on this build — verify once, ahead of time, so you're not surprised on stage.
**I must do during demo:**
1. Click **Gen AI studio → AI asset endpoints** in the left nav.
2. Point at the `llama-32-3b-instruct` row — endpoint URL, model status, **Generate API key** button.
3. *If Settings → Subscriptions is visible:* click **Settings → Subscriptions → llama-32-3b-instruct-subscription** to show the governance side.
4. *If not visible* (fallback): open a terminal and run the command in the ADMIN TERMINAL STEP box below instead.

**Values to enter:** none — inspection only.

**What I point at:** the endpoint URL `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`, and say "this is the exact same model Data Scientists just saw running raw inside `my-first-model` — MaaS didn't redeploy it, it *fronted* it."
**What I say:** "We already had this Llama model running. Models-as-a-Service doesn't deploy a second copy — it puts a governed gateway in front of the one we have. I minted an API-key-based access layer, a rate limit, and an authorization rule, all without touching the model itself."

**ADMIN TERMINAL STEP** — wiring an existing classic `InferenceService` into MaaS has **no dashboard form** (the native "Deploy straight into MaaS" wizard path only works for models deployed after MaaS was enabled, using `LLMInferenceService`; ours predates that and uses the older `InferenceService` kind). This was done once, ahead of time, via:
```bash
oc apply -f yaml/maas-reuse-llama-model.yaml
```
containing a `Secret`, `ExternalProvider`, `ExternalModel`, and `MaaSModelRef` (full contents in `ENABLED-FEATURES.md` §3). Say plainly on stage: "This one piece — bridging a pre-existing model into the MaaS layer — required a YAML apply, not a button. Everything downstream of it (subscriptions, policies, API keys) is dashboard-native."

**Expected result:** AI asset endpoints page lists `llama-32-3b-instruct` with a live endpoint and a working "Generate API key" button.
**Approximate wait time:** instant.
**Fallback:** `oc get maasmodelref,externalmodel,externalprovider -n models-as-a-service`.
**Cleanup:** None.

---

### Admin Step 8 — MaaS subscription / governance

**Persona:** Admin
**Demo mode:** PRE-CREATED + SHOW ONLY, primary path via dashboard **if visible** (see caveat in Step 7); otherwise **ADMIN TERMINAL STEP — PRE-CREATED**.
**Current sandbox state:** `MaaSSubscription/llama-32-3b-instruct-subscription` — owner group `system:authenticated`, priority `1`, token rate limit `100,000 / 1h` on `llama-32-3b-instruct-maas`, cost center `demo`. `MaaSAuthPolicy/llama-32-3b-instruct-access` — grants `system:authenticated` access to the same model ref. Both `Ready=True`.
**Cursor must prepare before demo:** Nothing further — already applied and `Ready`.
**I must do during demo (if `Settings → Subscriptions` is visible on this build):**
1. Click **Settings → Subscriptions**.
2. Click **llama-32-3b-instruct-subscription**.
3. Point at the group (`system:authenticated`), the model row, and its token limit.
4. Click **Settings → Authorization policies → llama-32-3b-instruct-access**, point at the same group grant.

**If not visible, do this instead (ADMIN TERMINAL STEP — PRE-CREATED):**
```bash
oc get maassubscription llama-32-3b-instruct-subscription -n models-as-a-service -o yaml
oc get maasauthpolicy   llama-32-3b-instruct-access        -n models-as-a-service -o yaml
```

**Values to enter:** none — this step only edits/creates a subscription if you choose to demonstrate "Create subscription" live (optional, not required):

| Field (only if demonstrating "Create subscription" live) | Value |
|---|---|
| Name | `demo-subscription` |
| Groups | `system:authenticated` |
| Model | `llama-32-3b-instruct` |
| Token limit | `100000` per `1h` |
| Priority | `1` |

**What I point at:** the token limit number (`100,000/hour`) and the group (`system:authenticated` — "every logged-in employee, out of the box").
**What I say (this is the core governance narrative of the whole admin section):** "A subscription and an authorization policy are two separate locks, and MaaS requires both to open. The subscription says *how much* a group can consume — a hundred thousand tokens an hour, tracked automatically. The authorization policy says *whether* that group is allowed to reach the model at all. Put simply: I decide who can use the shared model, and how much they're allowed to consume, once, centrally — and every API key anyone mints inherits that decision automatically. Maya, in the next section, never sees this screen. She just gets access, because she's in the right group."
**Expected result:** Subscription and policy detail pages (or their YAML) show the values above.
**Approximate wait time:** instant.
**Fallback:** as above.
**Cleanup:** None.

---

### Admin Step 9 — MLflow

**Persona:** Admin
**Demo mode:** PRE-CREATED — SHOW ONLY (brief).
**Current sandbox state:** `mlflowoperator: Managed`, `MLflow` CR named `mlflow`, `Available=True`. Tracking server `Deployment/mlflow` `2/2 Running`, backed by a 10Gi PVC + SQLite store (documented minimal-deployment pattern). No experiments logged yet — Maya creates the first real one later (Data Scientist Step 15).
**Cursor must prepare before demo:** Nothing further.
**I must do during demo:**
1. From any project, click **Develop & train → Experiments (MLflow)** in the left nav (or **Applications → MLflow**).
2. Point at the empty experiments list.

**Values to enter:** none.
**What I point at:** the empty state — "no experiments yet, on purpose."
**What I say:** "One more platform capability, quickly: experiment tracking, enabled centrally so every workbench gets it automatically, no manual tracking-URI setup for any data scientist. It's empty right now because nobody's logged a run yet — Maya will be the one to do that, later, from her own notebook."
**Expected result:** MLflow page loads inside the dashboard, empty experiments table.
**Approximate wait time:** instant.
**Fallback:** `oc get mlflow mlflow -o yaml`.
**Cleanup:** None.

---

### Admin Step 10 — OGX

**Persona:** Admin
**Demo mode:** PRE-CREATED — SHOW ONLY. **Do NOT create the `OGXServer` here.**
**Validated against product behavior:** the official Red Hat example for deploying an `OGXServer` explicitly scopes it `namespace: <project-name>` and wires it to *one specific* vLLM endpoint + *one specific* vector database — i.e., it is inherently an **application-level, project-scoped** resource, not a platform-wide one. Your suspicion is correct: **Alex (admin) enables the OGX capability platform-wide; Maya (data scientist) creates the actual `OGXServer` instance inside her own project**, because only she knows which model, which vector DB, and which use case it serves. This mirrors how KServe or Pipelines work — the admin turns on the engine, the data scientist drives it.
**Current sandbox state:** `ogx: Managed` in the DSC, condition `OGXReady=True`. CRDs `ogxs.components.platform.opendatahub.io` and `ogxservers.ogx.io` are registered. Operator pods `ogx-k8s-operator-controller-manager` and `opendatahub-ogx-operator` both `1/1 Running`. **No `OGXServer` CR exists anywhere on the cluster yet** — Maya creates the first one in Data Scientist Step 11.
**Cursor must prepare before demo:** Nothing further for this step specifically (the Postgres instance Maya's `OGXServer` will need is prepared under Data Scientist Step 3/11 — see `DEMO-PREPARATION.md`).
**I must do during demo:**
1. Return to **Operators → Red Hat OpenShift AI → Data Science Cluster → default-dsc → YAML**, point at `ogx: Managed` (same page as Admin Step 2 — quick, no re-navigation needed if you kept the tab open).
2. Optionally, in a terminal: `oc get pods -n redhat-ods-applications | grep ogx`.

**Values to enter:** none.
**What I point at:** `ogx: Managed` in the DSC spec, and the two Running operator pods in the terminal.
**What I say:** "The last platform capability: OGX, our newest Gen AI orchestration engine — it's what will let Maya's application retrieve company documents and hand them to the LLM as context, and later, host actual AI agents. I turn the *engine* on, platform-wide, once. But the actual server instance — which model it talks to, which vector database it uses — that's an application decision, so that belongs in Maya's project, not mine. Watch what she does with it in a few minutes."
**Expected result:** `ogx: Managed`, two operator pods `Running`, no `OGXServer` instances (empty `oc get ogxserver -A`).
**Approximate wait time:** instant.
**Fallback:** `oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="OGXReady")]}'`.
**Cleanup:** None.

---

### TRANSITION

**What I say:** "The platform is now ready. Alex has provided compute, shared models, governance, and platform capabilities. We can now switch roles. — I am now Maya, the data scientist."

---

## PERSONA 2 — MAYA, DATA SCIENTIST

### Data Scientist Step 1 — Discover the MaaS model

**Persona:** Data Scientist
**Demo mode:** PRE-CREATED + SHOW ONLY.
**Current sandbox state:** `llama-32-3b-instruct` is live and governed via MaaS (Admin Steps 7–8). Maya, as an authenticated cluster user in `system:authenticated`, already has subscription + policy access — nothing to request.
**Cursor must prepare before demo:** Nothing further.
**I must do during demo:**
1. Log in to the RHOAI dashboard as Maya (or narrate "as Maya" from the same session).
2. Click **Gen AI studio → AI asset endpoints**.
3. Point at the `llama-32-3b-instruct` row.
4. Click **Generate API key** (creates a real 1-hour temporary key — safe, self-expiring).

**Values to enter:** none.
**What I point at:** the endpoint URL, the **Subscription** dropdown (shows her inherited subscription), and the freshly generated key (shown once).
**What I say:** "Maya does not deploy another Llama model. She doesn't even know there's a GPU involved. She opens one page, sees a model the platform team already published, and gets a key. That's the entire self-service experience Alex's governance work in the last section was building toward."
**Expected result:** Model row visible with a working "Generate API key" action; a `sk-oai-*` key appears once.
**Approximate wait time:** instant.
**Fallback:** `curl -s https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com/v1/models -H "Authorization: Bearer <key>"`.
**Cleanup:** The temporary key self-expires in 1 hour; no action needed.

---

### Data Scientist Step 2 — Create application project

**Persona:** Data Scientist
**Demo mode:** LIVE CREATE
**Current sandbox state:** No project named `knowledge-advisor` exists yet (confirmed: `namespaces "knowledge-advisor" not found`).
**Cursor must prepare before demo:** Nothing — this must stay un-created so it can be created live.
**I must do during demo:**
1. Click **Projects → Create project**.
2. Fill in the fields below.
3. Click **Create**.

**Values to enter:**

| Field | Value |
|---|---|
| Name (display name) | `Knowledge Advisor` |
| Resource name (auto) | `knowledge-advisor` |
| Description | `RAG-powered internal Q&A assistant over company policy documents.` |

**What I point at:** the new empty project page — same tab skeleton Alex showed earlier (Connections, Workbenches, Pipelines, Deployments) — "this is entirely mine; I don't need Alex for any of what comes next."
**What I say:** "This is my project — my sandbox to build the Knowledge Advisor app in. Everything from here is self-service."
**Expected result:** `knowledge-advisor` project created within seconds, appears in the Projects list.
**Approximate wait time:** under 5 seconds.
**Fallback:** `oc new-project knowledge-advisor --display-name="Knowledge Advisor"`.
**Cleanup:** Keep for the remainder of the demo; delete with `oc delete project knowledge-advisor` after, if desired.

---

### Data Scientist Step 3 — Create PostgreSQL + pgvector

**Persona:** Data Scientist (infrastructure provisioned by Cursor beforehand; Maya only *sees and uses* it)
**Demo mode:** PRE-CREATED + SHOW ONLY.
**What Cursor prepares:** A `pgvector/pgvector:pg16` Postgres instance (`Deployment` + `Service` + `PVC` + `Secret`) inside `knowledge-advisor`, with the `vector` extension enabled and two databases created: `ragdb` (for document-chunk embeddings) and `ogx` (metadata store the `OGXServer` will use in Step 11). This is deployed **before** the demo because standing up a stateful database live wastes stage time for zero storytelling value — nobody wants to watch a PVC bind.
**Current sandbox state (after prep):** `Deployment/pgvector-db`, `Service/pgvector-db` (port 5432), `Secret/pgvector-db-credentials` (`POSTGRES_USER=ragadmin`, `POSTGRES_PASSWORD=<generated>`, `POSTGRES_DB=ragdb`), `PVC/pgvector-db-data` (5Gi, `gp3-csi`) — all in `knowledge-advisor`.
**I must do during demo:**
1. Click **Projects → knowledge-advisor → Connections** (Maya sees it as a Connection, not as a raw Deployment — see Step 4 for how she creates that Connection).
2. Optionally point at **Workloads → Deployments → pgvector-db** in the OpenShift console (not the RHOAI dashboard) to show "yes, it's a real Postgres pod running here" without dwelling on it.

**Values to enter:** none — this is inspection only; the actual Connection is created in Step 4.
**What I point at:** the running `pgvector-db` pod (`Running`, `1/1`) and, briefly, `psql`-ing in (optional) to run `SELECT extname FROM pg_extension WHERE extname = 'vector';` and show one row.
**What I say:** "This database holds two things: the vector embeddings for our RAG search, and metadata for OGX, which we'll set up in a few minutes. I didn't provision this live — a stateful database with a real backup story isn't something you spin up in front of an audience — but here it is, ready and connected to my project."
**Expected result:** Pod `Running`, `vector` extension present, both databases exist.
**Approximate wait time:** instant to view.
**Fallback:** `oc exec -n knowledge-advisor deploy/pgvector-db -- psql -U ragadmin -d ragdb -c "\dx"`.
**Cleanup:** Leave running for the rest of the demo.

---

### Data Scientist Step 4 — Create Connections

**Persona:** Data Scientist
**Demo mode:** LIVE CREATE
**Current sandbox state:** No connections exist yet in `knowledge-advisor` (project was just created in Step 2). A lightweight MinIO instance (`Deployment/minio`, `Service/minio`, buckets `documents` and `pipelines`) is pre-created by Cursor in the same project, to back both the document-storage connection and the Pipelines object-storage requirement in Step 10.
**Cursor must prepare before demo:** The MinIO instance + buckets (see `DEMO-PREPARATION.md`) and the Postgres instance from Step 3. Maya creates the *connections themselves* live — that part is fast, safe, and exactly what the user asked to see.
**I must do during demo:**
1. Click **Projects → knowledge-advisor → Connections → Create connection**.
2. **Connection 1 — vector database:**
   - Connection type: **URI - v1**.
   - Name: `vector-database`.
   - URI: `postgresql://ragadmin:<REDACTED>@pgvector-db.knowledge-advisor.svc.cluster.local:5432/ragdb` (use a placeholder like `<PGVECTOR_PASSWORD>` on stage — never paste the real password into a shared screen).
   - Click **Create**.
3. Click **Create connection** again. **Connection 2 — company documents:**
   - Connection type: **S3 compatible object storage - v1**.
   - Name: `company-documents`.
   - Access key / Secret key: from the pre-created MinIO credentials (placeholder on stage).
   - Endpoint: `http://minio.knowledge-advisor.svc.cluster.local:9000`.
   - Region: `us-east-1` (dummy — MinIO ignores it, but the field is required).
   - Bucket: `documents`.
   - Click **Create**.

**Values to enter:**

| Field | Connection 1 (`vector-database`) | Connection 2 (`company-documents`) |
|---|---|---|
| Type | URI - v1 | S3 compatible object storage - v1 |
| Name | `vector-database` | `company-documents` |
| URI / Endpoint | `postgresql://ragadmin:<PGVECTOR_PASSWORD>@pgvector-db.knowledge-advisor.svc.cluster.local:5432/ragdb` | `http://minio.knowledge-advisor.svc.cluster.local:9000` |
| Access key | — | `<MINIO_ACCESS_KEY>` (placeholder) |
| Secret key | — | `<MINIO_SECRET_KEY>` (placeholder) |
| Bucket | — | `documents` |

**What I point at:** the **Connections** tab now showing both rows, and the fact that neither has a password visible in the UI — "stored as a Secret, referenced by name."
**What I say:** "Maya connects to services without hard-coding credentials into her notebook. She picks a type, fills in a form once, and from now on every workbench or pipeline in this project can attach to `vector-database` or `company-documents` by name — no copy-pasted connection strings scattered across notebooks."
**Expected result:** Two connections listed on the Connections tab; each backed by a Kubernetes `Secret` with the `opendatahub.io/connections` annotation.
**Approximate wait time:** ~10 seconds per connection.
**Fallback:** `oc get secrets -n knowledge-advisor -l opendatahub.io/managed=true`.
**Cleanup:** Keep for the rest of the demo.

---

### Data Scientist Step 5 — Create Workbench

**Persona:** Data Scientist
**Demo mode:** PRE-CREATED + SHOW creation screen → open existing. A JupyterLab workbench takes 45–90 seconds to pull the image and start on first run in this sandbox — acceptable to show starting, but safer to have a warm one ready so you're not waiting on stage.
**Current sandbox state (after prep):** Workbench `knowledge-advisor-workbench` exists in `knowledge-advisor`, image `Jupyter | Standard Data Science`, `default-profile` (2 CPU / 4Gi), both connections attached, status `Running`.
**Cursor must prepare before demo:** Create and start this workbench ahead of time (see `DEMO-PREPARATION.md`).
**I must do during demo:**
1. Click **Projects → knowledge-advisor → Workbenches → Create workbench** — walk through the fields below, then either click **Create** for real (if you want to prove it live and are fine narrating through the ~60s startup) or **Cancel** and open the pre-created one.
2. Open **knowledge-advisor-workbench** → click **Open** to launch JupyterLab in a new tab.

**Values to enter:**

| Field | Value |
|---|---|
| Name | `knowledge-advisor-workbench` |
| Workbench image | `Jupyter \| Standard Data Science` |
| Deployment size / Hardware profile | `default-profile` (2 CPU / 4Gi, no accelerator) |
| Connections | `vector-database`, `company-documents` |
| Environment variables | none required — connection env vars are injected automatically |

**What I point at:** the **Connections** section of the creation form, pre-populated with the two connections from Step 4 — "I don't type a hostname or password anywhere in this form."
**What I say:** "A workbench is just a JupyterLab pod with my project's connections wired in automatically. Two CPUs, four gigs of RAM — plenty, because the actual AI work happens on the model servers, not in here. I attach both connections at creation time so `os.environ` just has what I need the moment the kernel starts."
**Expected result:** Workbench status `Running`; JupyterLab opens in a new browser tab; `os.environ` inside a notebook cell shows connection-derived env vars (e.g., `AWS_S3_ENDPOINT`, or the URI connection's env var name).
**Approximate wait time:** instant to open (pre-created); ~60–90s if started live.
**Fallback:** `oc get notebook knowledge-advisor-workbench -n knowledge-advisor -o jsonpath='{.status}'`.
**Cleanup:** Leave running for the rest of the demo; stop it afterward from the Workbenches tab to free resources.

---

### Data Scientist Step 6 — First MaaS API call

**Persona:** Data Scientist
**Demo mode:** LIVE (from the running workbench).
**Current sandbox state:** MaaS endpoint live at `https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com`; Maya has (or mints) an API key from Data Scientist Step 1.
**Cursor must prepare before demo:** Nothing beyond the workbench itself being open.
**I must do during demo:**
1. In JupyterLab, open a new notebook cell.
2. Paste and run:

```python
import requests

MAAS_URL = "https://maas.apps.ocp.tfmbf.sandbox2633.opentlc.com/v1/chat/completions"
API_KEY = "<paste the sk-oai-... key from Step 1>"

resp = requests.post(
    MAAS_URL,
    headers={"Authorization": f"Bearer {API_KEY}"},
    json={
        "model": "llama-32-3b-instruct",
        "messages": [{"role": "user", "content": "In one sentence, what is retrieval-augmented generation?"}],
    },
    timeout=30,
)
print(resp.json()["choices"][0]["message"]["content"])
```

**Values to enter:** the API key from Step 1 (shown once when minted).
**What I point at:** the printed model response, and the fact that the URL is an external, org-wide MaaS endpoint — not anything Maya deployed.
**What I say:** "At this point I already have AI inference — without deploying a model, without touching a GPU, without asking the platform team for anything except being in the right group. Fifteen lines of Python, one HTTP call."
**Expected result:** A coherent one-sentence answer printed in the notebook, HTTP 200.
**Approximate wait time:** 1–3 seconds for the response.
**Fallback:** If MaaS/network is flaky, fall back to calling the internal service directly for the demo: `http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1/chat/completions` (no auth needed, but explicitly say "this is the ungoverned, internal-only path — not what we'd use in production").
**Cleanup:** None.

---

### Data Scientist Step 7 — Test embedding model

**Persona:** Data Scientist
**Demo mode:** LIVE (from the workbench).
**Current sandbox state:** `all-minilm-l6-v2` running internally in `my-first-model` (Admin Step 6).
**Cursor must prepare before demo:** Nothing further.
**I must do during demo:**
1. New notebook cell:

```python
import requests

EMBED_URL = "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings"

resp = requests.post(
    EMBED_URL,
    json={"model": "all-minilm-l6-v2", "input": "Employees may work remotely on Monday and Friday."},
    timeout=30,
)
vector = resp.json()["data"][0]["embedding"]
print(f"Vector length: {len(vector)}")
print(f"First 8 values: {vector[:8]}")
```

**Values to enter:** the exact sentence above (matches the document content in Step 8, on purpose — it's the sentence Step 13's RAG answer will retrieve).
**What I point at:** `Vector length: 384` and the first few floating-point numbers.
**What I say:** "This vector represents the semantic meaning of that sentence — 384 numbers. It's meaningless to a human, but two sentences with similar meaning will produce two vectors that are close together mathematically. That's the entire trick behind semantic search."
**Expected result:** `Vector length: 384`, printed floats, no error.
**Approximate wait time:** under 1 second.
**Fallback:** `oc logs -n my-first-model deploy/all-minilm-l6-v2-predictor` if the call errors.
**Cleanup:** None.

---

### Data Scientist Step 8 — Documents

**Persona:** Data Scientist
**Demo mode:** PRE-CREATED — SHOW ONLY.
**What Cursor prepares:** Four short `.txt` files, uploaded into the `documents` bucket in MinIO (reachable via the `company-documents` connection) and also placed on disk inside the workbench under `~/documents/` for quick `!cat` display in a notebook cell. Deliberately short and unambiguous so the RAG answer in Step 13 is obviously correct to the audience.

```
remote-work-policy.txt:
"Employees may work remotely on Monday and Friday. All other workdays require
in-office presence unless approved by a manager in advance."

expenses-policy.txt:
"Employees may expense meals up to $40/day while traveling for business.
Receipts are required for any single expense over $25."

security-policy.txt:
"All laptops must have full-disk encryption enabled and a screen lock timeout
of 5 minutes or less. Multi-factor authentication is required for all corporate
accounts."

onboarding.txt:
"New employees complete IT setup, benefits enrollment, and a 30-minute
security briefing during their first week. A manager-assigned buddy is
available for the first 90 days."
```

**Cursor must prepare before demo:** Create and upload all four files (see `DEMO-PREPARATION.md`).
**I must do during demo:**
1. In JupyterLab, run `!ls -la ~/documents/` then `!cat ~/documents/remote-work-policy.txt`.

**Values to enter:** none.
**What I point at:** the one-sentence remote-work answer inside `remote-work-policy.txt` — "this is the exact fact our final RAG demo is going to retrieve and answer with."
**What I say:** "These are four tiny, realistic company documents — a remote-work policy, an expenses policy, a security policy, and onboarding steps. In a real deployment there'd be thousands; today, four is plenty to prove the mechanism."
**Expected result:** Files list and print correctly.
**Approximate wait time:** instant.
**Fallback:** None needed — trivial file operations.
**Cleanup:** None.

---

### Data Scientist Step 9 — Ingestion

**Persona:** Data Scientist
**Demo mode:** LIVE (from the workbench).
**Current sandbox state:** Documents available locally/in MinIO (Step 8); embedding model reachable (Step 7); `vector-database` connection available (Step 4).
**Cursor must prepare before demo:** Nothing beyond prior steps; optionally pre-install `psycopg2-binary`/`pgvector` Python packages into the workbench image ahead of time so `pip install` isn't run live.
**I must do during demo:** run these cells in order, narrating each:

```python
# 1) Load
import glob
docs = {}
for path in glob.glob("/opt/app-root/src/documents/*.txt"):
    with open(path) as f:
        docs[path.split("/")[-1]] = f.read()
print(list(docs.keys()))

# 2) Chunk (naive: one chunk per doc, since they're already short)
chunks = [{"source": name, "text": text} for name, text in docs.items()]

# 3) Embed
import requests
EMBED_URL = "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings"
for c in chunks:
    r = requests.post(EMBED_URL, json={"model": "all-minilm-l6-v2", "input": c["text"]}, timeout=30)
    c["embedding"] = r.json()["data"][0]["embedding"]

# 4) Store in pgvector
import psycopg2
conn = psycopg2.connect(os.environ["VECTOR_DATABASE_URI"])  # from the connection's injected env var
cur = conn.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS document_chunks (id serial PRIMARY KEY, source text, chunk text, embedding vector(384));")
for c in chunks:
    cur.execute(
        "INSERT INTO document_chunks (source, chunk, embedding) VALUES (%s, %s, %s)",
        (c["source"], c["text"], c["embedding"]),
    )
conn.commit()
print(f"Stored {len(chunks)} chunks.")
```

**Values to enter:** none beyond the code above (adjust the env var name to whatever the URI connection actually injects — confirm with `!env | grep -i uri` first).
**What I point at:** `Stored 4 chunks.` and, optionally, one `SELECT source, chunk FROM document_chunks;` to show the table populated.
**What I say:** "Load, chunk, embed, store — four steps, all in my notebook, all against services someone else already deployed. I'm experimenting freely here — trying different chunk sizes, checking the vectors look reasonable — before I commit to anything permanent."
**Expected result:** Four rows in `document_chunks`, each with a 384-dimension vector.
**Approximate wait time:** a few seconds total (four tiny documents, tiny model).
**Fallback:** If `psycopg2` import fails, `!pip install psycopg2-binary` live (30s) — acceptable fallback, not ideal for a scripted demo.
**Cleanup:** Table persists for the RAG steps later; drop with `DROP TABLE document_chunks;` when fully done.

---

### Data Scientist Step 10 — Pipeline

**Persona:** Data Scientist
**Demo mode:** Mixed — **pipeline server configuration is PRE-CREATED** (object storage backend, unglamorous); **importing the pipeline and starting a run is LIVE**.
**Current sandbox state:** No `DataSciencePipelinesApplication` exists yet in `knowledge-advisor`. Cursor pre-compiles the ingestion pipeline (a KFP Python DSL turning Step 9's four cells into `load → chunk → embed → store` components) into a ready-to-import YAML file, `pipelines/document-ingestion-pipeline.yaml`.
**Cursor must prepare before demo:**
1. Compile the pipeline YAML (`kfp` SDK, `@dsl.pipeline` with four components matching Step 9's logic).
2. Optionally pre-configure the pipeline server too, if you'd rather skip straight to importing — but configuring it live is fast (one form, no waiting) and demonstrates the connection between Pipelines and object storage nicely, so it's listed as LIVE below by default.
**I must do during demo:**
1. Click **Projects → knowledge-advisor → Pipelines → Configure pipeline server**.
2. Fill in the **Object storage connection** section using the pre-created MinIO connection (reuse `company-documents`'s underlying credentials, or a dedicated `pipeline-artifacts` connection pointed at bucket `pipelines` — recommended, to keep docs and pipeline artifacts separate).
3. Click **Configure pipeline server**. Wait ~30–60s for the pipeline server pods to come up.
4. Click **Develop & train → Pipelines → Pipeline definitions → Import pipeline**.
5. Fill in Pipeline name / description, choose **Upload a file**, select `document-ingestion-pipeline.yaml`.
6. Click **Import**.
7. Click **Develop & train → Experiments → (the imported pipeline's experiment) → Create run**, select the pipeline + version, click **Create run**.
8. Open the run and point at the graph: **Load → Chunk → Embed → Store**.

**Values to enter:**

| Field | Value |
|---|---|
| Object storage — Access key | `<MINIO_ACCESS_KEY>` |
| Object storage — Secret key | `<MINIO_SECRET_KEY>` |
| Object storage — Endpoint | `http://minio.knowledge-advisor.svc.cluster.local:9000` |
| Object storage — Region | `us-east-1` |
| Object storage — Bucket | `pipelines` |
| Pipeline name | `document-ingestion-pipeline` |
| Pipeline description | `Load, chunk, embed, and store company documents into pgvector.` |

**What I point at:** the four-node run graph, each node turning green as it completes, then the final **Succeeded** status.
**What I say:** "I experimented in the workbench first — that's where I figured out the logic. Now I've turned it into a Pipeline: the exact same four steps, but repeatable, schedulable, and auditable. Anyone on my team can re-run this the moment we add a fifth policy document, without touching a notebook."
**Expected result:** Pipeline server `Ready`; pipeline imported; run completes with all four steps `Succeeded`; new rows appear (or are refreshed) in `document_chunks`.
**Approximate wait time:** ~30–60s to configure the pipeline server; ~10–20s for the run itself (tiny data).
**Fallback:** If the run fails, fall back to re-running the Step 9 notebook cells live and explain "the pipeline packages this same logic — think of it as CI/CD for this exact code."
**Cleanup:** Leave the pipeline server and run history in place — useful as a talking point for repeatability.

---

### Data Scientist Step 11 — Create OGXServer

**Persona:** Data Scientist
**Demo mode:** **TERMINAL STEP (Import YAML)** — confirmed no dashboard wizard exists for creating an `OGXServer`. Red Hat's own documented procedure is literally "open the OpenShift Console → Import YAML."
**Current sandbox state:** `ogx: Managed` platform-wide (Admin Step 10); no `OGXServer` instance exists yet; Postgres (Step 3) and the Llama model (Admin Step 5) are both reachable.
**Cursor must prepare before demo:** Nothing — this should be created live, it's fast (~20–30s to reconcile) and is the single most important "aha" resource of Maya's section.
**I must do during demo:**
1. Open the **OpenShift Console** (not the RHOAI dashboard) → top-right **+** icon → **Import YAML**.
2. Make sure the **Project** selector (top of console) is set to `knowledge-advisor`.
3. Paste the YAML below and click **Create**.

```yaml
apiVersion: ogx.io/v1beta1
kind: OGXServer
metadata:
  name: knowledge-advisor-ogx
  namespace: knowledge-advisor
spec:
  distribution:
    name: rh-dev
  workload:
    replicas: 1
    overrides:
      env:
        - name: VLLM_URL
          value: 'https://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local/v1'
        - name: INFERENCE_MODEL
          value: llama-32-3b-instruct
        - name: VLLM_TLS_VERIFY
          value: 'false'
        - name: POSTGRES_HOST
          value: pgvector-db.knowledge-advisor.svc.cluster.local
        - name: POSTGRES_PORT
          value: '5432'
        - name: POSTGRES_DB
          value: ogx
        - name: POSTGRES_USER
          value: ragadmin
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              key: password
              name: pgvector-db-credentials
```

**Values to enter:** as shown in the YAML above (model endpoint, Postgres coordinates).
**What I point at:** after creation, `oc get ogxserver -n knowledge-advisor` showing `Ready=True` within ~20–30 seconds; then pivot to the dashboard — **Gen AI studio → Playground**, select project `knowledge-advisor`, point at the newly available server/model in the dropdown.
**What I say:** "This is the one piece of today's demo that genuinely has no button yet — OGX is brand new, so for now, creating a server instance means importing a YAML file, right in the OpenShift console. Twenty seconds later, it's live, and everything downstream — the Playground, agent config, tracing — lights up in my project specifically, because I told it exactly which model and which database to use."
**Expected result:** `OGXServer/knowledge-advisor-ogx` reaches `Ready=True`; a new pod appears in `knowledge-advisor`; Gen AI Studio Playground for this project now shows populated Agent config / Tracing / Prompt management tabs (Admin Step-enabled flags, previously empty).
**Approximate wait time:** 20–30 seconds to reconcile.
**Fallback:** If it doesn't reach Ready, check `oc describe ogxserver knowledge-advisor-ogx -n knowledge-advisor` and `oc logs -n knowledge-advisor deploy/knowledge-advisor-ogx` — most likely cause is a Postgres connectivity/credential typo; have a pre-verified-working copy of this YAML saved in a file (`yaml/ogx-server-knowledge-advisor.yaml`) so you can `oc apply -f` it instead of retyping under pressure.
**Cleanup:** Leave running for the rest of the demo (Playground/RAG steps use it).

---

### Data Scientist Step 12 — Playground

**Persona:** Data Scientist
**Demo mode:** LIVE.
**Current sandbox state:** `llama-32-3b-instruct` and `all-minilm-l6-v2` both exist as AI asset endpoints; `OGXServer` now `Ready` in `knowledge-advisor` (Step 11).
**Cursor must prepare before demo:** Nothing.
**I must do during demo:**
1. Click **Gen AI studio → Playground**.
2. Select project `knowledge-advisor` from the **Project** dropdown.
3. Click **Create playground** (first time) — the **Configure playground** dialog opens.
4. Select model **llama-32-3b-instruct**, Type = **Inference**; optionally also select **all-minilm-l6-v2**, Type = **Embedding**.
5. Click **Create**.
6. In the chat input, type: `What is our company's remote work policy?` and click **Send** — **before** any document context is added, to show the baseline.

**Values to enter:**

| Field | Value |
|---|---|
| Project | `knowledge-advisor` |
| Model 1 | `llama-32-3b-instruct` — Type: Inference |
| Model 2 (optional) | `all-minilm-l6-v2` — Type: Embedding |

**What I point at:** the model name shown in the chatbot header, and the (likely vague/generic, non-specific) answer to the un-augmented question.
**What I say:** "This is the Playground — a sandbox for talking to any model my project has access to, side by side if I want to compare. Watch what happens when I ask about our specific company policy without giving it anything to work with: [read the generic answer]. It has no idea, because it was never trained on our documents. That's exactly the gap we're about to close."
**Expected result:** Playground loads with the model in the header; the un-augmented answer is generic or an explicit "I don't have that information."
**Approximate wait time:** a few seconds for the playground to load; a few seconds for the response.
**Fallback:** If model selection is empty, verify the model has the "AI asset" checkbox checked in its deployment (Admin Steps 5/6).
**Cleanup:** None — leave the playground open for Step 13.

---

### Data Scientist Step 13 — RAG

**Persona:** Data Scientist
**Demo mode:** LIVE.
**Current sandbox state:** `document_chunks` table populated (Steps 9/10); Playground open with `llama-32-3b-instruct` (Step 12).
**Honest implementation note:** RHOAI 3.5's Playground does not (as documented) have a single-click "enable RAG" toggle — retrieval is something *your application* (or `OGXServer`'s own API) does before calling the chat model. So this step performs retrieval explicitly, in the open, which is actually the better teaching moment: the audience *sees* the mechanism instead of trusting a black box.
**Cursor must prepare before demo:** Nothing further.
**I must do during demo:**
1. Back in the workbench (or a second browser tab), run:

```python
question = "Which days can employees work remotely?"

# Embed the question the same way we embedded the documents
r = requests.post(EMBED_URL, json={"model": "all-minilm-l6-v2", "input": question}, timeout=30)
q_vector = r.json()["data"][0]["embedding"]

# Retrieve the closest chunk from pgvector
cur.execute(
    "SELECT source, chunk FROM document_chunks ORDER BY embedding <-> %s::vector LIMIT 1;",
    (q_vector,),
)
source, retrieved_chunk = cur.fetchone()
print(f"Retrieved from {source}:\n{retrieved_chunk}")
```

2. Point at the printed retrieved chunk: `Employees may work remotely on Monday and Friday.`
3. Switch to the Playground tab, and send this augmented prompt:
   `Context: "Employees may work remotely on Monday and Friday." \n\nQuestion: Which days can employees work remotely?`
4. Point at Llama's final answer.

**Values to enter:** the question and augmented prompt above.
**What I point at:** first the retrieved chunk printed in the notebook (proving *where* the fact came from), then the model's grounded final answer in the Playground (proving it used that fact correctly).
**What I say:** "First, we retrieve — a plain vector similarity search finds the one sentence, out of our four documents, that's semantically closest to the question. Then, we augment — we hand that sentence to the model as context. Then, the model generates. We did not retrain the LLM. We did not fine-tune anything. We retrieved private company information at request time and added it to the prompt as context. That's the entire idea behind retrieval-augmented generation."
**Expected result:** Retrieved chunk is exactly the remote-work sentence; final answer correctly states "Monday and Friday."
**Approximate wait time:** under 2 seconds for retrieval; a few seconds for the model response.
**Fallback:** If the vector search returns the wrong chunk (unlikely with only 4 documents), just show the raw distances (`embedding <-> %s::vector`) for all four rows to prove the remote-work one is genuinely closest, and use it directly.
**Cleanup:** None.

---

### Data Scientist Step 14 — Simple application

**Persona:** Data Scientist
**Demo mode:** PRE-CREATED + SHOW ONLY.
**What Cursor prepares:** A small Streamlit app, "Knowledge Advisor," implementing exactly the Step 13 logic (embed question → pgvector similarity search → augmented prompt → MaaS call → display answer) as a single `app.py`, built into a container image and deployed as an OpenShift `Deployment` + `Service` + `Route` inside `knowledge-advisor`. Built ahead of time because a live `oc new-app`/build/push cycle takes several minutes and has nothing to teach beyond what Steps 9–13 already showed.
**Current sandbox state (after prep):** Route `knowledge-advisor-app-knowledge-advisor.apps.ocp.tfmbf.sandbox2633.opentlc.com` live, app `Running`.
**I must do during demo:**
1. Open the app's Route URL in a browser tab.
2. Type into the input box: `Which days can I work remotely?`
3. Click **Ask**.

**Values to enter:**

| Field | Value |
|---|---|
| Question input | `Which days can I work remotely?` |

**What I point at:** the answer rendered in the app UI — `Employees may work remotely on Monday and Friday.` — and say "same pipeline, same two models, same governed MaaS endpoint, now behind a two-hour Streamlit UI instead of my notebook."
**What I say:** "This is what I'd hand to an actual employee — not a notebook, not a curl command. It talks to exactly the same backend we just built: it embeds the question with the CPU model, searches pgvector, and sends the augmented prompt to Llama through the same governed MaaS endpoint Alex configured. Nothing new was deployed for this app — it's just a thin UI over infrastructure that already existed."
**Expected result:** App renders a correct, grounded answer in under a few seconds.
**Approximate wait time:** instant to load; a few seconds per question.
**Fallback:** If the Route is unreachable, fall back to running `streamlit run app.py` locally inside the workbench and use the JupyterLab proxy URL instead.
**Cleanup:** Leave running; low resource footprint (CPU-only, no GPU).

---

### Data Scientist Step 15 — MLflow

**Persona:** Data Scientist
**Demo mode:** LIVE.
**Current sandbox state:** MLflow enabled platform-wide (Admin Step 9), no experiments logged yet.
**Cursor must prepare before demo:** Nothing — logging one real run live is fast and is the whole point of this step.
**I must do during demo:**
1. Back in the workbench, run:

```python
import mlflow, time

mlflow.set_experiment("knowledge-advisor-rag")
with mlflow.start_run(run_name="baseline-run"):
    start = time.time()
    # (reuse the retrieval + generation call from Step 13)
    latency_ms = (time.time() - start) * 1000
    mlflow.log_param("chunk_size", "whole-document (4 docs)")
    mlflow.log_param("top_k", 1)
    mlflow.log_param("embedding_model", "all-MiniLM-L6-v2")
    mlflow.log_param("llm", "llama-32-3b-instruct")
    mlflow.log_metric("latency_ms", latency_ms)
print("Run logged.")
```

2. Click **Develop & train → Experiments (MLflow) → knowledge-advisor-rag**.
3. Click the run, point at the **Parameters** and **Metrics** panels.

**Values to enter:** as shown in the code (`chunk_size`, `top_k`, `embedding_model`, `llm`, `latency_ms`).
**What I point at:** the run detail page showing all five logged values.
**What I say:** "Instead of relying on notebook history or my own memory of 'which settings did I use last time,' I log every real attempt. Next time I try a different chunk size or a different top-k, I get a second row here, and I can compare them side by side instead of guessing."
**Expected result:** New experiment `knowledge-advisor-rag` with one run, showing the five logged values.
**Approximate wait time:** under 2 seconds to log; instant to view.
**Fallback:** `mlflow.set_tracking_uri(...)` explicitly if autoconfiguration via the workbench annotation didn't apply (rare — only if the workbench was created before MLflow was enabled).
**Cleanup:** Leave the run in place — good artifact to leave behind after the demo.

---

### Data Scientist Step 16 — MCP Catalog

**Persona:** Data Scientist
**Demo mode:** PRE-CREATED + SHOW ONLY (browse only — deployment intentionally disabled).
**Current sandbox state:** `dashboardConfig.mcpCatalog: true`, `dashboardConfig.mcpRegistry: true`. No `MCPServer` CRD exists on this cluster (MCP Lifecycle Operator was deliberately not installed — it requires OpenShift 4.22+, this cluster is 4.20.36).
**Cursor must prepare before demo:** Nothing further.
**I must do during demo:**
1. Click **AI hub → MCP servers → Catalog** tab.
2. Click any server card, e.g. **Red Hat OpenShift** or **EDB Postgres AI**.
3. Point at the (grayed-out) **Deploy** button.

**Values to enter:** none.
**What I point at:** the catalog cards (Red Hat OpenShift, Ansible Automation Platform, Red Hat Insights, Confluent Cloud, EDB Postgres AI, HashiCorp Terraform, Microsoft Azure, Dynatrace, MongoDB, MariaDB), and the disabled **Deploy** button specifically.
**What I say:** "Retrieval-augmented generation gave our assistant *knowledge* — static documents. MCP is the next layer: it gives an agent *tools*, live access to running systems, like querying a database or checking a cluster's health, in real time. Red Hat ships a curated catalog of these — this button would deploy one directly, but it's greyed out here on purpose: the operator that manages MCP server lifecycle needs a newer OpenShift release than this sandbox runs. This is a look at what's coming, not a working feature yet on this exact cluster."
**Expected result:** Catalog renders with server cards; Deploy button visibly disabled/grayed with a tooltip explaining why.
**Approximate wait time:** instant.
**Fallback:** None needed — this is inherently a look-don't-touch step.
**Cleanup:** None.

---

### Data Scientist Step 17 — Agents Catalog

**Persona:** Data Scientist
**Demo mode:** PRE-CREATED + SHOW ONLY.
**Current sandbox state:** `dashboardConfig.agentsCatalog: true`. Pure navigation/templates catalog — no deploy backend exists.
**Cursor must prepare before demo:** Nothing further.
**I must do during demo:**
1. Click **AI hub → Agents** in the left nav.
2. Point at the **Developer Preview** banner at the top of the page.
3. Click into one starter kit, e.g. **LangGraph** or **CrewAI**.

**Values to enter:** none.
**What I point at:** the Developer Preview banner, and the starter-kit's description/README-style content — explicitly note there is no **Deploy** button on this page at all, only links/templates.
**What I say:** "One last look forward: an Agents Catalog of starter kits — LangGraph, LlamaIndex, CrewAI, AutoGen, and a few others — each one a template you'd clone to bootstrap an agentic application using everything we just built: the shared model, MaaS governance, OGX, and MCP tools. It's Developer Preview, so I'm not going to pretend to build an agent live — but this is exactly where today's story is heading next."
**Expected result:** Agents Catalog page renders with the Developer Preview banner and at least one starter-kit template visible.
**Approximate wait time:** instant.
**Fallback:** None needed.
**Cleanup:** None.

---

## End of runbook

Total new live-clickable moments: project creation ×2, connections ×2, workbench (optional live), MaaS API call, embedding call, ingestion notebook, pipeline run, `OGXServer` Import YAML, Playground chat ×2, MLflow run, Streamlit app. Everything GPU-bound or slow-loading is pre-created and shown, never created live, per your stated risk preference.
