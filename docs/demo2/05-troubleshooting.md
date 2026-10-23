# Demo 2 — Troubleshooting

Every entry below is a real error actually hit while building and
running this demo, with the real root cause and real fix — not a
hypothetical FAQ.

## "Login failed (401 Unauthorized)" when running `oc login -u maas-demo2-user -p ...`

**Cause:** this sandbox's only IdP is OIDC (in-cluster Keycloak), not
HTPasswd. `oc login -u/-p` performs a direct password grant against the
OpenShift OAuth server, which an OIDC/redirect-type provider does not
support — this is **expected**, not a bug.

**Fix:** use the real browser OAuth flow once to mint a CLI token:
1. Visit `https://oauth-openshift.<cluster-domain>/oauth/token/request`
2. Log in as the identity through the real login form (password read
   locally from `secrets/demo2/<user>.password`, never pasted into
   chat/logs).
3. Click "Display Token", then
   `KUBECONFIG=<path> oc login --token=<token> --server=<api-url> --insecure-skip-tls-verify=true`
4. `oc logout` immediately afterward to revoke the token.

See [`09-auth-oidc-entra.md`](09-auth-oidc-entra.md) for full detail;
this exact procedure was run once to verify the identity, then this
specific failure mode was no longer relevant for the rest of the demo
(API-key-based testing doesn't need `oc login` as the test user at all).

## `curl` to the MaaS gateway hangs or fails to resolve

**Cause:** on some sandboxes, the Gateway's LoadBalancer hostname (e.g.
an AWS ELB DNS name) has not yet propagated to the shell's resolver, or
the shell's `/etc/resolv.conf` doesn't point at a resolver that knows
about it yet.

**Fix:** resolve the Gateway's actual IP via `dig` and pass
`curl --resolve <maas-hostname>:443:<ip>`. Already implemented in every
inference/test script (`scripts/demo2/20-test-inference.sh`,
`40-test-negative.sh`) via the shared pattern:
```bash
GATEWAY_ADDR=$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}')
GATEWAY_IP=$(dig +short "$GATEWAY_ADDR" | head -1)
RESOLVE_OPT=(--resolve "$(maas_hostname):443:${GATEWAY_IP}")
```
This is also the fix reused from Demo 1's `scripts/infer.sh`.

## `POST /v1/chat/completions` returns `404` even though the model is `Ready`

**Real cause actually hit while building Scenario E's test script:** the
request body's `"model"` field used the short alias (`facebook/opt-125m`)
instead of the **full id** the gateway's body-based router actually
expects: `publishers/<namespace>/models/facebook/opt-125m` (exactly the
`id` field `GET /v1/models` returns). The short alias is silently
treated as "model not found" → `404`, even with full governance in place.

**Fix:** always resolve/use the full `id` string from `GET /v1/models`
(or hardcode the known pattern
`publishers/${DEMO2_MODEL_NAMESPACE}/models/facebook/opt-125m` when the
discovery call can't be made first, e.g. while deliberately testing a
Pending/ungoverned state).

## Negative-test script timing: `wait_for_phase` times out waiting for `Pending`

**Cause:** deleting the **subscription** a specific key is bound to does
**not** necessarily flip the model's overall `MaaSModelRef.status.phase`
to `Pending` — if another, unrelated subscription (e.g. the separate
rate-limit-test one) still pairs with the AuthPolicy, the model stays
`Ready` overall even though that one key's own access was revoked. This
looks like a timeout/bug at first but is actually the real, correct
governance behavior (see Scenario E Test 2's finding in
[`04-test-scenarios.md`](04-test-scenarios.md)).

**Fix:** don't assume a specific CR-level phase transition; check the
actual HTTP response the affected key gets instead — that's the
ground truth. `scripts/demo2/40-test-negative.sh`'s `wait_for_phase`
helper now treats a timeout as "continue anyway, you'll see from the
real HTTP status what actually happened" rather than failing the script.

## `python3 -c '...' <<'EOF' ... EOF` returns `Expecting value: line 1 column 1 (char 0)`

**Cause:** `python3 -` reads its own **program source** from stdin. A
heredoc (`<<'EOF'`) redirecting stdin for that same command **overrides**
any piped input (`oc get ... -o json | python3 - <<'EOF' ...`) — the
heredoc content becomes the Python program, and the piped JSON is
silently discarded, so `json.load(sys.stdin)` then has nothing to read.

**Fix:** write the Python script to a temporary file and run
`python3 /path/to/script.py` with the real data piped in separately, or
pass the script via `-c` instead of relying on stdin for the program
text. Fixed this way in `scripts/demo2/40-test-negative.sh`'s
`model_status_snapshot()`.

## A single `trap ... EXIT` silently replaces an earlier one

**Cause:** Bash only keeps the **last** `trap ... EXIT` registered for a
given signal in a script — setting a second one (e.g. one for temp-file
cleanup, another later for "restore governance objects") silently
discards the first.

**Fix:** combine all exit-time cleanup into one function
(`cleanup_on_exit() { restore_governance; rm -f "$TMPFILE"; }`) and
register that single function once.

## `AI asset endpoints` page shows "Unable to load models" even after creating a Project

**Cause (captured directly, not guessed):** the page's own backend call,
`GET /gen-ai/api/v1/maas/models?namespace=<selected-project>`, is scoped
to the **currently selected Project's namespace**, and requires RBAC to
list model-serving resources specifically in that namespace — which a
freshly self-provisioned Project's owner does not automatically have on
this installed Tech Preview version. Response captured directly:
```json
{"error": {"code": "403", "message": "user does not have permission to access services in this namespace"}}
```

**Fix / workaround:** none found that doesn't involve granting
additional RBAC in that namespace (out of scope for a non-admin demo
user). Use the "API keys" page (Scenario C) instead — it is subscription-
scoped, not Project-namespace-scoped, and is fully verified working.

## Revoked API key returns `403`, not the documented `401`

Not a bug in this project's scripts — a real, repeatable behavior of
this installed MaaS version. `scripts/demo2/30-verify-key-status.sh`
treats **both** `403` and `401` as "correctly revoked" for this reason.
See Scenario G in [`04-test-scenarios.md`](04-test-scenarios.md).

## The browser tab's clipboard is not bridged to the system clipboard

**Cause:** in this Cursor/Electron-on-Wayland environment,
`wl-copy`/`wl-paste` on the host do not see what gets copied inside the
embedded browser tab (confirmed empirically: `wl-paste` returned
unrelated chat text, not the copied API key).

**Fix / standing policy:** never rely on clipboard bridging for secret
capture. Any value shown exactly once in a browser dialog (API key
reveal) is captured with a **single** `Write` tool call directly from
the dialog's rendered value, immediately `chmod 600`'d, and never
re-typed into any subsequent Shell command.

## `Create API key`'s Subscription selector stays disabled

**Cause:** the user genuinely has zero subscriptions (Scenario A state).
This is correct, enforced UI behavior (`pointer-events: none`), not a
rendering bug.

**Fix:** none needed — this is the expected, verified behavior
documented in Scenario A.
