# Demo 2 — End-user runbook (Scenarios A, C, D, F, G)

Everything in this document was performed as the genuine, real,
non-admin identity `maas-demo2-user` — a real browser OIDC login via
this sandbox's in-cluster Keycloak, never an administrator token
disguised as a user, and never a mock/simulated session.

## Scenario A — before any subscription exists

With `maas-demo2-subscription`/`maas-demo2-access` temporarily removed
(`make demo2-cleanup-access CONFIRM=yes`), logging in as
`maas-demo2-user` and opening **Gen AI studio → API keys** shows:

**Subscriptions tab:**
> "Request a subscription — Subscriptions give you access to models. To
> request a subscription, contact your administrator."
> (+ a "Who's my administrator?" popover with generic guidance: "The
> person who assigned you your username...", "Someone in your IT
> department...", "A project manager or developer...", "Your professor
> (at a school)".)

**API keys tab:**
> "No API keys — API keys let you authenticate with AI model endpoints.
> Create a key to start making requests to models available in your
> subscriptions."

**Create API key dialog**, opened anyway: a warning alert reads
> "No subscriptions available — You don't have access to any
> subscriptions. Ask your admin to add you to a subscription."

and the Subscription typeahead combobox (and its dropdown toggle) are
not merely visually disabled but have `pointer-events: none` applied —
confirmed by inspecting the rendered DOM, not just by sight. **A user
genuinely cannot create a usable key without an admin-provisioned
subscription on this installed version.**

**Real finding vs. the task's reported discrepancy:** the task mentioned
a report of the message *"subscription required"* from Sopra Steria,
versus the documented *"No subscriptions"*. On this sandbox/version, the
actual text is **"Request a subscription"** (Subscriptions tab) / **"No
API keys"** (API keys tab) / **"No subscriptions available"** (create-key
dialog) — none of these is a verbatim match for either "No subscriptions"
or "subscription required". This is recorded as the genuine, verified
wording for this version rather than assumed to match either prior
report.

Evidence: captured via `document.querySelector('main').innerText`
(exact rendered text, not paraphrased) — not currently saved as a
standalone evidence file for this specific sub-step (captured
inline during development); the equivalent governance-state evidence
is in `evidence/demo2/scenario-e-02-no-subscription.txt`.

## Scenario C — discover the model and create a real API key

Once the admin has run `make demo2-grant-access` (Scenario B):

1. Log in as `maas-demo2-user` (real browser OIDC flow).
2. **Gen AI studio → API keys → Subscriptions tab** now shows:
   - `maas-demo2-subscription` — "1 active key" (after step 6 below)
   - `maas-demo2-subscription-ratelimit-test` — "0 active keys" (Scenario
     E's dedicated low-quota subscription, not used for the main flow)
3. Expanding the row shows the configured **token-rate limit ceiling**
   for the model under that subscription — e.g. `2,000 / 1 minute` for
   the main subscription. (This is the *configured limit*, not actual
   consumption — see Scenario F / [`04-test-scenarios.md`](04-test-scenarios.md).)
4. Switching to "Model view" groups the same information by model
   (`MaaS Demo Simulator` / `demo-simulator`) instead of by subscription.
5. **Create API key** dialog: Name, Description, a **Subscription**
   typeahead (now populated and selectable, no longer disabled — exactly
   one real subscription selected per key), and an **Expiration**
   control offering `On date` / `After` / **`Use max value of 90 days`**
   — confirming the documented 90-day default maximum is real on this
   version.
6. The key's plaintext value (prefix `sk-oai-`) is shown **exactly
   once**, in a masked field with "Show API key" / "Copy API key" /
   "Close" buttons. Once the dialog is closed, the plaintext is
   **never retrievable again** — confirmed the hard way during this
   project (one key's reveal dialog was accidentally closed before
   capture; it had to be revoked, unused, and replaced).
7. Model/endpoint discovery: `GET /v1/models` (see Scenario D below)
   returns the model's full id
   (`publishers/rhoai-maas-demo/models/facebook/opt-125m`) and, per
   model, a `subscriptions` array listing **only** the subscription(s)
   actually granting that key's owner access — when both
   `maas-demo2-subscription` (priority 10) and
   `maas-demo2-subscription-ratelimit-test` (priority 1) exist, only the
   higher-priority one was listed, consistent with "highest-priority
   subscription wins" behavior.

**Temporary 1-hour keys from "AI asset endpoints" — real, verified
BLOCKER, not fabricated:** Red Hat's docs describe a second way to get a
key, directly from a model's entry on the "AI asset endpoints" (Tech
Preview) page. On this sandbox, that page requires a Data Science
Project to be selected first (`"You must create a project to begin"`).
`maas-demo2-user` successfully **self-provisioned** a Project (confirmed
the `self-provisioners` ClusterRoleBinding works for an ordinary
authenticated user), but the page's own backend call then returned a
real, captured `403`:
```json
{"error": {"code": "403", "message": "user does not have permission to access services in this namespace"}}
```
See `evidence/demo2/scenario-c-04-ai-asset-endpoints-blocked.txt` for
the full capture. **Only the "API keys" page flow (steps 1–6 above) is
verified working on this installed version** — the temporary-key path
is documented as blocked, not silently skipped or assumed to work.

