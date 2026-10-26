# Demo 2 — Environment audit (read-only)

**Date:** 2026-10-22
**Cluster:** `api.ocp.<masked>.<masked>.opentlc.com` (hostname masked per policy, same disposable sandbox as Demo 1)
**OpenShift:** `4.20.42` | **RHOAI (RHODS operator):** `3.5.2`
**Identity used for this audit:** `admin` (cluster-admin), read-only `oc get/explain` only — no secret *values* printed, no mutations.

This audit extends `docs/sandbox-audit.md` (Demo 1). It assumes Demo 1 has already been applied on this sandbox (`scripts/00-audit.sh` → `50-verify.sh`). **Nothing in this document required any write operation.**

---

## 1. Demo 1 platform state (reused as-is, not rebuilt)

| Component | State | Evidence |
|---|---|---|
| RHCL / Kuadrant | `kuadrant-system/kuadrant` — Authorino + Limitador present | `oc get kuadrant,authorino,limitador -A` |
| Gateway `maas-default-gateway` | `openshift-ingress`, class `openshift-default`, **Programmed=True** | `oc get gateway -A` |
| `DataScienceCluster.spec.components.aigateway` | `managementState: Managed`, `modelsAsAService.managementState: Managed` | `oc get dsc default-dsc -o jsonpath=...` |
| `ModelsAsAServiceReady` | `True` — "modelsAsAService is Managed and deployments are available" | same |
| MaaS infra namespace | `redhat-ai-gateway-infra` — `maas-api` Running, `maas-api-key-cleanup` CronJob completing on schedule | `oc get pods -n redhat-ai-gateway-infra` |
| `maas-db-config` secret | present (value not inspected) | `oc get secret maas-db-config -n redhat-ai-gateway-infra` |
| User Workload Monitoring | Enabled; `prometheus-user-workload`, `thanos-ruler-user-workload` Running | `oc get pods -n openshift-user-workload-monitoring` |
| `LLMInferenceService/demo-simulator` | `rhoai-maas-demo` ns, **Ready=True**, served model `facebook/opt-125m` (CPU `llm-d-inference-sim`, no GPU) | `oc get llminferenceservice -A -o wide` |
| `MaaSModelRef/demo-simulator` | same ns, `RuntimeReady=True`, **`Ready=False` / `phase=Pending`** — `GovernanceAttached=False`, reason `NoPairingFound`, message *"No active subscription and auth policy pairing found"* | `oc get maasmodelref demo-simulator -n rhoai-maas-demo -o yaml` |
| Legacy `my-first-model/llama-32-3b-instruct` | Still Ready, GPU=1/1, **untouched** | `oc get isvc -A` |

**This is exactly the gate Demo 2 exists to close.** No changes were made to any of the above for this audit.

### Resolved model identity (read from the live `MaaSModelRef`)

```yaml
status:
  resolvedModelAlias: publishers/rhoai-maas-demo/models/facebook/opt-125m
  httpRouteGatewayName: maas-default-gateway
  httpRouteGatewayNamespace: openshift-ingress
  httpRouteName: demo-simulator-kserve-route
  httpRouteNamespace: rhoai-maas-demo
```

