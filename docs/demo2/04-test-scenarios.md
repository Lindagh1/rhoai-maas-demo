# Demo 2 — Test scenarios reference (A–G)

For each scenario: objective, preconditions, exact steps run, expected
behavior (per Red Hat's official docs / the task spec), and the **actual**
verified result on this sandbox. Any discrepancy between expected and
actual is called out explicitly — never silently "corrected" to match
the docs. See [`02-admin-runbook.md`](02-admin-runbook.md) and
[`03-end-user-runbook.md`](03-end-user-runbook.md) for the role-based
narrative; this document is the flat test matrix. Status definitions
match `DEMO2-RESULTS.md`: **PASS** / **FAIL** / **BLOCKED** / **NOT TESTED**.

---

## Scenario A — user without any subscription

| | |
|---|---|
| **Preconditions** | `maas-demo2-user` exists; `maas-demo2-subscription`/`maas-demo2-access` temporarily absent (`make demo2-cleanup-access CONFIRM=yes`) |
| **Steps** | Log in as `maas-demo2-user` → Gen AI studio → API keys (Subscriptions tab, API keys tab) → attempt Create API key |
| **Expected (docs)** | Subscriptions view can display "No subscriptions" |
| **Expected (Sopra Steria report)** | "subscription required" |
| **Actual** | Subscriptions tab: *"Request a subscription... contact your administrator."* API keys tab: *"No API keys... Create a key to start making requests to models available in your subscriptions."* Create-key dialog: *"No subscriptions available... Ask your admin to add you to a subscription."* Subscription selector has `pointer-events: none` (not just visually disabled). |
| **Discrepancy** | Neither prior report's exact wording matches; this version's real text is recorded above, not forced to match either. |
| **Status** | **PASS** (behavior reproduced and documented faithfully) |

---

## Scenario B — administrator grants access

| | |
|---|---|
| **Preconditions** | Demo 1 verified (`make demo1-verify`); cluster-admin `oc` session |
| **Steps** | `make demo2-grant-access` → server-side dry-run validation → apply `MaaSSubscription` ×2 + `MaaSAuthPolicy` → verify CR state + `MaaSModelRef` readiness |
| **Expected** | Both CRs `Active`; `MaaSModelRef` → `Ready`; dashboard "Create a matching authorization policy" checkbox also works |
| **Actual (declarative/GitOps)** | Verified live: `maassubscription/maas-demo2-subscription` and `/maas-demo2-subscription-ratelimit-test` both `Active`; `maasauthpolicy/maas-demo2-access` `Active`; `MaaSModelRef/demo-simulator` → `status.phase: Ready` (`GovernanceAttached`/`RuntimeReady`/`Ready` all `True`). `owner.groups`/`subjects.groups` exactly `[maas-demo2-developers]`; `modelRefs` exactly `rhoai-maas-demo/demo-simulator` (no unintended broader grant). Idempotent re-apply confirmed (no errors, no duplicates). |
| **Actual (dashboard UI checkbox)** | **Not executed** — requires an interactive cluster-admin dashboard login, which this project could not safely obtain without mutating a shared, non-Demo-2-scoped account. See [`02-admin-runbook.md`](02-admin-runbook.md) §3 for the exact manual procedure. |
| **Real finding** | Changing a subscription's model/group targeting later does **not** auto-resync an existing AuthPolicy's `subjects`/`modelRefs` — they are independently reconciled CRs. |
| **Status** | **PASS** (declarative path) / **NOT TESTED** (dashboard checkbox path) |

---

## Scenario C — end-user discovers and accesses the model

| | |
|---|---|
| **Preconditions** | Scenario B complete |
| **Steps** | Log in as `maas-demo2-user` → Subscriptions tab (view assigned model + token-rate limits) → Create API key (scope to a subscription, set expiration) → capture key value once |
| **Expected** | Subscription visible with model + limits; key creation works; both a ~1h temporary key (model endpoints) and a configurable-expiration key (API keys page) are available |
| **Actual** | Subscriptions tab shows `maas-demo2-subscription` with expandable token-limit detail (`2,000 / 1 minute`). API-keys-page key creation fully works: Subscription typeahead populated, Expiration offers `On date`/`After`/**`Use max value of 90 days`** (confirms the documented 90-day max). Key shown exactly once, `sk-oai-` prefix. |
| **Real finding** | The ~1-hour temporary-key flow from "AI asset endpoints" requires a Data Science Project; a self-provisioned Project still gets a real `403` (`"user does not have permission to access services in this namespace"`) from that page's own backend call — see `evidence/demo2/scenario-c-04-ai-asset-endpoints-blocked.txt`. |
| **Status** | **PASS** (API-keys-page flow) / **BLOCKED** (model-endpoints temporary-key flow — real, captured 403, not simulated) |

---

## Scenario D — real inference test

| | |
|---|---|
| **Preconditions** | Scenario C complete, a captured API key in `secrets/demo2/maas-demo2-user.apikey` |
| **Steps** | `make demo2-test-inference` → `GET /v1/models` then `POST /v1/chat/completions` with the real key |
| **Expected** | Auth succeeds; model listed; inference returns a valid response from the native model; usage info present where supported |
| **Actual** | `GET /v1/models` → `200`. `POST /v1/chat/completions` → `200` using the model's **full id** (`publishers/rhoai-maas-demo/models/facebook/opt-125m`; the short alias alone is rejected — real finding). Genuine reply + `usage` object (`prompt_tokens`/`completion_tokens`/`total_tokens`) from Demo 1's real `llm-d-inference-sim` backend. No `X-RateLimit-*` headers observed on this `200` (recorded as observed, not assumed). |
| **Evidence** | `evidence/demo2/scenario-d-01-models.txt`, `scenario-d-02-inference.txt` (API key redacted) |
| **Status** | **PASS** |

---

## Scenario E — authorization and rate-limiting tests

All three tests use `scripts/demo2/40-test-negative.sh`: bounded, with a guaranteed restore (`trap`) of the governance objects regardless of outcome, and a strict max request count for the rate-limit test (never an uncontrolled load test).

| Test | Expected (docs) | Actual | Real finding |
|---|---|---|---|
| **1. No AuthPolicy** (subscription present, AuthPolicy removed) | `403` | **`403`** | MaaSModelRef flips to `Pending`/`NoPairingFound`; matches expectation |
| **2. Missing subscription/quota** (AuthPolicy present, the key's own subscription removed) | docs/task phrasing implies `429` | **`403`**, body `"requested subscription not found"` | A key's access check is bound to its **specific granting subscription**. Deleting it → `403` even though the model stays `Ready` overall (paired via the other, unrelated subscription). `429` is reserved for genuine quota exhaustion (Test 3), not "no grant at all". |
| **3. Rate limit reached** (dedicated 50-tokens/1-minute subscription, ≤15 bounded requests, `max_tokens=5` each) | `429` + possible rate-limit headers | **`429`** after 15 requests | Confirmed enforced; counters cross-checked against Limitador's own metrics (Scenario F: `authorized_calls=15`, `limited_calls=1` — exact match) |

Evidence: `evidence/demo2/scenario-e-01-no-authpolicy.txt`,
`scenario-e-02-no-subscription.txt`, `scenario-e-03-rate-limit.txt`.

**Status: PASS** for all three (each produced a real, captured, bounded
result; Test 2's actual status differs from the docs' implied `429`, and
that discrepancy is the documented finding, not a failure of the test
itself).

---

## Scenario F — usage visibility

| | |
|---|---|
| **Non-admin (dashboard)** | Subscriptions tab shows: subscription name, active-key count, **configured** token-rate-limit ceiling. **Never**: actual consumption, remaining quota, or usage history/graph, in either Subscription view or Model view. |
| **Admin (Kuadrant/Limitador)** | `GET /metrics` on the `limitador-limitador` service (port 8080, reached via `oc port-forward`) exposes real-time Prometheus counters: `authorized_calls`, `limited_calls`, `authorized_hits`, scoped per Gateway `HTTPRoute` (i.e. per model via the `limitador_namespace` label). Live values exactly matched Scenario E Test 3's real calls (`authorized_calls=15`, `limited_calls=1`). |
| **Scrape wiring** | A `ServiceMonitor` (`limitador-metrics`, namespace `redhat-ods-monitoring`) is **pre-provisioned by the MaaS operator itself** (owned by its `Config` CR `maas.opendatahub.io/v1alpha1`) — not something this demo had to set up. |
| **Real limitation** | Limitador's metrics are aggregated **per-model only** — never per-subscription, per-user, or per-key. Confirmed by inspecting the `MaaSSubscription` CRD schema directly: `.status` has `conditions`, `modelRefStatuses`, `phase`, `tokenRateLimitStatuses` — **no usage/consumption field at all**. |
| **"Observe & monitor → Dashboard → Usage"** | Not found as a distinct admin dashboard page on this installed version; the real, verified admin-side observability path is the Limitador Prometheus metrics above, not a dedicated "Usage" screen. Not claiming this screen doesn't exist anywhere in RHOAI — only that it was not found/verified here. |
| **Evidence** | `evidence/demo2/scenario-f-01-admin-limitador-metrics.txt`, `scenario-f-02-subscription-cr-no-usage-field.txt`, `scenario-f-03-user-dashboard-view.txt` |
| **Status** | **PASS** (non-admin visibility fully characterized; admin visibility verified via the real Limitador metrics path) / a dedicated "Usage" dashboard screen specifically is **NOT TESTED** (not located on this version — see above) |

---

## Scenario G — API key revocation and regeneration

| | |
|---|---|
| **Steps** | Create a disposable test key → verify `200` → revoke via dashboard (kebab → Revoke → typed confirmation) → repeat the same call → verify rejection → create a fresh replacement key → verify `200` |
| **Expected (task spec)** | Revoked key → `401 Unauthorized` |
| **Actual** | Revoked key → **`403 Forbidden`**, empty body. Verified across three independently revoked keys during this project. Fresh replacement key created and verified `200` immediately — no infrastructure change needed. |
| **Discrepancy** | `403`, not the documented `401` — recorded as the genuine, repeatable behavior of this installed version. |
| **Evidence** | `evidence/demo2/scenario-g-01-before-revoke.txt`, `scenario-g-02-after-revoke.txt`, `scenario-g-03-regenerate.txt` |
| **Status** | **PASS** (full real revoke→regenerate cycle demonstrated; the HTTP status discrepancy from the task's expectation is itself the documented finding) |

---

## Authentication path (OpenShift OAuth vs external OIDC/Entra ID)

See [`09-auth-oidc-entra.md`](09-auth-oidc-entra.md) for full detail.
Summary: `keycloak-incluster` strategy verified live and used for the
entire demo above (real OpenShift OAuth identity, genuinely non-admin).
The `htpasswd` strategy is implemented but not exercised on this
sandbox (no htpasswd IdP present here). The external-OIDC/Entra-ID
strategy is deliberately **refused** by automation and documented as a
manual procedure, **not executed** — per the task's explicit instruction
not to introduce an Entra ID integration just to complete the
demonstration.

| Path | Status |
|---|---|
| In-cluster Keycloak (OpenShift OAuth) | **PASS** (used throughout this entire demo) |
| HTPasswd | **NOT TESTED** (implemented, no htpasswd IdP on this sandbox to exercise it against) |
| External OIDC / Entra ID | **NOT TESTED** (deliberately not executed; manual procedure + architecture documented) |
