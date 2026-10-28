# Local patches on top of vendored upstream

Vendored from https://github.com/rh-aiservices-bu/rhoai-maas-guide
at commit `ca26a4561673c05a19cd1be5e2eb7663cdb8b17d`.

Every edit made directly inside this vendored copy must be listed here so a
future re-vendor from a newer upstream commit can replay (or re-check the
relevance of) each one.

| File | Change | Reason |
|---|---|---|
| `scripts/setup-maas.sh` | `POSTGRES_PASSWORD` generation falls back to `python3 -c "import secrets; ..."` when `openssl` is not on `PATH` | The agent/runner host for this sandbox has no `openssl` binary and no passwordless `sudo` to install one. Purely a local-tooling compatibility fix — does not change cluster-side behavior. |
| `scripts/setup-maas.sh` Phase 0 + Phase 4 gate | Preflight's "is MaaS already Managed?" check now also requires `.spec.components.aigateway.managementState == Managed` (parent), not just the nested `.spec.components.aigateway.modelsAsAService.managementState`. | **Real cluster-side bug found on this sandbox** (`mqgbd.sandbox840`), not a local-tooling issue — see root-cause writeup below. |

## Cluster-side bug: Phase 0 preflight false-positive on `aigateway` parent `managementState: Removed`

**Symptom:** On a fresh sandbox with RHOAI 3.5.2 pre-provisioned by the
OpenTLC catalog, the pre-existing `DataScienceCluster/default-dsc` already
had:

```yaml
spec:
  components:
    aigateway:
      managementState: Removed          # parent: Removed
      modelsAsAService:
        managementState: Managed        # nested: Managed
    llamastackoperator:
      managementState: Managed          # guide wants: Removed
    ogx:
      managementState: Removed          # guide wants: Managed
```

`setup-maas.sh`'s Phase 0 preflight only reads the **nested**
`aigateway.modelsAsAService.managementState` field to decide
`HAS_MAAS_MANAGED`. Since that nested field was already `Managed` on this
sandbox (but the parent `aigateway` component was `Removed`), the script
logged `modelsAsService: Managed` and later `DSC already has MaaS: Managed,
skipping` in Phase 4 — so it never applied
`manifests/04-rhoai-config/datasciencecluster.yaml`, which is the only place
that also flips `llamastackoperator` to `Removed` and `ogx`/`aigateway`
(parent) to `Managed`.

Net effect: Phase 5 (deploy model) still worked — KServe/LLMInferenceService
doesn't need `aigateway` — so the `facebook-opt-125m-simulated` model came
up `Ready` and looked like a success. But `maas-api` never deployed, no
`maas*.opendatahub.io` CRDs were ever registered
(`maasmodelref`/`maassubscription`/`maasauthpolicy` all `NotFound`), and
`AIGatewayReady`/`ModelsAsAServiceReady` stayed `False (Removed)` the whole
time. Running Phase 6 verification against this state fails outright (no
`maas-api`, no CRDs).

**Root cause (per the guide manifest's own in-line comment, confirmed live
on this cluster):** `llamastackoperator: Managed` is deprecated and, left
`Managed`, aborts the whole module-provisioning batch at runlevel 32 —
which blocks `aigateway` and `mlflowoperator` from ever installing their
CRDs, regardless of what `modelsAsAService.managementState` says. This
sandbox's pre-provisioned DSC had `llamastackoperator: Managed`, so
`aigateway` was permanently stuck even though someone/something had already
flipped the nested MaaS flag.

**Fix applied to the live cluster (targeted merge patch, not a full
`datasciencecluster.yaml` apply, to avoid touching unrelated pre-provisioned
components like `trainer`/`kueue` on this shared sandbox):**

```bash
oc patch datasciencecluster default-dsc --type=merge -p '{
  "spec": {
    "components": {
      "aigateway": {"managementState": "Managed", "modelsAsAService": {"managementState": "Managed"}},
      "llamastackoperator": {"managementState": "Removed"},
      "ogx": {"managementState": "Managed"},
      "mlflowoperator": {"managementState": "Managed"}
    }
  }
}'
```

**Fix applied to this vendored script:** Phase 0 and the Phase 4 gate now
also check the parent `aigateway.managementState`, so a future run (or a
different sandbox with the same pre-provisioned drift) re-applies Phase 4
instead of silently skipping it. See the diff in `scripts/setup-maas.sh`.

