# Sandbox `cluster-t5lkh.dyn.redhatworkshops.io` — RHOAI base install

Captured / performed: 2026-09-07.

Unlike the sandbox documented in the root `BASELINE.md`/`PREFLIGHT.md` (which
already had RHOAI 3.5 pre-installed), this sandbox started with **no
OpenShift AI at all**. This document records the feasibility analysis and the
actual installation performed here.

## Cluster identity

| Item | Value |
|---|---|
| API server | `https://api.cluster-t5lkh.dyn.redhatworkshops.io:6443` |
| `oc whoami` | `admin` (cluster-admin confirmed) |
| OpenShift server version | `4.22.11` |
| Platform (`infrastructure.status.platform`) | `None` (bare-metal / on-prem style — no cloud LoadBalancer provisioner) |
| Cluster domain | `apps.cluster-t5lkh.dyn.redhatworkshops.io` |
| Topology | Single node (`control-plane,master,worker` combined) |

## Node sizing (baseline, before install)

| Resource | Capacity | Allocatable | Used (baseline) |
|---|---|---|---|
| CPU | 32 vCPU | 31.5 vCPU | 3.49 (11%) |
| Memory | 131888560Ki (~125.8 GiB) | 130737584Ki (~124.7 GiB) | 21928Mi (17%) |

No GPU on the node. Default StorageClass present:
`ocs-external-storagecluster-ceph-rbd` (ODF external, dynamic provisioning,
CephFS also available for RWX).

## Feasibility analysis — risks identified before installing

1. **OpenShift version above RHOAI 3.5's officially supported range.**
   Red Hat's docs state RHOAI 3.5 supports OCP **4.19–4.20**. This cluster
   runs **4.22.11**. Not a hard technical blocker (see result below — it
   installed and reconciled cleanly), but **not an officially supported
   combination**.
2. **Node RAM slightly under the documented SNO minimum.** Red Hat's docs
   require "at least 32 CPUs and 128 GiB RAM" for single-node OpenShift.
   This node has 32 CPUs (meets it) but only ~125.8 GiB RAM capacity
   (~98% of the 128 GiB minimum). Worked fine for this base install; would
   need monitoring if adding heavier workloads (model serving, pipelines
   under load, etc.).
3. **No cloud LoadBalancer / MetalLB / GatewayClass configured.** Not an
   issue for the base operator + dashboard (uses a Route, as always).
   It **would** matter for anything relying on Gateway API +
   `LoadBalancer`-type Services (e.g. a MaaS gateway, as used in the other
   sandbox's demo, or Distributed Inference with llm-d) — this cluster has
   no cloud LB provisioner, so exposing a `Gateway` would require MetalLB or
   a Route/NodePort-based workaround. Out of scope for this base install.
4. **OLMv1 Technology Preview catalog is enabled by default on OCP 4.21+.**
   Did not interfere with the CLI-based classic OLM `Subscription` used here
   — `CatalogSource`/`PackageManifest`/`Subscription` all worked normally.

## What was installed

Manifests: `manifests/rhoai-operator/`. Script: `scripts/install-rhoai-operator.sh`
(`make install-rhoai-operator`).

| Resource | Namespace | Notes |
|---|---|---|
| `Namespace/redhat-ods-operator` | — | Operator namespace |
| `OperatorGroup/rhods-operator` | `redhat-ods-operator` | AllNamespaces (only supported install mode) |
| `Subscription/rhods-operator` | `redhat-ods-operator` | channel `stable-3.x`, source `redhat-operators`, `installPlanApproval: Automatic` |
| `DSCInitialization/default-dsci` | — | Auto-created by the operator on CSV install. `applicationsNamespace: redhat-ods-applications` |
| `DataScienceCluster/default-dsc` | — | Created manually (not auto-created on this operator version). Components enabled: `dashboard`, `workbenches`, `kserve`, `aipipelines`, `modelregistry`, `trainingoperator`, `trustyai`, `ray`. Left `Removed`: `kueue`, `feastoperator`, `mlflowoperator`, `sparkoperator`, `llamastackoperator`, `mcplifecycleoperator`, `ogx`, `aigateway` (each needs extra operators/dependencies out of scope for a base-install check — see conditions below). |

### Gotcha hit during install

`spec.components.kueue.managementState: Managed` is **rejected** by the
`datasciencecluster-v2-validator.opendatahub.io` admission webhook on this
operator version: `"Managed is no longer supported as a managementState"`.
Per `oc explain`, Kueue's valid values are now `Unmanaged` / `Removed` only
(`Managed` is kept in the enum only for OLM upgrade backwards-compatibility
and is actively rejected at runtime). Fixed by setting `kueue.managementState: Removed`.

## Verification (result)

```
CSV rhods-operator.3.5.0                    Succeeded   (~35s after Subscription apply)
DSCInitialization default-dsci              Ready
DataScienceCluster default-dsc              Ready       (~2.5 min after apply)
  DashboardReady          True
  WorkbenchesReady        True
  KserveReady             True
  AIPipelinesReady        True
  ModelRegistryReady      True
  TrainingOperatorReady   True
  TrustyAIReady           True
  RayReady                True
  (all other *Ready=False conditions are expected — those modules were
   intentionally left `Removed`, or (Kserve's LLMInferenceService
   dependency conditions) report missing optional deps: Connectivity
   Link / LeaderWorkerSet, neither installed, neither needed here)

Release: OpenShift AI Self-Managed 3.5.0

All redhat-ods-operator and redhat-ods-applications pods: Running, 0
unexpected restarts.

Dashboard route: rhods-dashboard-redhat-ods-applications.apps.cluster-t5lkh.dyn.redhatworkshops.io
  curl -k <route>  -> HTTP 301 (expected: redirect into OpenShift OAuth login)

Node usage after install: CPU 20% (6.4/32 cores), Memory 23% (29.3Gi/125.8Gi)
  -> still ample headroom.

Pre-existing, unrelated Pending pods (openshift-storage cephcsi ctrlplugins,
age 4d21h, present before this install) — not caused by this change.
```

## Conclusion

**RHOAI 3.5 installs and reconciles successfully on this sandbox**, despite
the two "unsupported configuration" caveats above (OCP 4.22.11 vs. the
4.19–4.20 support matrix, and node RAM ~98% of the documented SNO minimum).
The dashboard, workbenches, KServe (RawDeployment), Data Science Pipelines,
Model Registry, Training Operator, TrustyAI, and Ray components are all
`Ready`. This is **not a Red Hat–supported combination** for production use,
but it is functionally usable for demos/testing on this sandbox.

Not attempted here (out of scope for "is a base install possible"):
MaaS gateway exposure (needs MetalLB or a Route/NodePort alternative to the
cloud LoadBalancer used in the other sandbox's demo), Kueue, Connectivity
Link/Kuadrant, GPU-backed model serving (no GPU on this node).
