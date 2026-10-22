# Demo 1 runbook — Native llm-d serving + MaaS publication

## What this demo proves

Platform admin path:

1. Deploy a model with native **`LLMInferenceService`** (llm-d).
2. Publish it with **`MaaSModelRef`** (`spec.modelRef.kind: LLMInferenceService`).
3. Show it in the RHOAI dashboard / MaaS UI.

**Not in this demo:** subscriptions, auth policies, API keys, quota, revocation (Demo 2).

## Prerequisites on a fresh sandbox

- Disposable OpenShift sandbox with RHOAI 3.5.x
- `oc` logged in as cluster-admin (`oc login …` — never commit tokens)
- Network pull to Red Hat registries + `ghcr.io/llm-d/llm-d-inference-sim`
- This Git repository

## Reproduce from zero

```bash
# 1) Login (token stays in your shell history / kubeconfig — not in git)
oc login --server="$SANDBOX_API" --token="$SANDBOX_TOKEN" --insecure-skip-tls-verify=true

# 2) Audit (read-only)
bash scripts/00-audit.sh
# Review docs/sandbox-audit-raw.txt and docs/sandbox-audit.md

# 3) Install missing pieces + deploy + publish
bash scripts/10-prerequisites.sh
bash scripts/20-enable-maas.sh
bash scripts/30-deploy-native-model.sh
bash scripts/40-publish-maas.sh

# 4) Verify twice (idempotence)
bash scripts/50-verify.sh
bash scripts/50-verify.sh
```

Optional cleanup (demo-owned only):

```bash
CONFIRM=yes bash scripts/99-cleanup.sh
```

## Live click-by-click (customer demo)

1. Open **RHOAI dashboard**  
   `https://rhods-dashboard-redhat-ods-applications.<cluster-domain>`
2. Go to **Data Science Projects** → open **`rhoai-maas-demo`**.
3. Open **Models** / model deployments and select **`demo-simulator`**.
4. Point out it is an **`LLMInferenceService`** (llm-d native), not a legacy `InferenceService`.
5. Show **Publish as MaaS** / MaaS publication state.  
   **Say clearly:** publication was applied **declaratively** via `MaaSModelRef` (`oc apply`), same CR the dashboard checkbox would create — we did not click the checkbox in this run.
6. Optionally open the MaaS UI (`maas-ui` / Gen AI Studio models catalog) and show the published model entry.
7. CLI proof (sanitized):

```bash
oc get llminferenceservice -n rhoai-maas-demo
oc get maasmodelref -n rhoai-maas-demo -o yaml | grep -A3 modelRef
```

## Model note (GPU)

This sandbox has **one NVIDIA L4**, fully used by legacy `my-first-model/llama-32-3b-instruct`. Demo 1 therefore uses **CPU `llm-d-inference-sim`**. To show a real GPU llm-d model later, free that GPU (with owner approval) and replace the LLMIS manifest — do not use ExternalModel.

## Success criteria checklist

- [ ] `ModelsAsAServiceReady=True`
- [ ] `LLMInferenceService/demo-simulator` Ready
- [ ] `MaaSModelRef` same namespace, `kind: LLMInferenceService`, `RuntimeReady=True`
- [ ] `scripts/50-verify.sh` passes twice
- [ ] No `vLLMDeploymentOnMaaS` / ExternalModel used

### Known platform gate (not Demo 1 failure)

On RHOAI 3.5.2, `MaaSModelRef.status.phase` stays `Pending` with message **Awaiting governance pairing** until a `MaaSSubscription` + `MaaSAuthPolicy` pair exists. That is **Demo 2**. Do not create those objects in Demo 1 unless the customer expands scope.