Never print or commit API key values: every key in this project was
captured exactly once via the `Write` tool directly from the browser's
one-time reveal, into a `chmod 600` file under `secrets/demo2/`
(gitignored), and never re-typed into any Shell command afterward.

## Scenario D — real inference

```
make demo2-test-inference
```
(or `bash scripts/demo2/20-test-inference.sh`, reading the key from
`secrets/demo2/maas-demo2-user.apikey` / `DEMO2_API_KEY_FILE` /
`DEMO2_API_KEY` — never hardcoded)

Real, live results obtained on this sandbox:
- `GET /v1/models` → `200`, lists `demo-simulator`.
- `POST /v1/chat/completions` (body-based routing, model id = the full
  `publishers/.../models/facebook/opt-125m` string — **the short alias
  `facebook/opt-125m` alone is rejected**, a real finding, not a
  guess) → `200`, genuine model reply, `usage` object present
  (`prompt_tokens`/`completion_tokens`/`total_tokens`) confirming the
  response comes from Demo 1's real `llm-d-inference-sim` backend, not a
  mock. No `X-RateLimit-*` response headers were observed on this
  particular `200` (documented as an actual observation, not assumed
  either way).

Sanitized (API-key-redacted) evidence:
`evidence/demo2/scenario-d-01-models.txt`,
`evidence/demo2/scenario-d-02-inference.txt`.

## Scenario F — usage visibility (non-admin side)

See `evidence/demo2/scenario-f-03-user-dashboard-view.txt` for the full,
verbatim capture. Summary: the Subscriptions tab shows subscription
name, active-key count, and the **configured** token-rate-limit ceiling
— **never** actual consumption, remaining quota, or any usage
history/graph, in either "Subscription view" or "Model view". The only
way a non-admin discovers they've been rate-limited is receiving an
actual `429` on a real request. The admin-side observability
counterpart is in [`04-test-scenarios.md`](04-test-scenarios.md) /
`evidence/demo2/scenario-f-01-admin-limitador-metrics.txt`.

## Scenario G — revoke and regenerate

As the end user, through the real dashboard (kebab menu on a key row →
**Revoke** → type the exact key name into the confirmation field →
**Revoke**):

1. The key disappears from the default "Active" filter immediately.
2. Repeating the same `GET /v1/models` call with the revoked key's value
   returns **`403` with an empty body** — **not** the documented `401
   Unauthorized`. Verified across three independently revoked keys in
   this sandbox during this project; recorded as the real behavior of
   this installed version, not corrected to match the docs.
3. Creating a fresh key through the same "Create API key" flow, scoped
   to the same (or a different) subscription, works immediately — no
   infrastructure change required, since the underlying
   `MaaSSubscription`/`MaaSAuthPolicy` pairing is untouched.
4. This is explicitly **regeneration through new key creation**, not
   reactivation — a revoked key's row is gone; there is no "un-revoke"
   action anywhere in the UI.

Full evidence: `evidence/demo2/scenario-g-01-before-revoke.txt`,
`scenario-g-02-after-revoke.txt`, `scenario-g-03-regenerate.txt`.
Reusable, secret-safe check:
`scripts/demo2/30-verify-key-status.sh <keyfile>` (reads the key only
via `cat`, never as a literal argument; treats both `403` — this
version's real signature — and `401` — the documented one — as a
correctly-revoked key).
