# Sandbox `cluster-t5lkh` — demo VS Code (code-server) workbench

Deployed 2026-09-07, after the full RHOAI activation documented in
`RHOAI-INSTALL.md`.

## What was created

Manifests: `manifests/workbench-vscode-demo/`. Script:
`scripts/install-vscode-workbench-demo.sh` (`make install-vscode-workbench-demo`).

| Resource | Namespace | Notes |
|---|---|---|
| `Namespace/vscode-demo` | — | Data Science Project (`opendatahub.io/dashboard: "true"`) |
| `PersistentVolumeClaim/vscode-demo` | `vscode-demo` | 20Gi, RWO, default StorageClass |
| `Notebook/vscode-demo` (kubeflow.org/v1) | `vscode-demo` | Image: `code-server-notebook:3.5` (the built-in RHOAI VS Code workbench image) |

Only the workbench container itself was authored by hand — the
`odh-notebook-controller` + `notebook-controller` reconcilers automatically
added everything else once the `Notebook` CR was created:
a `kube-rbac-proxy` sidecar container, a `StatefulSet`, two `Service`s
(`vscode-demo` on port 80→8888, `vscode-demo-kube-rbac-proxy` on 8443), and a
Gateway API `HTTPRoute` (`nb-vscode-demo-vscode-demo`, in
`redhat-ods-applications`) — **not** a classic OpenShift `Route` per
notebook, unlike older (2.x-era) RHOAI docs describe.

## Gotcha: auth model changed from `oauth-proxy` to `kube-rbac-proxy`

Most public examples (including Red Hat's own 3.3-era "Creating a workbench
by using the Notebook CRD" doc) show the mutating webhook injecting an
`oauth-proxy` sidecar in response to the
`notebooks.opendatahub.io/inject-oauth: "true"` annotation, plus a classic
`Route`. On this RHOAI 3.5 build, the injected sidecar is **`kube-rbac-proxy`**
instead, and exposure is via a Gateway API `HTTPRoute` attached to the
**same shared `data-science-gateway`** that backs the RHOAI dashboard itself
— not a dedicated per-notebook `Route`. (`inject-oauth` annotation is still
accepted/harmless to set, but the actual mechanism it triggers has moved on.)

## How to reach it

The `HTTPRoute` is only reachable through the `Gateway`'s own externally
exposed `Route`, found by looking for the `Route` in `openshift-ingress`
that targets the `data-science-gateway...` Service:

```
oc get route -n openshift-ingress
# data-science-gateway   rh-ai.apps.cluster-t5lkh.dyn.redhatworkshops.io
```

Workbench URL:
`https://rh-ai.apps.cluster-t5lkh.dyn.redhatworkshops.io/notebook/vscode-demo/vscode-demo/`

`curl`-ing it unauthenticated correctly returns `302` to
`https://oauth-openshift.apps.../oauth/authorize?...` (OpenShift OAuth login)
— the same healthy behavior as the main RHOAI dashboard route. A real
browser session (logged into the cluster's OAuth/htpasswd/identity provider)
is required to actually open the VS Code UI.

## Verification

```
pod/vscode-demo-0   2/2 Running, 0 restarts   (containers: vscode-demo, kube-rbac-proxy)
statefulset.apps/vscode-demo    1/1 Ready
notebook.kubeflow.org/vscode-demo  status.conditions: Ready=True, ContainersReady=True, Initialized=True

code-server log:
  "HTTP server listening on http://[::]:8787/"
  "Authentication is disabled"   <- expected: kube-rbac-proxy handles auth in front, code-server itself has none
```

## Cleanup

```
oc delete -f manifests/workbench-vscode-demo/03-notebook.yaml
oc delete -f manifests/workbench-vscode-demo/02-pvc.yaml
oc delete -f manifests/workbench-vscode-demo/01-namespace.yaml
```
