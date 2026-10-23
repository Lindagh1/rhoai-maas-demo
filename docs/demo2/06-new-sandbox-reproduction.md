# Demo 2 — Running this on a brand-new RHOAI 3.5 sandbox

**Success criterion (from the task spec):** a new Red Hat sandbox can
run Demo 1 followed by Demo 2, with minimal configuration, while
clearly distinguishing automated tests, administrator actions, and
genuine non-admin user actions.

This document is the single, ordered checklist to get there. It assumes
nothing about the new sandbox beyond: it is RHOAI 3.5, you have a
cluster-admin `oc` session, and Demo 1 has not yet been run there.

## 0. Prerequisites

- `oc login` as a cluster-admin.
- `make`, `bash`, `curl`, `dig`, `python3`, `jq`-free (this repo
  intentionally avoids `jq` in favor of `python3 -c`/inline scripts
  already present on every RHOAI sandbox image).
- `KEYFILE`/secret paths all live under `secrets/demo2/` — this
  directory is `chmod 700` and gitignored; nothing there is ever
  committed.

## 1. Run Demo 1 first (unmodified — Demo 2 never rebuilds it)

```
make demo1-audit
make demo1-prereqs
make demo1-enable-maas
make demo1-deploy-model
make demo1-publish
make demo1-verify-twice
```

Confirm `demo1-verify-twice` passes both times (idempotency). This
deploys and publishes the native model (`demo-simulator` /
`facebook/opt-125m`, or whichever model Demo 1 successfully deployed on
this sandbox) that Demo 2 will reuse without modification.

## 2. Audit the environment for Demo 2 (read-only, always safe)

```
make demo2-audit
```

This single command (wrapping `scripts/demo2/05-audit.sh`) reports:
which identity-provider strategy this sandbox uses, whether the Demo 2
test identity/group already exist, the current state of Demo 2's
governance objects (if any), the Demo 1 model's readiness, and which
local secret files already exist. **Run this on every new sandbox
before anything else in Demo 2** — never assume this sandbox's IdP or
starting state matches the one this repo was originally built against.

If this reports strategy `oidc-other` (a real external enterprise IdP,
e.g. Entra ID), stop here and follow
[`09-auth-oidc-entra.md`](09-auth-oidc-entra.md)'s manual procedure
instead of the automated identity-creation step below.

## 3. Create the test identity + group (idempotent, mostly additive)

```
make demo2-create-identity
```

For `keycloak-incluster` or `htpasswd` strategies, this creates
`maas-demo2-user` / `maas-demo2-developers` automatically. **This is the
one step that touches shared identity infrastructure** (the IdP backing
every login on the sandbox) rather than a purely Demo-2-scoped
Kubernetes object — per the task's rule to require explicit confirmation
before modifying shared security/identity config, confirm with whoever
owns the sandbox before running this the first time on a shared/
non-disposable environment. On a dedicated, disposable sandbox (the
normal case for this kind of demo), this is safe to run directly.

## 4. Grant access (admin, declarative — the verified path)

```
make demo2-grant-access
```

Validates every manifest against the **live** cluster's CRDs with a
server-side dry-run before applying anything, then creates the
`MaaSSubscription`(s) + `MaaSAuthPolicy` scoped to `maas-demo2-developers`
and the model Demo 1 actually deployed. Safe to re-run (idempotent).

## 5. Verify the whole environment is in the expected state

```
make demo2-verify
```

Checks: `MaaSModelRef` → `Ready`, both governance CRs → `Active`, and
(if already captured) both known API key files still return `200`.
Exits non-zero if anything is off — use this as the single
"is Demo 2 ready to present?" gate.

## 6. The one manual, human step: create the end-user's API key

There is **no script** for this, by design — Scenario C's entire point
is demonstrating the real, non-admin dashboard flow:

1. Log in to the RHOAI dashboard as `maas-demo2-user` (real browser
   OIDC/OAuth login, password from `secrets/demo2/maas-demo2-user.password`).
