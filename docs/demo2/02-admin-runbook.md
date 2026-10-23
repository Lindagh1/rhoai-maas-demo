# Demo 2 — Administrator runbook (Scenario B)

This is the exact, real procedure an RHOAI administrator follows to grant
a non-admin group access to Demo 1's already-deployed native model
(`demo-simulator` in `rhoai-maas-demo`), using Demo-2-specific,
clearly-named resources that cannot collide with anything else on the
sandbox.

Prerequisites: Demo 1 complete and `make demo1-verify` passing (model
`Ready`, MaaS enabled). Logged in as a cluster-admin (`oc login` with an
account that can create namespaced CRs in `models-as-a-service`).

## 0. Detect the identity provider (read-only, do this first)

```
make demo2-detect-idp
```

On this sandbox this reports `keycloak-incluster` (in-cluster Red Hat
Build of Keycloak, single realm, single custom OAuth client — verified
sandbox-scoped before any mutation; see
[`01-environment-audit.md`](01-environment-audit.md)). A different
sandbox may report `htpasswd` or `oidc-other` — see
[`09-auth-oidc-entra.md`](09-auth-oidc-entra.md) for both of those paths.

## 1. Create the non-admin test identity

```
make demo2-create-identity
```

This runs [`scripts/demo2/01-create-test-identity.sh`](../../scripts/demo2/01-create-test-identity.sh),
which:

1. Re-confirms the IdP strategy.
2. For `keycloak-incluster`: verifies the realm is sandbox-scoped
   (`kc_assert_sandbox_scoped()` — exactly one custom OAuth client,
   this cluster's own), then creates `maas-demo2-user` via the Keycloak
   Admin API (admin token read from the cluster-generated
   `keycloak-initial-admin` Secret, never hardcoded). A generated
   password is written **once**, directly, to
   `secrets/demo2/maas-demo2-user.password` (chmod 600, gitignored).
3. Creates (or confirms) the OpenShift `Group` `maas-demo2-developers`
   and adds `maas-demo2-user` to it — OpenShift does **not** auto-sync
   OIDC group claims into native `Group` objects, so this step is always
   required regardless of IdP technology.
4. Verifies (once) that a real browser OAuth login works for this
   identity, and that it holds **zero** elevated RBAC
   (`oc auth can-i --list` as this identity — confirmed empty beyond
   defaults in [`01-environment-audit.md`](01-environment-audit.md)).

This step is additive only: it never touches any other user, group, or
existing IdP configuration. Because it mutates **shared** identity
infrastructure (the realm backing every login on this sandbox, not a
Demo-2-scoped Kubernetes object), this project explicitly asked the user
for a go-ahead before running it the first time — consistent with the
task's "require explicit confirmation before modifying shared security,
identity, Gateway or cluster-level configuration" rule. Re-running it is
idempotent (it checks for existence before creating).

## 2. Grant access — declarative / GitOps workflow (verified, real)

```
make demo2-grant-access
```

This runs [`scripts/demo2/10-admin-grant-access.sh`](../../scripts/demo2/10-admin-grant-access.sh),
which:

1. Fails fast if the prerequisite `MaasTenantConfig` (`default-tenant` in
   `models-as-a-service`) or the target `LLMInferenceService` don't
   exist yet (Demo 1 not applied).
2. Validates every manifest under `manifests/demo2/` with
   `oc apply --dry-run=server` against the **live** cluster CRDs before
   ever applying anything for real — per the task's explicit requirement
   to never blindly copy manifests from older RHOAI releases.
3. Applies, idempotently (`--server-side=true`):
   - [`manifests/demo2/10-maas-subscription.yaml`](../../manifests/demo2/10-maas-subscription.yaml) — `MaaSSubscription/maas-demo2-subscription`, `owner.groups: [maas-demo2-developers]`, `modelRefs: [{name: demo-simulator, namespace: rhoai-maas-demo}]`, a generous token-rate limit, `priority: 10`.
   - [`manifests/demo2/11-maas-authpolicy.yaml`](../../manifests/demo2/11-maas-authpolicy.yaml) — `MaaSAuthPolicy/maas-demo2-access`, `subjects.groups: [maas-demo2-developers]`, same model reference.
   - [`manifests/demo2/12-maas-subscription-ratelimit-test.yaml`](../../manifests/demo2/12-maas-subscription-ratelimit-test.yaml) — a **separate**, deliberately tiny (50 tokens/1 minute) `MaaSSubscription/maas-demo2-subscription-ratelimit-test`, `priority: 1`, used **only** by Scenario E's rate-limit test — never the main demo pitch, and never touching any other sandbox user's quota.
4. Verifies, live, after applying:
   - Both CRs report `phase: Active`.
   - `MaaSModelRef/demo-simulator`'s `status.phase` transitions to
     `Ready` (`GovernanceAttached` + `RuntimeReady` + `Ready` conditions
     all `True`) — **confirmed live** on this sandbox.
   - The subscription's `owner.groups` is **exactly**
     `[maas-demo2-developers]` (not accidentally broader).
   - The subscription's `modelRefs` is **exactly**
     `rhoai-maas-demo/demo-simulator` (not accidentally broader — i.e.
     this does not grant access to any other model).
   - Same two checks for the AuthPolicy's `subjects.groups` /
     `modelRefs`.

**Real finding, verified by test (not assumed):** changing a
`MaaSSubscription`'s token-rate limit or model list later does **not**
automatically re-synchronize an existing, already-created
`MaaSAuthPolicy` — they are two independent CRs, each separately
reconciled. If you change the subscription's quota, the AuthPolicy still
exists exactly as created and does not need re-creation for a simple
quota change (quota lives on the subscription, not the authpolicy) — but
if you change *which group or model* a subscription targets without also
updating the matching AuthPolicy's `subjects`/`modelRefs`, the two will
drift out of sync and the model can end up ungoverned or mis-governed.
Always review both CRs together when changing either.

Idempotency verified live: re-running `make demo2-grant-access` after
the objects already exist produces no errors and no duplicate resources
(confirmed during this project's work, via `scripts/demo2/99-cleanup-access.sh`
removing the objects and `10-admin-grant-access.sh` re-creating them
identically).

## 3. Grant access — dashboard UI workflow ("Create a matching authorization policy")

**Status: BLOCKED on this sandbox — not executed, documented honestly rather than simulated.**

Red Hat's dashboard lets an admin create a `MaaSSubscription` and check a
box labeled *"Create a matching authorization policy"* so the UI
provisions both CRs together in one step — the UI equivalent of what
step 2 above does declaratively. This project could not exercise that
specific UI flow on this sandbox because doing so requires an
interactive dashboard login as a genuine cluster-admin **human** account
(not the `oc` CLI's existing cluster-admin token — the OpenShift/RHOAI
dashboard authenticates via a full browser OAuth redirect+cookie flow,
which cannot be shortcut from a bearer token already held by a CLI
session). This sandbox's provisioned admin identity (`admin`, mapped via
Keycloak group `keycloak-sso-user:admin` → `cluster-admin`) is **shared
sandbox infrastructure, not a Demo-2-scoped resource** — discovering or
resetting its password would mean mutating a shared account, which this
project's standing rule ("never touch shared/non-demo2-prefixed
resources without explicit confirmation") does not permit without asking
first.

