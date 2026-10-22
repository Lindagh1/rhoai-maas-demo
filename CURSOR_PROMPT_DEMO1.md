# Cursor Agent — RHOAI 3.5 MaaS Sandbox: Native Demo 1

You are a senior Red Hat OpenShift AI 3.5 / OpenShift / llm-d / MaaS platform engineer. Work in the repository opened in Cursor and in the currently selected, explicitly authorized temporary Red Hat sandbox only. Do not assume anything is installed. Your mission is to prepare a fully repeatable and idempotent Demo 1 of **native model serving and MaaS publication**:

    LLMInferenceService (llm-d) -> MaaSModelRef -> discoverable/published model in MaaS

The customer already integrated a legacy KServe InferenceService through ExternalProvider + ExternalModel. We want to show the **native** path WITHOUT either ExternalProvider or ExternalModel. **Do not implement Demo 2 / end-user self-service yet.** The later Demo 2 will add MaaSSubscription, MaaSAuthPolicy, group, API keys, curl, quota enforcement, and revocation; preserve compatibility with that future work.

## Authoritative references — use the 3.5 version, not old 3.3/3.4 tutorials

1. https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service
   - §1.2 Platform and Operator prerequisites
   - §1.3 Gateway requirements
   - §1.4 TLS
   - §1.5 PostgreSQL secret
   - §1.6 MaaS configuration
   - §1.7 Dashboard configuration
   - §1.9 Verification
   - §1.10 Deploy models with MaaS
   - §1.17 CLI/CR workflow
2. https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference
3. https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploy_models_using_distributed_inference_with_llm-d/configuring-authentication-for-llmd_distributed-inference
4. https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install
5. https://access.redhat.com/articles/rhoai-supported-configs

You MUST reconcile version-specific requirements with the ACTUAL sandbox and CRD schemas. For example: RHOAI 3.5 uses `spec.components.aigateway.modelsAsAService.managementState` instead of legacy `kserve.modelsAsService`; the MaaS DB secret belongs in the infrastructure namespace (often `redhat-ai-gateway-infra`, verify `MaasTenantConfig.status.infraNamespace`); distributed llm-d serving has its own OpenShift compatibility requirements. Never copy unsupported old-version manifests.

## Stage A — audit (READ ONLY, run first)

- Verify `oc` login, cluster context, current project, permissions, OpenShift version, RHOAI version, Operator channels/CSVs. Abort cluster changes if the context is not the intended disposable sandbox.
- Inspect `DataScienceCluster`, `DSCInitialization`, `OdhDashboardConfig`, serving components, models and model storage; inspect *spec*, *status*, and Events, NOT Kubernetes secret contents.
- Detect GPUs by node allocatable and actual free capacity, GPU operator/device plugin, hardware profiles, Node Feature Discovery; detect CPU, memory, PersistentVolumeClaims/StorageClasses, model source available (PVC/S3/OCI/URI) and registry pull access. Do not assume Granite 8B fits available GPU.
- Check llm-d and `LLMInferenceService` availability, KServe, necessary Operators (including RHCL 1.4.x, Kuadrant, cert-manager and any required dependencies) and `GatewayClass`/`Gateway` routing (`openshift-ai-inference` for serving; `maas-default-gateway` for MaaS), TLS, ingress and hostname.
- Check PostgreSQL 14+ readiness and connectivity without outputting connection strings or secret data; look up the actual MaaS infra namespace, validate secret **existence only** and the `ModelsAsAServiceReady` status, Gateway and dashboard flags.
- Detect whether an existing native model and/or MaaSModelRef can be safely REUSED instead of redeploying.
- Record findings in `docs/sandbox-audit.md` with a table: requirement | observed value/version | pass/fail/unknown | supporting command | remediation. List blockers, high-risk conflicts, and GPU capacity. Mask cluster URLs, user names and all sensitive values from exported reports when appropriate.
- Run the provided `scripts/00-audit.sh` as a starting point and extend it with non-destructive checks as needed. If `oc` login is missing, show the user exactly how to authenticate; NEVER ask them to paste tokens into chat or commit credentials.

## Stage B — compute a minimal, supported installation plan

