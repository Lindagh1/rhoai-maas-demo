# Identity providers for Demo 2: OpenShift OAuth, in-cluster Keycloak, and external OIDC (e.g. Entra ID)

Demo 2 needs exactly one non-admin end-user identity (`maas-demo2-user`,
member of group `maas-demo2-developers`) to drive Scenarios A–G. Every
other RHOAI sandbox this demo might run on (including the partner's own
environment) can have a **different** identity-provider (IdP) setup than
this reference sandbox. This document records what was actually verified
on this cluster, and the honest, not-yet-executed procedure for the two
other realistic cases a partner sandbox could present.

All of this is implemented, read-only-safe, in
[`scripts/demo2/00-detect-identity-provider.sh`](../../scripts/demo2/00-detect-identity-provider.sh)
(detection only, never mutates) and
[`scripts/demo2/01-create-test-identity.sh`](../../scripts/demo2/01-create-test-identity.sh)
(creates the identity, branching on the detected strategy).

## How detection works

`detect_idp_strategy()` (in [`scripts/demo2/lib.sh`](../../scripts/demo2/lib.sh))
reads the live `oauth/cluster` CR — never assumes — and returns one of:

| Strategy | Meaning |
|---|---|
| `none` | No `identityProviders` configured at all (bootstrap/kubeadmin-only cluster). |
| `htpasswd` | An `HTPasswd`-type provider is configured. |
| `keycloak-incluster` | An `OpenID`-type provider is configured, **and** its issuer resolves to this same cluster's own domain, **and** the Keycloak Operator CRDs + a `Keycloak` CR actually exist here. |
| `oidc-other` | An `OpenID`-type provider is configured, but it does **not** meet the in-cluster-Keycloak criteria above (external issuer, e.g. a real enterprise IdP such as Microsoft Entra ID, Okta, or a shared Red Hat SSO instance). |

This is intentionally conservative: the in-cluster-Keycloak branch (the
only one that is ever mutated non-interactively) requires **both** an
in-domain issuer URL **and** proof that a Keycloak Operator is actually
installed here — a partner's external OIDC provider could otherwise
coincidentally share a similar-looking hostname and get misclassified as
safe to administer.

## What this sandbox actually has (verified live)

```
$ bash scripts/demo2/00-detect-identity-provider.sh
- name=rhbk type=OpenID

Detected strategy: keycloak-incluster
In-cluster Keycloak detected, backing the only configured OIDC provider.
```

Raw `oauth/cluster` spec (`identityProviders[0]`):

```json
{
  "mappingMethod": "claim",
  "name": "rhbk",
  "openID": {
    "claims": {
      "email": ["email"],
      "name": ["name"],
      "preferredUsername": ["preferred_username"]
    },
    "clientID": "idp-4-ocp",
    "clientSecret": { "name": "openid-client-secret-bb6zw" },
    "extraScopes": [],
    "issuer": "https://sso.<cluster-domain>/realms/sso"
  },
  "type": "OpenID"
}
```

This is **Red Hat Build of Keycloak (RHBK)**, installed in-cluster
(namespace `keycloak`), serving a single realm (`sso`) with exactly one
custom OAuth client (`idp-4-ocp` — this cluster's own OpenShift OAuth
integration). Before any mutation, `kc_assert_sandbox_scoped()` verifies
this realm has no *other* custom clients, confirming it is dedicated,
disposable sandbox infrastructure and not a shared enterprise IdP —
see [`01-environment-audit.md`](01-environment-audit.md).

Given `keycloak-incluster`, `01-create-test-identity.sh` creates
`maas-demo2-user` via the Keycloak Admin API (master-realm admin token
read from the cluster-generated `keycloak-initial-admin` Secret, never
hardcoded), then an OpenShift `Group` (`maas-demo2-developers`) via
`oc adm groups`, since **OpenShift does not automatically sync OIDC
group claims into native `Group` objects** — this has to be done
explicitly regardless of which OIDC provider is in front of it, and is
exactly what `MaaSSubscription`/`MaaSAuthPolicy`'s `owner.groups` /
`subjects.groups` fields target.

Real login verification for an OIDC/redirect-type provider cannot be done
with `oc login -u/-p` (confirmed: that returns a genuine, expected `401
Unauthorized` — the identity is OIDC-only, it has no direct password
grant at the OpenShift OAuth server). The real, working procedure (also
executed once during development of this script) is a one-time browser
login:

1. Visit `https://oauth-openshift.<cluster-domain>/oauth/token/request`
2. Log in as `maas-demo2-user` (password read locally from
   `secrets/demo2/maas-demo2-user.password`, never pasted into chat/logs)
3. Click "Display Token", then:
   `KUBECONFIG=secrets/demo2/maas-demo2-user.kubeconfig oc login --token=<token> --server=<api-url> --insecure-skip-tls-verify=true`
