# Sandbox audit — Demo 1 (native LLMInferenceService → MaaS)

**Date:** 2026-10-22  
**Cluster (redacted):** `api.ocp.sv8wx.sandbox2633.opentlc.com`  
**Identity:** `admin` (cluster-admin)  
**Method:** read-only `oc get` / `oc explain` / `oc describe` / server dry-run. No secret values inspected.  
**Raw capture:** `docs/sandbox-audit-raw.txt` (gitignored)

## Summary

| Area | Verdict |
|---|---|
| Intended disposable sandbox | **PASS** — logged into `sv8wx.sandbox2633` |
| OpenShift / RHOAI versions | **PASS** — OCP `4.20.42`, RHOAI `3.5.2` |
| Native llm-d CRD (`LLMInferenceService`) | **PASS** — CRD present (`serving.kserve.io/v1alpha2`), 0 instances |
| MaaS control plane | **FAIL** — `aigateway` unset; `ModelsAsAServiceReady=False` (Removed); no MaaS CRDs |
| RHCL / Kuadrant | **FAIL** — Operator not installed; no `Kuadrant` CR; DSC reports `KserveLLMInferenceServiceDependencies=False` (“Red Hat Connectivity Link not installed”) |
| Gateway for MaaS | **FAIL** — `maas-default-gateway` missing; `openshift-default` GatewayClass missing |
| PostgreSQL / `maas-db-config` | **FAIL** — infra ns `redhat-ai-gateway-infra` absent; no MaaS DB |
| User Workload Monitoring | **FAIL** — ns exists, no pods; `enableUserWorkload` not configured |
| GPU hardware | **PASS** — 1× NVIDIA L4 (23 GiB), driver/plugin Ready |
| GPU free capacity for a new GPU model | **FAIL** — `nvidia.com/gpu` Requests/Limits = **1/1** held by legacy `InferenceService` |
| Reusable native model / MaaSModelRef | **N/A** — none present |

**Demo 1 path chosen after audit:** enable missing GA prerequisites, then publish a **CPU** `LLMInferenceService` using `llm-d-inference-sim` (no GPU). A real GPU llm-d model is blocked until `my-first-model/llama-32-3b-instruct` releases the GPU (out of scope to delete without explicit approval).

---

## Requirement matrix

