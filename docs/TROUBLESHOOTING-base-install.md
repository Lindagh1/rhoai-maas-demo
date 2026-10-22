# Troubleshooting — base RHOAI install / Knowledge Advisor demo

> Scope: base RHOAI operator install + Knowledge Advisor RAG demo.
> For Demo 1 (native llm-d + MaaS), see [`troubleshooting.md`](troubleshooting.md) instead.
> Renamed from `TROUBLESHOOTING.md` to avoid a case-insensitive filename
> collision with `troubleshooting.md` on macOS/Windows clones.

Issues actually encountered while building/running this demo on this sandbox, and the exact fix applied. Every entry below was reproduced and fixed on the live cluster — none of this is speculative.

---

## 1. `data-science-gateway` OOMKilled (pre-existing RHOAI platform Gateway, not a demo resource)

**Symptom:**

```
oc get pod -n openshift-ingress
data-science-gateway-data-science-gateway-class-xxxxxxxxxx-xxxxx   0/1   CrashLoopBackOff   6   61m
```

```
oc get pod -n openshift-ingress <pod> -o jsonpath='{.status.containerStatuses[0].lastState}'
{"terminated":{"exitCode":137,"reason":"OOMKilled", ...}}
```

**Root cause:** `data-science-gateway` is created automatically by RHOAI's `GatewayConfig/default-gateway` (it backs the RHOAI dashboard itself) — it is **not** created by this demo. Its Envoy sidecar (`istio-proxy`) shipped with only a `1Gi` memory limit, which is too tight once the platform's `aigateway`/`ogx` components and Kuadrant policies are enabled. Node-wide memory was not under pressure (27% used) — this was purely a too-low per-pod limit.

**Fix (one-time, declarative, no Deployment patching):**

The Gateway already referenced a ConfigMap via the supported Gateway API mechanism:

```yaml
spec:
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: data-science-gateway-config
```

We added a `deployment:` key to that **existing** `ConfigMap/data-science-gateway-config` (the operator only owns the `service:` key via Server-Side Apply, so this did not conflict):

```yaml
data:
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: "2"
                memory: 2Gi
```

Applied with `oc apply --server-side --field-manager=demo-oom-fix` so the change is tracked under its own field manager and does not touch the fields the `gatewayconfig` operator manages.

**Verification:** new pod `Running`/`Ready`, `istio-proxy` limit confirmed `2Gi`, actual usage ~1.1Gi, `Gateway` `Programmed=True`, RHOAI dashboard route `HTTP 200`. Observed stable (no reversion by the operator) over 8 checks across ~7 minutes.

**Scope note:** This is a **platform prerequisite fix**, not a demo-created resource. `make cleanup` does **not** revert it — the fix should persist for future demos on this sandbox. Full evidence is recorded in [`../BASELINE.md`](../BASELINE.md#platform-prerequisite-fix-post-baseline-pre-existing-platform-resource--not-a-demo-resource).

---

## 2. RHOAI 3.5 DSC schema diverges from the published docs: `kserve.modelsAsService` is deprecated

**Symptom:**

```
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"kserve":{"modelsAsService":{"managementState":"Managed"}}}}}'
The DataScienceCluster "default-dsc" is invalid: ...
modelsAsService is deprecated; cannot re-enable once Removed. Use spec.components.aigateway.modelsAsAService instead
```

**Root cause:** The official RHOAI 3.5 documentation (docs.redhat.com) describes `spec.components.kserve.modelsAsService.managementState`, but this cluster's live admission webhook has already migrated to the newer "AI Gateway" modularized path.

**Fix:** `scripts/bootstrap.sh` detects this at runtime — it first attempts the documented `kserve.modelsAsService` field; if the API server rejects it with the deprecation message above, it falls back to:

```
spec.components.aigateway.managementState: Managed
spec.components.aigateway.modelsAsAService.managementState: Managed
```

The live cluster's admission control is always treated as the source of truth over static documentation examples.

---

## 3. `OdhDashboardConfig.spec.dashboardConfig.maasAuthPolicies` is frozen/deprecated

**Symptom:**

```
The OdhDashboardConfig "odh-dashboard-config" is invalid: spec.dashboardConfig: Invalid value: "object": no such key: maasAuthPolicies evaluating rule: DEPRECATED: spec.dashboardConfig.maasAuthPolicies must be removed or left unchanged.
```

**Fix:** `bootstrap.sh` treats this as a non-fatal, expected outcome on this cluster build and skips the patch. The MaaS governance UI on this build is gated by `genAiStudio` instead, which is set successfully.

---

## 4. `LlamaStackOperator` blocks `OGX` provisioning

**Symptom:** After enabling `aigateway`/`ogx`, MaaS CRDs never appear. `DataScienceCluster` status shows:

```
OGXReady=False Deploying "Waiting for root OGX operator webhook resources to become ready"
```

and the `rhods-operator` logs show:

```
LlamaStackOperator is set to Managed; it has been deprecated, set it to Removed before enabling OGX
```

**Fix:** `bootstrap.sh` checks whether `spec.components.llamastackoperator.managementState` is `Managed` with no active consumers, and if so sets it to `Removed` before enabling `ogx`. This unblocks `OGX` module provisioning.

---

## 5. `maas-api` CrashLoopBackOff: `password authentication failed for user "maasadmin"`

**Symptom:**

```
error: failed to initialize token store: failed to connect to PostgreSQL: ... FATAL: password authentication failed for user "maasadmin" (SQLSTATE 28P01)
```

**Root cause (two distinct causes were found on this sandbox):**

1. As soon as the MaaS infra namespace is created, the platform auto-generates a placeholder `maas-db-config` secret with credentials that do not match the demo's own PostgreSQL instance.
2. Separately, the demo's own `postgres-creds` secret was once created with an **empty** `POSTGRES_PASSWORD` value, because an earlier password-generation command (`openssl rand -hex 20`) failed silently (`openssl` was not available in that shell) before the script was fixed to use `python3 -c "import secrets; print(secrets.token_hex(20))"`. Because the secret-creation logic only creates the secret if it does **not** already exist, this empty password persisted across subsequent idempotent runs.

**Fix:**
- `bootstrap.sh` always (re)writes `maas-db-config` in the MaaS infra namespace with the exact connection string derived from the demo's own `postgres-creds` secret, and restarts `maas-api` if the value changed.
- `bootstrap.sh` now also **self-heals** `postgres-creds`: on every run, if `POSTGRES_PASSWORD` is found to be empty, it regenerates a proper password, updates the secret, and runs `ALTER USER ... WITH PASSWORD ...` against the running PostgreSQL role via `oc exec ... psql -h /var/run/postgresql` (local socket auth, not a Deployment patch) so the live database role matches the secret again.

---

## 6. `oc get projects | wc -l` undercounts

**Symptom:** `oc get projects | wc -l` reports fewer projects than actually exist.

**Fix:** Use `oc get projects --no-headers | wc -l` — the header line row from the table output was being counted incorrectly against expectations, and `--no-headers` gives an accurate count.
