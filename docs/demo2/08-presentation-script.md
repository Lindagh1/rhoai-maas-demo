# Demo 2 — Presentation script (10–12 minutes)

Audience: Sopra Steria stakeholders evaluating Models-as-a-Service
governance on RHOAI 3.5. Two roles are shown throughout, explicitly
labeled so the audience never confuses admin actions with genuine
non-admin end-user actions. Every output shown live is real (no mocked
responses, no fabricated screenshots) — this script only narrates what
has already been verified in [`04-test-scenarios.md`](04-test-scenarios.md).

**Setup before the room:** `make demo2-verify` passing, both API key
files present in `secrets/demo2/`, two browser profiles/sessions ready
(or one browser + re-login) for admin vs. `maas-demo2-user`.

---

### 0:00–1:00 — Framing (narration only, no screen action yet)

> "Demo 1 showed a native model served and published through MaaS. Demo
> 2 answers the next question every platform team asks: once a model is
> published, how do you actually *govern* who can call it, with what
> limits, and how does that look from both sides — the administrator
> granting access, and the real end-user consuming it? Everything you'll
> see today is live against a real OpenShift AI 3.5 sandbox and a real,
> non-admin OpenShift identity — no mocked responses."

---

### 1:00–2:30 — [END USER] Before any access is granted

**Action:** log in to the RHOAI dashboard as `maas-demo2-user`. Navigate
to **Gen AI studio → API keys**.

**Show:** Subscriptions tab — *"Request a subscription... contact your
administrator."* API keys tab — *"No API keys."* Open "Create API key"
anyway — *"No subscriptions available"* warning, and point out the
Subscription selector is genuinely disabled (not just dimmed).

> "This is a real non-admin user with zero access configured. Note the
> exact wording — we verified this precisely because a customer had
> reported slightly different UI text than the official docs describe,
> and reproducing the *actual* behavior mattered more than assuming the
> docs were right."

---

### 2:30–4:30 — [ADMIN] Grant access, declaratively

**Action:** switch to a terminal. Run:
```
make demo2-grant-access
```

**Show:** the command's own output — server-side dry-run validation
against the live CRDs, then the two `MaaSSubscription` objects and the
`MaaSAuthPolicy` applying cleanly, then `MaaSModelRef` flipping to
`Ready`.

> "This is the GitOps-friendly path: three small, clearly-named
> manifests — one subscription granting a demo group access with a
> defined token-rate limit, a second, deliberately tiny subscription
> we'll use later for a controlled rate-limit test, and the matching
> authorization policy. Everything is scoped to this demo's own group
> and model — it cannot accidentally grant access to anything else on
> the sandbox, and it's idempotent: running it again changes nothing."

(Mention, briefly, without dwelling: *"The dashboard also offers a
'create a matching authorization policy' checkbox to do this in one UI
step — we're showing the declarative path live here since it's the one
fully verified end-to-end on this sandbox."*)

---

### 4:30–6:30 — [END USER] Discover the model, create a real API key

**Action:** switch back to `maas-demo2-user`'s browser session, reload
the Subscriptions tab.

**Show:** the subscription now appears, with the configured token-rate
limit visible on expand. Open "Create API key", select the subscription,
show the 90-day-max expiration option, create the key, reveal it once.

> "This user now sees exactly one subscription, with the limit the admin
> configured a minute ago. Creating a key scopes it to that subscription
> specifically — and the key's value is shown exactly once. If we close
> this dialog without copying it, it's gone for good; we'd have to
> revoke and create a new one. That's a deliberate security property,
> not a bug — we'll actually demonstrate that exact revoke/regenerate
> flow later."

---

### 6:30–8:00 — [END USER via script] Real inference

**Action:** terminal:
```
make demo2-test-inference
```

**Show:** `GET /v1/models` → `200`, the model's full id. `POST /v1/chat/completions`
→ `200`, a genuine reply and a token-usage object.

> "This is a real OpenAI-compatible call against the exact same native
> model Demo 1 deployed — using the end-user's own key, not an admin
> token. The usage numbers you see are real token counts from this
> request, not a canned example."

---

### 8:00–9:30 — [AUTOMATED] Negative tests — what happens when governance is wrong

**Action:** terminal:
```
make demo2-test-negative
```

**Show (narrate while it runs, ~90 seconds):** it temporarily removes
the authorization policy → real `403`; temporarily removes the
specific subscription that key belongs to → real `403` with
`"requested subscription not found"` in the body; then sends a small,
bounded sequence of requests against a dedicated, tiny 50-token quota →
real `429` after the quota is exhausted. Everything is restored
automatically at the end.

> "Three real negative scenarios, each triggering the actual governance
> layer — not simulated status codes. Notice the last one: we
> deliberately created a second, tiny, isolated subscription just for
> this test, so this never touches any other user's quota on this
> sandbox."

---

### 9:30–10:30 — [ADMIN] Usage visibility — what you can and can't see

**Action:** terminal:
```
make demo2-check-usage
```

**Show:** Limitador's own Prometheus counters —
`authorized_calls`/`limited_calls` matching the exact numbers from the
test that just ran.

> "This is Kuadrant/Limitador's real metrics endpoint, already wired
> into this platform's own monitoring — not something we built for this
> demo. One honest limitation worth calling out: these counters are
> per-model, not per-user. If you need per-subscriber billing or
> showback, that's a gap today, not a feature we're hiding."

(If time allows, flip back to the end-user's Subscriptions tab one more
time: *"And from the user's side — they see their configured limit, but
never their actual remaining quota. The only signal they get is an
actual 429 if they go over."*)

---

### 10:30–11:30 — [END USER] Revoke and regenerate

**Action:** dashboard, kebab menu on a key → Revoke → type the exact key
name to confirm.

**Show:** the key disappears from Active; re-run the same `GET /v1/models`
call with that now-dead key — a real rejection (this sandbox returns
`403`, not the `401` the docs describe — call this out explicitly as a
genuine finding). Create a fresh key, verify it works immediately.

> "Revocation here is real and immediate, confirmed by actually
> re-using the dead key and getting rejected. And to be precise with
> you: our testing found this installed version returns 403 here, not
> the 401 the official docs describe — we're telling you the real
> behavior we measured, not the documented one."

---

### 11:30–12:00 — Close

> "Everything you saw was a real non-admin OpenShift identity, a real
> native model from Demo 1, and real HTTP responses — including the
> couple of places where reality didn't quite match the documentation,
> because that's exactly the kind of thing worth knowing before you
> build on this platform. Full write-up, every scenario's pass/fail
> status, and the exact commands to reproduce all of this on your own
> sandbox are in the repo — `DEMO2-RESULTS.md` and `docs/demo2/`."

---

## If something doesn't cooperate live

- `make demo2-verify` first, off-stage, to confirm the baseline state
  before the room starts.
- If a key file is missing/stale: re-run Scenario C's dashboard flow
  live (it's short) rather than skipping Scenario D.
- If `demo2-test-negative` looks stuck: it always restores on exit,
  including on Ctrl-C, so worst case is re-running `make demo2-verify`
  and moving on.
- Full troubleshooting list: [`05-troubleshooting.md`](05-troubleshooting.md).
