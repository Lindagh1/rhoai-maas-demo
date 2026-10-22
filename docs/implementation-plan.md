# Implementation plan — Demo 1 (native path only)

## Goal

`LLMInferenceService` (llm-d) → `MaaSModelRef` → model visible/published in MaaS.

**Out of scope (Demo 2):** `MaaSSubscription`, `MaaSAuthPolicy`, groups, API keys, curl auth, quotas, revocation.

## Model choice (after GPU measurement)

| Option | Feasible now? | Decision |
|---|---|---|
| GPU instruct model via llm-d (e.g. small Granite / Llama) | **No** — L4 fully allocated to `my-first-model/llama-32-3b-instruct` | Deferred; requires explicit approval to scale down that ISVC |
| CPU `llm-d-inference-sim` as `LLMInferenceService` | **Yes** — server dry-run accepted on `serving.kserve.io/v1alpha2` | **Selected for Demo 1** |
| ExternalProvider / ExternalModel wrapping legacy ISVC | Feasible but forbidden by Demo 1 brief | Rejected |
| vLLM-on-MaaS dashboard TP | Feasible after flag | Rejected (Technology Preview; must not be silent fallback) |

Simulator uses synthetic completions; it proves the **native CR path and MaaS publication**, not production inference quality.

## Minimal change set (in order)

1. **Prerequisites (`scripts/10-prerequisites.sh`)**
   - Enable User Workload Monitoring (`cluster-monitoring-config`).
   - Create `GatewayClass/openshift-default` (additive; do not alter existing classes).
   - Install RHCL Subscription `stable-1.4` → `openshift-operators`.
   - Create `kuadrant-system` + Authorino Service annotation + `Kuadrant` CR; wait Ready.
   - Configure Authorino TLS per RHOAI 3.5 §1.4.

2. **MaaS enable (`scripts/20-enable-maas.sh`)**
   - Create `maas-default-gateway` from template (hostname from live cluster domain; cert from ingress defaultCertificate; route selector label — **not** `from: All`).
   - Provision demo Postgres in `redhat-ods-applications` (secrets generated at runtime, never committed).
   - Patch DSC: `aigateway.managementState=Managed` + `modelsAsAService.managementState=Managed` (leave deprecated `kserve.modelsAsService=Removed`).
   - Ensure dashboard `modelAsService=true` (already true); do **not** set `vLLMDeploymentOnMaaS`.
   - Wait for MaaS CRDs + infra namespace; write `maas-db-config` into discovered infra ns; wait tenant Ready / `ModelsAsAServiceReady=True`.

3. **Native model (`scripts/30-deploy-native-model.sh`)**
   - Namespace `rhoai-maas-demo` labeled for gateway access.
   - Apply `LLMInferenceService` `demo-simulator` (v1alpha2); wait Ready/Running.

4. **Publish (`scripts/40-publish-maas.sh`)**
   - Apply declarative `MaaSModelRef` (`kind: LLMInferenceService`) in the **same** namespace.
   - Wait Ready. Document as CLI/GitOps publication (not dashboard checkbox).

5. **Verify (`scripts/50-verify.sh`)** — run twice for idempotence.

6. **Cleanup (`scripts/99-cleanup.sh`)** — demo-owned resources only; requires `CONFIRM=yes`. **Not** part of setup.

## Anticipated mutations (cluster-scoped)

| Resource | Why |
|---|---|
| Subscription `rhcl-operator` | Official MaaS + llm-d dependency |
| GatewayClass `openshift-default` | Docs name; existing classes are owned elsewhere |
| Gateway `maas-default-gateway` | Required MaaS gateway (new) |
| ConfigMap `cluster-monitoring-config` | UWM required or MaaS Degraded |
| DSC `default-dsc` aigateway fields | Enable MaaS control plane |
| Namespace `kuadrant-system`, `rhoai-maas-demo`, possibly `models-as-a-service` / infra (operator-created) | Platform / demo |

**Will not mutate:** existing Gateways, legacy ISVC, GPU ClusterPolicy, RHOAI Operator channel/version, RHCL downgrade/upgrade once installed.

## Dependencies

```
UWM ─┐
RHCL → Kuadrant → Authorino TLS ─┐
GatewayClass + maas-default-gateway ─┼→ DSC aigateway.modelsAsAService → infra ns + maas-db-config
Postgres ──────────────────────────┘         ↓
                                    LLMInferenceService → MaaSModelRef
```

## Docs used (RHOAI 3.5)

- https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service (§1.2–1.7, 1.9–1.10, 1.17)
- https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference
- https://access.redhat.com/articles/rhoai-supported-configs

## Risks / assumptions

- Sandbox pull access to `ghcr.io/llm-d/llm-d-inference-sim` and `registry.redhat.io/rhel9/postgresql-16`.
- Enabling aigateway may briefly reconcile RHOAI components; existing `my-first-model` must stay untouched.
- If RHCL install fails (catalog/RBAC), stop and report — no TP fallback.
