# Proof of Demo 1 publication (sanitized)

**Cluster:** `api.ocp.sv8wx.sandbox2633.opentlc.com` (disposable sandbox)  
**Captured:** 2026-10-22  

## Platform

| Check | Result |
|---|---|
| OpenShift | `4.20.42` |
| RHOAI | `rhods-operator.3.5.2` |
| RHCL | `rhcl-operator.v1.4.4` Succeeded |
| Kuadrant | Ready=True |
| `ModelsAsAServiceReady` | **True** |
| `AIGatewayReady` | **True** |
| Gateway `maas-default-gateway` | Programmed=True |
| Infra ns | `redhat-ai-gateway-infra` (`maas-db-config` present; value not exported) |
| UWM | prometheus-user-workload Running |

## Native model

| Check | Result |
|---|---|
| Kind / API | `LLMInferenceService` `serving.kserve.io/v1alpha2` |
| Name / ns | `demo-simulator` / `rhoai-maas-demo` |
| Ready | **True** (`LLMInferenceServiceReady`) |
| Pod | `demo-simulator-kserve-…` 1/1 Running |
| Serving image | `ghcr.io/llm-d/llm-d-inference-sim:v0.7.1` (CPU simulator) |
| Gateway ref | `maas-default-gateway` / `openshift-ingress` |
| HTTPRoute | `demo-simulator-kserve-route` created by controller |

## MaaSModelRef (declarative publication)

| Field | Value |
|---|---|
| Name / ns | `demo-simulator` / `rhoai-maas-demo` (same as backend) |
| `spec.modelRef.kind` | `LLMInferenceService` |
| `spec.modelRef.name` | `demo-simulator` |
| `RuntimeReady` | **True** — “Backend is healthy” |
| `GovernanceAttached` | False — “No active subscription and auth policy pairing found” |
| `Ready` / `phase` | False / `Pending` — “Awaiting governance pairing” |

**Interpretation:** Demo 1 publication CR is present and bound to a healthy native backend. On this 3.5.2 build, overall `MaaSModelRef` Ready requires **Demo 2** `MaaSSubscription` + `MaaSAuthPolicy` pairing. That pairing was **not** created (per Demo 1 scope). This is reported as an expected platform gate, not invented success.

Publication method: **CLI/GitOps** (`oc apply` of `manifests/maas/maas-model-ref.yaml`), not the dashboard checkbox.

## Untouched shared resources

| Resource | Status after Demo 1 |
|---|---|
| `my-first-model/llama-32-3b-instruct` InferenceService | Still Ready=True |
| `openshift-ai-inference` / `data-science-gateway` Gateways | Not modified |
| `vLLMDeploymentOnMaaS` | Not enabled (Technology Preview) |

## Local proof files (gitignored or sanitized)

- `docs/proof-llmis.yaml`
- `docs/proof-maasmodelref.yaml`
- `docs/proof-httproute.yaml`
- `docs/proof-dsc-status.txt`
- `docs/proof-pods.txt`
- `docs/proof-legacy-untouched.txt`

## Reproduce verify

```bash
bash scripts/50-verify.sh
bash scripts/50-verify.sh
```
