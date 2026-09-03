# BASELINE — Phase 0 (Read-Only)

Captured: 2026-09-03, sandbox `api.ocp.lzmcf.sandbox1039.opentlc.com:6443`

## Cluster identity

| Item | Value |
|---|---|
| `oc whoami` | `admin` |
| API server | `https://api.ocp.lzmcf.sandbox1039.opentlc.com:6443` |
| Cluster-admin (`oc auth can-i '*' '*' --all-namespaces`) | `yes` |
| OpenShift client version | 4.22.3 |
| OpenShift server version | **4.20.35** |
| Kubernetes version | v1.33.13 |
| ClusterVersion status | `True` (Available), not Progressing |
| Platform (`infrastructure.status.platform`) | **AWS** (cloud — no MetalLB needed) |
| Cluster domain | `apps.ocp.lzmcf.sandbox1039.opentlc.com` |
| Default ingress cert | `cert-manager-ingress-cert` (cert-manager already installed and managing the router wildcard cert) |

## Nodes

Single-node cluster (all roles on one node):

| Node | Roles | CPU allocatable | Memory allocatable | CPU used | Memory used |
|---|---|---|---|---|---|
| ip-10-0-19-46.eu-central-1.compute.internal | control-plane,master,worker | 31500m | 125894508Ki (~120Gi) | 3347m (10%) | 29022Mi (23%) |

No `Pending`, `CrashLoopBackOff`, or `OOMKilled` pods found anywhere on the cluster. One historical `installer-5` pod in `openshift-kube-scheduler` shows `Error` status — this is a normal one-shot revision-installer pod artifact from the initial control-plane bring-up, not a live crash loop. Restart counts on core operator pods (4-12) are typical for a cluster that finished bootstrapping ~85 minutes before this check and are not a stability concern.

## RHOAI installation

| Item | Value |
|---|---|
| Operator CSV | `rhods-operator.3.5.0` (replaces `rhods-operator.3.4.3` — installed via the normal upgrade path) |
| Phase | `Succeeded` across all namespaces |
| DataScienceCluster | `default-dsc` present |
| DSCInitialization | `default-dsci` present, `applicationsNamespace: redhat-ods-applications` |

## Pre-existing workloads (NOT created by this demo — do not touch)

| Namespace | Resource | Notes |
|---|---|---|
| `my-first-model` | `llama-32-3b-instruct-predictor` Deployment (classic KServe `InferenceService`, GPU-backed) | Pre-provisioned sample model on this sandbox. Running healthy (1/1, 0 restarts). |
| `nvidia-gpu-operator` | NVIDIA GPU Operator + driver daemonset | Backs the GPU used by `my-first-model`. Not used by this demo (CPU-only simulator). |
| `openshift-ingress` | `data-science-gateway` Gateway | Owned by RHOAI's own `GatewayConfig/default-gateway` — backs the RHOAI dashboard itself. **One declarative memory fix applied post-baseline — see "Platform prerequisite fix" below.** |
| `openshift-ingress` | `openshift-ai-inference` Gateway | Generic inference gateway serving `my-first-model`'s namespace. Not a MaaS gateway (no MaaS annotations). Not touched. |

## Top resource consumers (baseline)

CPU: `kube-apiserver` (723m), `kube-controller-manager` (480m), `workbenches-operator` (437m), `openshift-apiserver` (298m) — all core platform, expected.

Memory: `kube-apiserver` (5.6Gi), `nvidia-driver-daemonset` (3Gi), `llama-32-3b-instruct-predictor` (2.9Gi, pre-existing GPU model), `prometheus-k8s-0` (1.8Gi).

## Result

**Cluster health: PASS.** No CrashLoopBackOff, no OOMKilled, no Pending pods. Node at 10% CPU / 23% memory — ample headroom for a CPU-only MaaS simulator demo. Safe to proceed to Phase 1.

## Platform prerequisite fix (post-baseline, pre-existing platform resource — NOT a demo resource)

While enabling the RHOAI `aigateway`/`ogx` components (Phase 6/7 of the MaaS installation), the **pre-existing**, RHOAI-owned `data-science-gateway` (created automatically by `GatewayConfig/default-gateway`, and already present at baseline — it backs the RHOAI dashboard) began `CrashLoopBackOff`/`OOMKilled`:

> `data-science-gateway` was OOMKilled at its initial 1Gi Envoy (`istio-proxy`) memory limit. The existing `Gateway.spec.infrastructure.parametersRef` → `ConfigMap/data-science-gateway-config` was declaratively adjusted to 2Gi (adding a `deployment:` key, mirroring the `service:` key already owned by the `gatewayconfig` operator). No generated Deployment was patched directly, no loop/reconciler was created, and no operator reconciliation was disabled.

Evidence collected before the change:
- `istio-proxy` container: `restartCount=6`, `lastState.terminated.reason=OOMKilled`, `exitCode=137`, limit was `1Gi`.
- Node memory headroom was ample (27% used cluster-wide) — this was a per-pod limit, not cluster-wide memory pressure.
- `Gateway.spec.infrastructure.parametersRef` confirmed to reference `ConfigMap/data-science-gateway-config` before any change was made.

Change applied via `oc apply --server-side --field-manager=demo-oom-fix` (co-existing with the `gatewayconfig` operator's own field ownership of the `service:` key — no field conflicts).

Verified stable after the change:
- New pod `Running`, `1/1` Ready, `istio-proxy` limit = `2Gi`, actual usage ~1.1Gi (comfortable margin).
- `Gateway` `Accepted=True`, `Programmed=True`.
- RHOAI dashboard route returned `HTTP 200`.
- Observed over 8 cycles (~7 minutes): ConfigMap and Deployment limit remained at `2Gi` — the `gatewayconfig` operator did **not** revert this change (it only owns the `service:` key, not `deployment:`).

This is a **platform prerequisite fix**, not a demo-created resource — it is intentionally excluded from `make cleanup` and will persist for future demos on this sandbox.