4. Immediately revoke it afterwards: `KUBECONFIG=secrets/demo2/maas-demo2-user.kubeconfig oc logout`

This confirmed real OAuth login succeeds and that `maas-demo2-user` has
zero elevated RBAC (see `01-environment-audit.md`).

## The other two cases (honest status: NOT executed on this sandbox)

### `htpasswd`

If `oauth/cluster` has an `HTPasswd`-type provider, `01-create-test-identity.sh`
appends `maas-demo2-user` to the **existing** htpasswd secret (reads the
current file, adds one line with `htpasswd -nbB`, re-applies the same
secret — additive, no other user touched). Login can then be verified
directly and non-interactively with `oc login -u -p`, since htpasswd is a
direct password grant. This path is implemented and would work, but this
sandbox does not use htpasswd, so it has not been exercised here.

### `oidc-other` (realistic stand-in for Entra ID / external enterprise OIDC)

This is the path a real partner sandbox integrated with **Microsoft Entra
ID** (or Okta, PingFederate, a shared corporate Red Hat SSO, etc.) would
hit. `01-create-test-identity.sh` deliberately **refuses** to mutate
anything in this case:

```
BLOCKED — manual procedure required. See docs/demo2/09-auth-oidc-entra.md for:
  - how to request/create a non-admin test account in that external IdP,
  - how group-claim mapping needs to be verified before MaaS subscriptions can target a Group,
  - the architecture diagram for this path (not executed on this sandbox).
```

This refusal is intentional, not a gap to be papered over: an external
enterprise IdP is shared infrastructure outside this demo's control, and
creating or mutating accounts there requires the partner's own IT
process, not an automated script run from a sandbox repo. The manual
procedure a partner would actually need to follow is:

1. **Request/obtain a non-admin test account** in the partner's Entra ID
   tenant (or ask the partner to point you at an existing low-privilege
   test user). This cannot be automated from inside the OpenShift
   cluster — it is the partner's IdP, managed outside this cluster.
2. **Verify the OIDC claim mapping** on `oauth/cluster`'s
   `identityProviders[].openID.claims` (`email`, `name`,
   `preferredUsername`, and critically **groups**, if the partner's Entra
   ID app registration emits a `groups` claim). If Entra ID is not
   configured to emit a usable group claim, OpenShift has no native
   Group to target, and `MaaSSubscription.spec.owner.groups` /
   `MaaSAuthPolicy.spec.subjects.groups` would need to target
   **individual users** (`owner.users` / `subjects.users`) instead of a
   group — both CRDs support this (confirmed from the CRD schema; see
   [`01-environment-audit.md`](01-environment-audit.md)), so the rest of
   this demo's Scenario B manifests would only need a one-line field
   change (`groups` → `users`), not a redesign.
3. **Log in once through the real browser OAuth flow** exactly as
   described above for `keycloak-incluster` (the procedure is identical
   for any OIDC/redirect-type provider — only the login page's branding
   differs) to confirm the account authenticates and to capture a CLI
   token for verification, if needed.
4. Proceed with Scenarios B–G exactly as documented elsewhere in
   `docs/demo2/` — nothing past identity creation depends on which OIDC
   provider is in front of OpenShift.

```
                 ┌─────────────────────────┐
                 │   Partner's Entra ID     │   (outside this cluster,
                 │   tenant / app reg.      │    outside this demo's
                 └───────────┬─────────────┘    automation reach)
                             │ OIDC (issuer, clientID/secret,
                             │ claims incl. optional "groups")
                             ▼
                 ┌─────────────────────────┐
                 │  oauth/cluster           │
                 │  identityProviders:      │
                 │   - type: OpenID         │
                 │     name: <partner-idp>  │
                 └───────────┬─────────────┘
                             │ detect_idp_strategy() → "oidc-other"
                             ▼
                 ┌─────────────────────────┐
                 │ 01-create-test-identity  │
                 │ .sh REFUSES to mutate;   │
                 │ prints this manual proc. │
                 └─────────────────────────┘
```

### Why `none` is also handled

A brand-new sandbox might have no IdP configured at all yet (only
`kubeadmin`/service-account access). `01-create-test-identity.sh` refuses
to add a new HTPasswd provider unless `ADD_HTPASSWD_IDP=yes` is explicitly
set, since that is itself a cluster-level auth configuration change, not
something to do silently as a side effect of a demo setup script.

## Takeaway for reproducibility on a new RHOAI sandbox

Running `scripts/demo2/00-detect-identity-provider.sh` first, before
anything else in Demo 2, is mandatory and is the first step in
[`docs/demo2/02-admin-runbook.md`](02-admin-runbook.md). It is read-only
and safe to run on any sandbox, including the partner's own, and tells
you immediately which of the three real paths above applies — instead of
this demo silently assuming its own development sandbox's Keycloak setup
is universal.
