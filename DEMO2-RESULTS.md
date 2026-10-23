# Demo 2 Results — MaaS End-User Journey (RHOAI 3.5)

**Sandbox:** same disposable OpenTLC sandbox as Demo 1 (hostname masked
per policy — see `docs/sandbox-audit.md` / `docs/demo2/01-environment-audit.md`).
**Identity provider:** in-cluster Red Hat Build of Keycloak (OIDC),
verified sandbox-scoped before any mutation.
**Model under test:** Demo 1's native `demo-simulator`
(`facebook/opt-125m`, CPU-only `llm-d-inference-sim`), reused unmodified.
**Test identity:** `maas-demo2-user` (group `maas-demo2-developers`) —
a genuine, non-admin, real-browser-OIDC-login OpenShift identity, never
an admin token disguised as a user.

Status legend: **PASS** (verified live, real) / **FAIL** (verified live,
did not behave as required) / **BLOCKED** (not executed — genuine
external/safety blocker, with the manual procedure documented) /
**NOT TESTED** (in scope but not attempted, no negative claim made).

## Scenario summary

| Scenario | Status | Evidence | Notes |
|---|---|---|---|
| **A** — no subscription | **PASS** | (UI text captured inline; see `docs/demo2/03-end-user-runbook.md`) | Real UI wording differs from both the official docs ("No subscriptions") and the reported customer wording ("subscription required") — actual text documented verbatim, not forced to match either. |
| **B** — admin grants access (declarative/GitOps) | **PASS** | `evidence/` n/a — verified via `oc get`/CR status, see `docs/demo2/02-admin-runbook.md` | `MaaSModelRef` confirmed `Ready`; idempotent re-apply verified. |
| **B** — admin grants access (dashboard checkbox) | **NOT TESTED** | — | Requires an interactive cluster-admin dashboard login; no safe way to obtain this without mutating shared, non-Demo-2 sandbox credentials. Manual procedure documented in `docs/demo2/02-admin-runbook.md` §3. |
| **C** — discover + create API key (API keys page) | **PASS** | — | Full real flow: subscription visibility, 90-day max expiration, one-time key reveal. |
| **C** — discover + create API key (AI asset endpoints, ~1h temp key) | **BLOCKED** | `evidence/demo2/scenario-c-04-ai-asset-endpoints-blocked.txt` | Real, captured `403` (`"user does not have permission to access services in this namespace"`) even for a self-provisioned Project owner. |
| **D** — real inference | **PASS** | `evidence/demo2/scenario-d-01-models.txt`, `scenario-d-02-inference.txt` | Real `200` + token usage from the native model. Full model id required (short alias rejected). |
| **E.1** — no AuthPolicy | **PASS** | `evidence/demo2/scenario-e-01-no-authpolicy.txt` | `403`, matches docs' implication. |
| **E.2** — missing subscription/quota | **PASS** | `evidence/demo2/scenario-e-02-no-subscription.txt` | **`403`** (`"requested subscription not found"`), not the docs-implied `429` — real finding, documented. |
| **E.3** — rate limit reached | **PASS** | `evidence/demo2/scenario-e-03-rate-limit.txt` | Real `429` after 15 bounded requests on a dedicated 50-tokens/1-minute subscription; counters cross-checked against Limitador. |
| **F** — non-admin usage visibility | **PASS** | `evidence/demo2/scenario-f-03-user-dashboard-view.txt` | Shows configured limit only, never actual consumption/remaining quota. |
| **F** — admin usage visibility (Limitador metrics) | **PASS** | `evidence/demo2/scenario-f-01-admin-limitador-metrics.txt`, `scenario-f-02-subscription-cr-no-usage-field.txt` | Real Prometheus counters, pre-wired by the MaaS operator itself; aggregated per-model only (no per-subscription/user breakdown). |
| **F** — dedicated "Observe & monitor → Usage" dashboard screen | **NOT TESTED** | — | Not located as a distinct page on this installed version; not claiming it doesn't exist elsewhere, only that it wasn't found/verified here. |
| **G** — revoke + regenerate | **PASS** | `evidence/demo2/scenario-g-01-before-revoke.txt`, `scenario-g-02-after-revoke.txt`, `scenario-g-03-regenerate.txt` | Revoked key → **`403`**, not the task-spec-expected `401` — real finding, documented. Fresh key works immediately. |
| **Auth path** — OpenShift OAuth / in-cluster Keycloak | **PASS** | throughout | Used for the entire demo above. |
| **Auth path** — HTPasswd | **NOT TESTED** | — | Implemented in `scripts/demo2/01-create-test-identity.sh`; no htpasswd IdP present on this sandbox to exercise it against. |
| **Auth path** — external OIDC / Microsoft Entra ID | **NOT TESTED** | — | Deliberately not executed, per the task's instruction not to introduce an Entra ID integration just to complete the demo. Manual procedure + architecture diagram in `docs/demo2/09-auth-oidc-entra.md`. |

## Real findings that differ from official documentation (summary)

1. Scenario A's exact "no subscription" UI wording.
2. Scenario E.2: missing-subscription access returns `403`, not `429`.
3. Scenario G: a revoked key returns `403`, not `401`.
4. Scenario C: the "AI asset endpoints" temporary-key flow is blocked by
   a real `403`, even for a self-provisioned Project owner.
5. `/v1/chat/completions` requires the model's **full id**
   (`publishers/<ns>/models/<name>`), not the short alias.
6. Kuadrant/Limitador's usage metrics are aggregated per-model only —
   `MaaSSubscription`'s own CR status has no usage/consumption field.

None of these were "fixed" to match the docs — each is recorded as the
actual, verified behavior of this installed RHOAI 3.5 MaaS version,
per the task's explicit instruction to never fabricate or assume
behavior.

## Security note

Two API keys created early in this project were briefly exposed as
literal values in terminal commands during development. Both were
treated as compromised, revoked through the real dashboard flow, and
confirmed dead (`403`) before replacement keys were created using a
strict one-time, `Write`-tool-direct-from-dialog capture method (never
re-typed into a Shell command). This incident and its remediation are
documented in `evidence/demo2/scenario-g-*.txt` and this repo's chat
history; no exposed key remains valid.

## Full detail

- Expected-vs-actual matrix, per sub-test: `docs/demo2/04-test-scenarios.md`
- Admin procedure: `docs/demo2/02-admin-runbook.md`
- End-user procedure: `docs/demo2/03-end-user-runbook.md`
- Troubleshooting (real errors + fixes): `docs/demo2/05-troubleshooting.md`
- New-sandbox checklist: `docs/demo2/06-new-sandbox-reproduction.md`
- Sources: `docs/demo2/07-source-references.md`
- 10–12 min presentation script: `docs/demo2/08-presentation-script.md`
- Auth (OAuth vs OIDC/Entra ID): `docs/demo2/09-auth-oidc-entra.md`
- Sanitized evidence: `evidence/demo2/`
- Manifests: `manifests/demo2/`
- Automation: `scripts/demo2/`, `make demo2-*` (see `Makefile`)