## Cluster-side bug: `maas-api` CrashLoopBackOff — "found 2" Gateway Services

**Symptom:** After the DSC fix above, the operator auto-created `maas-api`
in `redhat-ai-gateway-infra`, but it crash-looped with:

```
error: failed to register handlers: failed to resolve gateway internal
address: expected 1 gateway service for openshift-ingress/maas-default-gateway,
found 2: [maas-default-gateway-openshift-ai-inference maas-default-gateway-openshift-default]
```

**Root cause:** this sandbox's pre-provisioned RHOAI catalog already had a
`Gateway/maas-default-gateway` object (created 2026-10-27, on GatewayClass
`openshift-ai-inference`, with a Service named
`maas-default-gateway-openshift-ai-inference`). When Phase 2 of
`setup-maas.sh` ran (today, 2026-10-28) it detected a hostname mismatch on
that pre-existing Gateway and **re-applied it onto the guide's own
GatewayClass** (`openshift-default`), which made the Gateway controller
provision a *second* Service, `maas-default-gateway-openshift-default`. The
first Service was never garbage-collected even though both are owned by the
same `Gateway` UID (confirmed via `ownerReferences` — same owner, same
selector, same endpoints) — the Gateway API implementation on this cluster
leaves the old per-class Service behind on a `gatewayClassName` switch.
`maas-api` hard-fails if it finds anything other than exactly one Service
for the Gateway it's configured to use.

This is specific to sandboxes that already had a `maas-default-gateway`
object under a *different* GatewayClass before `setup-maas.sh` ran — not
expected on a truly blank cluster, where the Gateway is created fresh under
`openshift-default` and only ever has one Service.