- **Model namespace:** `rhoai-maas-demo`
- **Model name (`modelRefs[].name`):** `demo-simulator` (this is the `MaaSModelRef`/`LLMInferenceService` name — what Demo 2's `MaaSSubscription`/`MaaSAuthPolicy` manifests reference)
- **Served model name (what appears in `/v1/models` and must be sent as `model` in `/v1/chat/completions`):** to be **confirmed live in Scenario D** against the actual Gateway response — do not assume `resolvedModelAlias` and the OpenAI-API `model` field are identical until verified by a real request (recorded in `evidence/demo2/`).
- **MaaS Gateway hostname:** `maas.apps.ocp.<masked>…opentlc.com` (same masking convention as Demo 1 docs; full value in the untracked raw audit dump only)

---

## 2. MaaS tenant

| Item | Value |
|---|---|
| `AITenant` | `models-as-a-service` (namespace `ai-tenants`), **Ready=True**, tenant namespace `models-as-a-service`, gateway `maas-default-gateway` |
| `MaaSTenantConfig` | `default-tenant` in `models-as-a-service`, **Ready=True**, reason `Reconciled` |

**Decision:** reuse the existing `default-tenant` / `models-as-a-service` AITenant. **No new `AITenant` is created for Demo 2** — none is technically required: the model already belongs to this tenant's gateway, and the task brief explicitly says not to create one unless justified.

---

## 3. Existing MaaS governance objects (conflict check)

```
$ oc get maassubscription -A   → No resources found
$ oc get maasauthpolicy -A    → No resources found
```

**Clean slate.** No pre-existing `MaaSSubscription` or `MaaSAuthPolicy` on this sandbox, so Demo 2's `maas-demo2-subscription` / `maas-demo2-access` cannot collide with anything, and nothing needs to be preserved/avoided beyond the Demo 1 objects listed above.

---

## 4. Identity / authentication — **critical finding**

```
$ oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].type}'
OpenID
```

This sandbox's **only** configured identity provider is **OIDC backed by an in-cluster Red Hat build of Keycloak (RHBK)**, not `HTPasswd`:

| Item | Value |
|---|---|
| IDP name (in `oauth/cluster`) | `rhbk` |
| IDP type | `OpenID` (generic OIDC) |
| OIDC issuer | `https://sso.apps.ocp.<masked>…opentlc.com/realms/sso` |
| Keycloak instance | `keycloak/keycloak` (Keycloak Operator CR), realm `sso` imported via `KeycloakRealmImport/sso` |
| Client used by OpenShift | `idp-4-ocp` — **`directAccessGrantsEnabled: true`**, `standardFlowEnabled: true` (so `oc login -u -p` works directly, no browser redirect required for CLI) |
| Group claim mapped? | **No** — the IDP's `claims` mapping only covers `email`, `name`, `preferredUsername`. There is **no `groups` claim mapped from Keycloak into OpenShift `Group` objects.** |
| Pre-existing users in the realm | **`admin` only** (confirmed by reading the `KeycloakRealmImport` spec — `realm.users[].username == ["admin"]`) |
| `oc get users` | `admin` (identity `rhbk:<sub>`), no other `User`/`Identity` objects — nothing has JIT-provisioned a second user yet |
| `oc get groups` | `rhods-admins` (empty) — no other groups |

**Conclusion — does this sandbox support creating a genuine non-admin OpenShift OAuth user?**

**Yes, but it requires an additive write to the external IdP (Keycloak), not just `oc` commands.** There is no `HTPasswd` secret to append a user to. The only way to get a second, real, non-admin, browser-loggable OAuth identity is to create a new user in the Keycloak `sso` realm (via its Admin REST API, reachable at `https://sso.apps.ocp.<masked>…opentlc.com`), using the `keycloak-initial-admin` Secret in namespace `keycloak` (credentials not printed here). Because the realm's `idp-4-ocp` client has `directAccessGrantsEnabled: true`, a new Keycloak user can log in both via `oc login -u maas-demo2-user -p '<password>'` (CLI/API testing) **and** via the normal browser OIDC login form (dashboard screenshots).

Since OpenShift does **not** sync Keycloak groups into `Group` objects (no `groups` claim mapped), the task's required `maas-demo2-developers` **OpenShift `Group`** must be created directly with `oc adm groups new` / `oc adm groups add-users` — independent of Keycloak. This part requires no IdP mutation and is pure Kubernetes API usage already permitted to `admin` (`oc auth can-i create groups/users` → `yes`).

**This is the one step in Demo 2 that touches shared, external identity infrastructure** (the realm backing login for this entire sandbox) rather than purely Demo-2-scoped Kubernetes objects. Per the task's explicit rule — *"Require explicit confirmation before deleting resources or modifying shared security, identity, Gateway or cluster-level configuration"* — **this was escalated to the user for an explicit go-ahead before any Keycloak mutation was performed.** See `docs/demo2/02-admin-runbook.md` §1 for the decision and exact procedure.

**Never grant `maas-demo2-user` cluster-admin or any Keycloak admin/realm-admin role.** The new user will be created as a plain realm member (role `user` only, matching the realm's own pre-defined non-admin role), added to the OpenShift `Group/maas-demo2-developers` only, with zero additional OpenShift RBAC beyond the base `system:authenticated` grants every logged-in user already has (`self-provisioners`, `basic-user`, `self-access-reviewer`, …).

### RBAC note — MaaS catalog visibility is not driven by raw CR RBAC

```
ClusterRole/maas-viewer-role  → get/list/watch maasmodelrefs, externalmodels
ClusterRole/maas-owner-role   → full CRUD on maasmodelrefs, externalmodels
```

Neither role is bound to `system:authenticated` or to any group — only `admin` (via the default `admin`/`cluster-admin` bindings) can read `MaaSModelRef` objects directly through the Kubernetes API today. This confirms that **the MaaS model catalog shown in the dashboard to an ordinary end user is served by the `maas-api` backend** (its own service logic / DB-backed catalog, gated by subscription state), **not** by direct Kubernetes RBAC on `maasmodelrefs` for the logged-in user. This matters for Scenario A: "model discovery" and "subscription/key gating" are two different enforcement layers, and must be tested and documented separately rather than assumed.

---

## 5. Observability prerequisites for MaaS usage (Scenario F)

| Requirement | State |
|---|---|
| User Workload Monitoring | **Enabled** (Demo 1 prerequisite, already satisfied) |
| `ServiceMonitor`/`PodMonitor` for Limitador | `kuadrant-limitador-monitor` (kuadrant-system), `limitador-metrics` (redhat-ods-monitoring) — present |
| `ServiceMonitor`/`PodMonitor` for Authorino | `kuadrant-authorino-monitor`, `authorino-operator-monitor` — present |
| `ServiceMonitor` for `maas-api` | `maas-api-metrics` (redhat-ai-gateway-infra) — present |
| `ServiceMonitor` for `maas-controller` | `maas-controller-metrics` (redhat-ods-applications) — present |
| `ServiceMonitor`/`PodMonitor` for the model itself | `kserve-llm-isvc-*` (rhoai-maas-demo) — present |

**Observability for Demo 2 now depends on Demo 1's explicit observability step.** On a fresh sandbox, use `make demo1-all` (or at least `make demo1-enable-observability`) so the RHOAI dashboard's `Observe & Monitor` views are actually present before Demo 2. Scenario F then distinguishes:
- what the **non-admin** user can see in `API keys` and `Observe & Monitor → Models`
- what the **admin** can verify through Limitador metrics
- and the known limitation that `Observe & Monitor → Usage` can still remain empty/partial on this build even after real traffic

---

## 6. GPU / shared resources (unchanged from Demo 1)

Still 1× NVIDIA L4, still fully allocated (`1/1`) to `my-first-model/llama-32-3b-instruct`. Demo 2 reuses the existing CPU `LLMInferenceService/demo-simulator` from Demo 1 and does **not** request any additional GPU/compute. No conflict.

---

## 7. Summary of blockers found (before any Demo 2 mutation)

| # | Blocker | Resolution path |
|---|---|---|
| 1 | No non-admin OAuth identity exists; the only IdP is OIDC/Keycloak with no HTPasswd fallback | Create one additive Keycloak realm user via Admin REST API (plain `user` role) **— requires explicit user confirmation before execution**, documented in `02-admin-runbook.md` §1 |
| 2 | Keycloak does not sync `groups` claim into OpenShift `Group` objects | Create `Group/maas-demo2-developers` directly via `oc adm groups new/add-users` (no IdP change needed for this part) |
| 3 | `MaaSModelRef/demo-simulator.status.phase=Pending` | Expected — this is exactly what Demo 2's `MaaSSubscription` + `MaaSAuthPolicy` pairing resolves (Scenario B) |
| 4 | Exact OpenAI-API `model` string not yet confirmed from a live Gateway response | Confirm in Scenario D, record in `evidence/demo2/` |

No other blockers identified. All remaining Demo 2 steps are additive, Demo-2-labelled, and do not touch Demo 1 or any shared/legacy resource.