- Choose the smallest valid CHANGE SET to reach Demo 1; reuse what already works.
- First preference: GA **llm-d native** serving using `LLMInferenceService` and publishing to MaaS. Do not silently fall back to vLLM MaaS Technology Preview or an ExternalModel if GA llm-d is impossible. Report a blocker and an optional alternative separately.
- Pick a supported small instruct model only after measuring GPU VRAM/resource quotas/model storage. Document storage source, artifact access, legal/registry requirements and resource requests. No invented checkpoint path or storage credentials.
- Before writing YAML, query the installed schemas using `oc explain` and `oc get crd ... -o json`; use official 3.5 examples, and validate with `oc apply --dry-run=server` when possible.
- Avoid re-installing Operators just because a tutorial shows them. Check OLM subscriptions, version compatibility and ownership first. Do not upgrade/downgrade existing RHOAI, RHCL or OpenShift Operators without an explicit warning and user approval.
- Provide a concise actionable plan in `docs/implementation-plan.md`, with dependencies and anticipated mutations.

## Stage C — implement and EXECUTE reproducibly (only after audit confirms intended sandbox)

Build a Git repository whose scripts work for each fresh sandbox, including (naming can be adjusted):

- `scripts/00-audit.sh` (read-only)
- `scripts/10-prerequisites.sh` (idempotently prepares missing required supported components, if safe and authorized)
- `scripts/20-enable-maas.sh` (idempotent MaaS infrastructure configuration; use actual infrastructure namespace)
- `scripts/30-deploy-native-model.sh` (creates/uses a dedicated demo namespace and `LLMInferenceService` with llm-d)
- `scripts/40-publish-maas.sh` (creates/validates native `MaaSModelRef` referencing the LLMInferenceService)
- `scripts/50-verify.sh` (re-run after any fresh sandbox)
- `scripts/99-cleanup.sh` (only resources owned by this demo; requires an explicit confirmation parameter; DO NOT RUN as part of setup)
- `manifests/` (version-validated declarative YAML/templates, redacted)
- `README.md`, `.gitignore`, `docs/sandbox-audit.md`, `docs/implementation-plan.md`, `docs/demo1-runbook.md`, `docs/troubleshooting.md`.

Make scripts `set -euo pipefail`, safe to re-run, with good readiness waits, meaningful logs and exit codes; separate secrets from the repo (interactive env vars / approved Secret manager, never plain committed YAML); do not use `curl -k` as a permanent workaround; no wholesale Operator uninstall, no broad cluster deletion, no modifications outside necessary demo scope. Detect actual namespaces and avoid hardcoded cluster hostnames and credentials. Every new cluster-scoped change needs a recorded rationale. Avoid cluster-wide `allowedRoutes.namespaces.from: All` if narrower route policies suffice. Do not overwrite existing shared Gateway, AuthPolicy, network policies, TLS settings or database configurations blindly.

**Demo 1 success criteria (all required, with evidence):**
1. RHOAI, required dependencies and default MaaS tenant are healthy; `ModelsAsAServiceReady=True` where applicable.
2. GPU and model storage are sufficient; a supported `LLMInferenceService` with llm-d is Ready (not just CR created).
3. A `MaaSModelRef` exists in the SAME namespace as its backend, with `spec.modelRef.kind: LLMInferenceService` and the correct backend name.
4. Show the model from the RHOAI dashboard, preferably including the "Publish as MaaS" option. **Important:** if you create the MaaSModelRef via CLI, explain this is declarative publication; do not claim the dashboard generated it.
5. Validate model availability/route and a documented smoke test where possible without bypassing platform authentication.
6. Run `scripts/50-verify.sh` twice to establish idempotence; capture sanitized output.
7. Explain exactly how to reproduce from a NEW sandbox using only the repo + access to its cluster + separately supplied secrets/model artifacts.

Stop and explain when blocked by permissions, missing GPUs, unavailable operator catalogs, absent S3/PVC/model artifacts, or unsupported software versions. Do not manufacture successful results. If a platform component is Technology Preview, label it, never call it GA. Do not run any work for Demo 2 yet.

## Final answer expected from Cursor

- Actual detected cluster version / RHOAI / RHCL / GPU capacity
- What existed, what changed and why
- Commands executed and all relevant statuses
- Which demo stage is operational vs blocked
- Reproduction command(s) and files created
- Exact click-by-click live demo path
- Remaining assumptions and risks
- URLs to the exact official Red Hat documentation used

Begin NOW with the read-only sandbox audit, not with a speculative installation.