**Fix applied to the live cluster (one-time, not re-applicable by the
script — it's a stale-object cleanup, not a config toggle):**

```bash
oc delete svc maas-default-gateway-openshift-ai-inference -n openshift-ingress
oc rollout restart deployment/maas-api -n redhat-ai-gateway-infra
```

Verified safe to delete: both Services share the same `ownerReferences`
(the single `Gateway/maas-default-gateway` object), the same pod selector,
and the same endpoints — the deleted one was the orphan left over from the
GatewayClass switch, not a second independent object.

**Not patched into `scripts/setup-maas.sh`:** this is sandbox-specific
cleanup of a pre-existing resource under an unrelated GatewayClass, not a
reproducible step the script should always run (on a clean cluster there is
no second Service to delete). If you hit the same `maas-api` crash on
another sandbox, check `oc get svc -n openshift-ingress | grep
<gateway-name>` for duplicates sharing the Gateway's `ownerReferences` UID
before assuming it's the same cause.

## Cluster-side bug: `manifests/06-verification/verify.sh` can delete the whole `models-as-a-service` namespace

**Severity: high — this one briefly took down the entire MaaS platform.**

**Symptom:** after a normal `verify.sh` run (Phase 6 "Cleanup"), the log
printed `namespace "models-as-a-service" deleted` / `Deleted namespace
models-as-a-service`. Seconds later: `maas-api` pod gone
(`redhat-ai-gateway-infra` → "No resources found"), external
`/maas-api/health` → `HTTP 000`, and
`DataScienceCluster/default-dsc` condition `ModelsAsAServiceReady` flipped
to `False` with message `AITenant: tenant namespace
"models-as-a-service" is terminating; MaasTenantConfig: default
MaasTenantConfig not yet created`.

**Root cause:** `verify.sh`'s cleanup only checks
`oc get maassubscription,maasauthpolicy -n models-as-a-service` to decide
whether the namespace is "empty" before deleting it. It never checks for
the operator-owned `Tenant`/`MaasTenantConfig`/`AITenant` CRs that also
live in that namespace — the actual MaaS tenant, which `verify.sh` does
not create and must never delete. On a sandbox where no *persistent*
MaaSSubscription/MaaSAuthPolicy exists yet (e.g. right after
`setup-maas.sh`, because Phase 5 only checked `LLMInferenceService` count
and skipped re-applying the governance manifests for an
already-deployed model), the only subscription/policy present are the
ones `verify.sh` itself just created and is about to delete — so the
"remaining" count hits `0` and it deletes the entire shared tenant
namespace.

**Recovery:** the `aigateway` operator self-healed within ~30-45s
(recreated the namespace, `Tenant/default-tenant`, and the `maas-api`
pod) once it reconciled again — no manual intervention was needed beyond
waiting and re-checking `oc get maastenantconfigs -A` / `curl
.../maas-api/health`. This self-healing is reassuring but should not be
relied on; a sandbox with slower reconciliation, or one where `aigateway`
is not actively `Managed`, would stay down.

**Fix applied to this vendored script:** removed the `oc delete namespace
"$MAAS_NS"` branch entirely from `verify.sh`'s cleanup. `$MAAS_NS` is a
shared platform namespace the script does not own; it should only ever
clean up the specific `maassubscription`/`maasauthpolicy` objects it
created inside it (which it already does, earlier in the same cleanup
function), never the namespace itself.

## Environment characteristic (not patched): occasional bare "000" on isolated gateway requests

**Observation, not a script bug:** across 5 `verify.sh` runs on this
sandbox, roughly 1 in ~15-20 individual `curl` calls to
`https://maas.apps.ocp.mqgbd.sandbox840.opentlc.com` got a bare `000`
(connection dropped/timed out) with **no corresponding entry in
`maas-api`'s access log** — i.e. the request never reached the
application. It was never the same logical check twice (seen once on
"Unauthenticated request", once on "Invalid token", once on "Testing
inference"), and a bare retry 3s later always succeeded. This points to
occasional packet loss/connection drops on the path to the AWS NLB
fronting `maas-default-gateway` on this particular sandbox, not an
application or governance bug.

**Fix applied (defensive, Phase 4 only):** wrapped the two Phase 4 checks
in a 3-attempt retry (`auth_check_curl`, 3s apart) that only retries on a
literal `000` — any real HTTP status (including a correct `401`/`403`, or
a genuinely wrong one) still returns on the first try, so this cannot mask
a real auth-enforcement regression. Phases 1, 3, and 5 already had their
own retry logic (health check) or implicitly tolerate one flaky request
(rate-limit burst test counts successes vs. 429s across 16 calls) and were
left as-is — if you see an isolated `HTTP 000`/empty body on this sandbox
during the corporate-scenario demo too, re-run the single request before
assuming it's a governance problem.

## Environment characteristic: single-node sandbox → ~25-40% dropped connections under rapid-fire bursts

**Found while running `demo/corporate-scenario/run-demo.sh`:** the Phase-6
flakiness above (~1-in-15-20) got dramatically worse under the
corporate-scenario demo's rapid consecutive request bursts: direct,
reproducible testing showed **3 of 8** back-to-back plain `GET
/maas-api/health` calls (no auth, no model, no governance involved at
all) returning a bare `000` within ~0.2s (too fast to be a timeout - a
dropped/reset connection), split roughly evenly across both of the
Gateway's two DNS-resolved IPs. `oc get nodes` confirms this sandbox is a
**single-node cluster** (`externalTrafficPolicy: Cluster`, one node total)
— so this isn't a Kubernetes-level node-routing issue, it's upstream of
that (AWS NLB or the single node's networking stack under load from
everything else running on it: Keycloak, pipelines, multiple simulator
pods, etc.).

**Conclusion:** this is a property of this specific sandbox's
infrastructure under concurrent load, not a MaaS/governance defect — it
reproduces identically on a trivial unauthenticated health check with no
MaaS logic involved.

**Fix applied:** extended the "retry on a dropped connection, never on a
real response" pattern from Phase 4 of `verify.sh` into
`demo/corporate-scenario/run-demo.sh` (`fire_burst`, `fire_denied`,
`login_and_key`) and `verify-scenario.sh` (`fire_one`, `login_and_key`,
the eng-2 key-multiplication key minting) — initially as a single retry,
then bumped to up to 3 attempts per call after a single retry still left
a measurable "other" count in `run-demo.sh`'s bursts (drop rate under
rapid-fire load on this sandbox is high enough that two drops in a row on
the same logical request isn't rare). Every retry condition checks
specifically for `000` (curl connection-level failure), `500` (stale
upstream connection), or an empty response body with no `.key` field —
any real HTTP status, including a correct `403`/`429`, returns
immediately without a retry, so none of these changes can mask an actual
governance regression.

See the diff in
`manifests/06-verification/verify.sh`.