Per the task's own guidance — *"For steps requiring an interactive human
login or privileged changes, prepare the exact procedure and report the
blocker rather than simulating success"* — the manual procedure a real
admin would follow (per Red Hat's official documentation, not invented
here) is:

1. Log into the RHOAI dashboard as a cluster-admin.
2. Navigate to **Gen AI studio → API keys → Subscriptions tab**.
3. Click **Create subscription** (admin view of this page offers
   subscription creation; the non-admin view does not — confirmed from
   the non-admin side in Scenario A/C).
4. Fill in the subscription's name, target group(s), model(s), and
   token-rate limit.
5. Check **"Create a matching authorization policy"**.
6. Submit, then verify via `oc get maassubscription,maasauthpolicy -n models-as-a-service`
   that both CRs now exist with the same shape step 2 above produces
   declaratively.

The declarative path (step 2) is functionally equivalent and has been
fully verified live; this dashboard path remains **NOT TESTED**, not
**FAIL** — it was never attempted, so no negative claim is made about it
either.

## 4. Cleanup (Demo 2 governance objects only)

```
make demo2-cleanup-access CONFIRM=yes
```

Runs [`scripts/demo2/99-cleanup-access.sh`](../../scripts/demo2/99-cleanup-access.sh),
gated behind `CONFIRM=yes`. Removes **only**
`maassubscription/maas-demo2-subscription`,
`maassubscription/maas-demo2-subscription-ratelimit-test`, and
`maasauthpolicy/maas-demo2-access` from `models-as-a-service`. Leaves
the test identity, group, and Demo 1's model completely untouched —
re-running `make demo2-grant-access` afterward restores the exact same
state (verified live during this project, used to temporarily reproduce
Scenario A's "no subscription" state for evidence capture).

## Troubleshooting

See [`05-troubleshooting.md`](05-troubleshooting.md) for the concrete
errors actually hit during this project (not hypothetical ones) and how
each was resolved.