| Requirement | Observed | Pass/Fail/Unknown | Supporting command | Remediation |
|---|---|---|---|---|
| OpenShift ≥ 4.19.9 | `4.20.42` Available | PASS | `oc get clusterversion` | — |
| RHOAI ≥ 3.5 | CSV `rhods-operator.3.5.2` Succeeded | PASS | `oc get csv -A \| grep rhods` | — |
| Cluster-admin | `oc auth can-i create namespaces` → yes | PASS | `oc auth can-i …` | — |
| Functional ingress + TLS | Domain `apps.ocp.sv8wx…`; `cert-manager-ingress-cert` Ready | PASS | `oc get ingresscontroller …`; `oc get certificate -n openshift-ingress` | Reuse existing ingress cert for MaaS Gateway |
| RHCL Operator 1.4.x in `openshift-operators` | Not installed; packagemanifest `rhcl-operator` channels `stable` (1.4.3), `stable-1.4` (1.4.4) | FAIL | `oc get sub -A`; `oc get packagemanifest rhcl-operator -n openshift-marketplace` | Install Subscription channel `stable-1.4` |
| `Kuadrant` Ready in `kuadrant-system` | CRD/resource absent; ns empty | FAIL | `oc get kuadrant -A` | Create ns + Kuadrant CR after RHCL |
| Authorino / Limitador for MaaS | Authorino Operator CSV present; no Authorino CR; Limitador absent | FAIL | `oc get authorino -A`; `oc get csv -A \| grep -i limitador` | Provided by Kuadrant reconcile |
| `DSC` aigateway Managed | `spec.components.aigateway` = null; `AIGatewayReady=False` (Removed) | FAIL | `oc get dsc default-dsc -o json` | Patch `aigateway.managementState=Managed` |
| `aigateway.modelsAsAService` Managed | `ModelsAsAServiceReady=False` (Removed) | FAIL | same | Patch `modelsAsAService.managementState=Managed` |
| Deprecated `kserve.modelsAsService` | Already `Removed` | PASS (leave alone) | same | Do **not** re-enable (webhook forbids) |
| KServe Managed | `Managed`, `KserveReady=True` | PASS | same | Keep |
| llm-d LLMIS controller | `llmisvc-controller-manager` Running | PASS | `oc get pods -n redhat-ods-applications` | Needs RHCL for full dependency Ready |
| LeaderWorkerSet (Wide EP) | Not installed; WideEP deps False | Unknown / N/A for single-replica | DSC condition `KserveLLMInferenceServiceWideEPDependencies` | Not required for single-node / simulator Demo 1 |
| JobSet | Operator `1.0.1` Succeeded | PASS | `oc get csv -n openshift-jobset-operator` | — |
| GatewayClass `openshift-default` | Missing (have `openshift-ai-inference`, `data-science-gateway-class`) | FAIL | `oc get gatewayclass` | Create dedicated `openshift-default` (additive) |
| Gateway `maas-default-gateway` | Missing | FAIL | `oc get gateway -A` | Create with required MaaS annotations + TLS |
| Existing gateways (do not overwrite) | `openshift-ai-inference`, `data-science-gateway` Programmed | PASS | same | Leave untouched |
| PostgreSQL 14+ for MaaS | Not present for MaaS | FAIL | `oc get deploy -A \| grep -i postgres` | Deploy demo-scoped Postgres + `maas-db-config` in infra ns |
| UWM enabled | Namespace empty; no `cluster-monitoring-config` enable flag | FAIL | `oc get pods -n openshift-user-workload-monitoring` | Enable user workload monitoring |
| Dashboard `modelAsService` | `true` | PASS | `oc get odhdashboardconfig -A` | Keep; do not enable `vLLMDeploymentOnMaaS` (TP) |
| GPU present | 1× NVIDIA-L4, 23034 MiB, g6.8xlarge | PASS | node labels `nvidia.com/gpu.*` | — |
| GPU free for new GPU LLMIS | Allocated 1/1 by `llama-32-3b-instruct-predictor` | FAIL | `oc describe node … Allocated resources` | Optional: scale down legacy ISVC **with approval**; else use CPU simulator |
| StorageClasses | `gp3-csi` (default), `gp2-csi` | PASS | `oc get storageclass` | Use `gp3-csi` for Postgres PVC |
| Hardware profiles | `default-profile`, `gpu-profile` | PASS | `oc get hardwareprofile -A` | — |
| Existing native LLMIS / MaaSModelRef | None | PASS (nothing to reuse) | `oc get llminferenceservices,maasmodelrefs -A` | Deploy new |
| Legacy KServe model | `my-first-model/llama-32-3b-instruct` Ready, GPU=1 | High-risk conflict if touched | `oc get isvc -A` | **Do not modify** for Demo 1 |
| Can create LLMIS / namespaces | yes | PASS | `oc auth can-i …` | — |
| Can create MaaSModelRef | API group absent today; RBAC would allow once CRDs exist | Unknown → remediable | `oc auth can-i create maasmodelrefs…` | Enable MaaS first |

---

## Blockers / high-risk conflicts

1. **MaaS not enabled** — no CRDs, no infra namespace, no tenant. Must install RHCL + Gateway + Postgres + enable `aigateway.modelsAsAService`.
2. **No free GPU** — cannot deploy a second GPU model alongside `llama-32-3b-instruct` without stopping it.
3. **Shared gateways** — `openshift-ai-inference` already routes to `my-first-model`; Demo 1 must use a **new** `maas-default-gateway`, not patch existing Gateways.
4. **Technology Preview** — `vLLMDeploymentOnMaaS` must remain unset/false; Demo 1 uses GA llm-d `LLMInferenceService` path only.

## GPU capacity detail

| Metric | Value |
|---|---|
| Product | NVIDIA L4 |
| Count / VRAM | 1 / ~23 GiB |
| Sharing | none (no MIG / time-slicing) |
| Free for scheduling | **0** (held by legacy ISVC) |

## Evidence commands (safe to re-run)

```bash
bash scripts/00-audit.sh
oc get dsc default-dsc -o jsonpath='{.status.conditions}' 
oc get gateway,gatewayclass -A
oc get packagemanifest rhcl-operator -n openshift-marketplace
oc describe node "$(oc get nodes -o jsonpath='{.items[0].metadata.name}')" | grep -A15 'Allocated resources'
```

---

## Post-install delta (after Demo 1 scripts)

| Item | After change |
|---|---|
| RHCL | `rhcl-operator.v1.4.4` Succeeded; Kuadrant Ready |
| UWM | Enabled; prometheus-user-workload Running |
| GatewayClass `openshift-default` | Created (Accepted) |
| Gateway `maas-default-gateway` | Created (Programmed) |
| DSC aigateway / MaaS | Managed / Managed; `ModelsAsAServiceReady=True` |
| Postgres + `maas-db-config` | Present (creds not exported) |
| `LLMInferenceService/demo-simulator` | Ready=True (CPU simulator) |
| `MaaSModelRef/demo-simulator` | RuntimeReady=True; Ready Pending (needs Demo 2 pairing) |
| Legacy ISVC | Untouched, still Ready |