2. **Gen AI studio → API keys → Create API key**, scope it to
   `maas-demo2-subscription`, pick an expiration.
3. **Immediately** capture the one-time-shown key value with a direct
   `Write`-tool call (or, for a human presenter, just copy it) into
   `secrets/demo2/maas-demo2-user.apikey` (`chmod 600`). Never type it
   into a terminal command, never commit it.
4. Repeat for `maas-demo2-subscription-ratelimit-test` →
   `secrets/demo2/maas-demo2-user.ratelimit.apikey`, needed for
   Scenario E's rate-limit test.

## 7. Run the automated test scenarios

```
make demo2-test-inference    # Scenario D
make demo2-test-negative     # Scenario E (403 / 403 / 429 — bounded, self-restoring)
make demo2-check-usage       # Scenario F (admin-side Limitador metrics)
```

Each saves sanitized (API-key-redacted) evidence under `evidence/demo2/`.
Re-run `make demo2-verify` afterward to confirm the sandbox is back in
its normal governed state (the negative tests temporarily mutate and
always restore the governance objects).

## 8. Scenario G (revoke/regenerate) and Scenario A (if re-demonstrating from scratch)

Both are deliberately manual/dashboard-driven (see
[`03-end-user-runbook.md`](03-end-user-runbook.md)) — Scenario G because
it's the exact UI flow being demonstrated, Scenario A because it
requires temporarily removing the governance objects
(`make demo2-cleanup-access CONFIRM=yes`), capturing the "no
subscription" UI state, then restoring (`make demo2-grant-access`).

## 9. Cleanup (Demo 2 only — Demo 1 untouched)

```
make demo2-cleanup-access CONFIRM=yes
```

Removes only the three Demo-2-named governance CRs. To also remove the
test identity/group, do so manually via the same IdP-specific procedure
`01-create-test-identity.sh` used to create them (deliberately not
automated as a "delete a user" script — a destructive identity change
on shared IdP infrastructure should always be a reviewed, manual action).

## What differs on a sandbox with a different IdP

| This sandbox | A different sandbox might have |
|---|---|
| In-cluster Red Hat Build of Keycloak (`keycloak-incluster`) | A plain `HTPasswd` provider — fully supported, same `make` targets, just a different branch inside `01-create-test-identity.sh` |
| | An external enterprise OIDC provider (Entra ID, Okta, shared Red Hat SSO) — `oidc-other`; automation **refuses** to mutate it; follow [`09-auth-oidc-entra.md`](09-auth-oidc-entra.md) manually |
| Pre-existing `ServiceMonitor`/Limitador wiring already enabled | Possibly disabled observability — `make demo2-check-usage` will report the Limitador port-forward failing; see [`05-troubleshooting.md`](05-troubleshooting.md) |
| No pre-existing `MaaSSubscription`/`MaaSAuthPolicy` | Other sandbox users' subscriptions/policies already present — `make demo2-grant-access`'s manifests are scoped exclusively to `maas-demo2-*` names and `maas-demo2-developers`, and never list/modify other objects |

## What is genuinely NOT reproducible without extra, explicit human action

- The htpasswd and external-OIDC identity paths are implemented/
  documented but not exercised end-to-end on *this* sandbox (no such
  IdP present here) — see [`04-test-scenarios.md`](04-test-scenarios.md)'s
  status table.
- The dashboard UI's "Create a matching authorization policy" checkbox
  (Scenario B) requires an interactive cluster-admin browser login this
  project could not safely obtain — see
  [`02-admin-runbook.md`](02-admin-runbook.md) §3.
- The "AI asset endpoints" temporary 1-hour key flow is blocked by a
  real `403` even for a self-provisioned Project owner — see
  [`05-troubleshooting.md`](05-troubleshooting.md).

These are documented as genuine, verified blockers — not silently
skipped, and not faked as passing.
