# Demo 2 — Source references

## Primary official documentation (as specified by the task)

- **Administrator documentation** — *Govern LLM access with Models-as-a-Service: Deploy and manage Models-as-a-Service* (RHOAI 3.5):
  <https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service>
  — used for Scenario B (`MaaSSubscription`/`MaaSAuthPolicy` creation,
  the dashboard "Create a matching authorization policy" checkbox, the
  documented 90-day max key expiration), and the general MaaS
  architecture (Gateway, tenant config).

- **End-user documentation** — *Govern LLM access with Models-as-a-Service: Use Models-as-a-Service* (RHOAI 3.5):
  <https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/use-models-as-a-service_maas-deploy>
  — used for Scenarios A, C, D, E, F, G (dashboard flows, API key
  creation/revocation, `/v1/models` and `/v1/chat/completions` usage,
  documented HTTP status expectations). Sections 1.14–1.19 and 2.1–2.3
  were given particular attention per the task's instruction, covering
  subscription/API-key management and real inference calls.

  **Where this project's verified, live results differ from these
  docs** (recorded as findings, not corrections to the docs themselves):
  - Scenario A's exact UI wording (`"Request a subscription"` /
    `"No API keys"` / `"No subscriptions available"`) rather than a
    generic `"No subscriptions"`.
  - Scenario E Test 2 and Scenario G: a missing-subscription/revoked-key
    rejection returns `403`, not the implied/documented `429`/`401`.
  - Scenario C's "AI asset endpoints" temporary-key flow returning a
    real `403` for a self-provisioned Project owner.

  See [`04-test-scenarios.md`](04-test-scenarios.md) for the full
  expected-vs-actual matrix.

## CRD schemas and cluster behavior

All Kubernetes field names, types, and required/optional structure for
`MaaSSubscription`, `MaaSAuthPolicy`, `MaaSModelRef`, and `MaasTenantConfig`
were taken **directly from the live cluster's installed CRDs**
(`oc get crd <name> -o yaml`, `openAPIV3Schema`), never copied from
older RHOAI release documentation or assumed from memory — per the
task's explicit instruction. See
[`01-environment-audit.md`](01-environment-audit.md) for the schema
excerpts actually inspected, and every manifest under
[`manifests/demo2/`](../../manifests/demo2/) for the resulting,
server-side-dry-run-validated resources.

## Kuadrant / Limitador (rate limiting, observability)

- Kuadrant project (upstream of the `AuthPolicy`/`RateLimitPolicy`/
  `Limitador` machinery MaaS builds on): <https://kuadrant.io/>
- Limitador's own Prometheus metrics (`authorized_calls`,
  `limited_calls`, `authorized_hits`, `limitador_up`) were read
  **directly from the running pod** (`oc port-forward svc/limitador-limitador 18080:8080`,
  `curl /metrics`) on this cluster, not from Kuadrant's own
  documentation — see
  [`04-test-scenarios.md`](04-test-scenarios.md) Scenario F and
  `evidence/demo2/scenario-f-01-admin-limitador-metrics.txt`.

## This repository's own prior work (reused, not rebuilt)

- Demo 1's runbook, manifests, and scripts (`docs/demo1-runbook.md`,
  `scripts/00-audit.sh` through `scripts/99-cleanup.sh`,
  `scripts/infer.sh`) — the native `LLMInferenceService` → `MaaSModelRef`
  publication Demo 2 builds its access-control layer on top of, exactly
  as the task instructed ("reuse its model, infrastructure, scripts,
  manifests and documented configuration").
- Demo 1's `--resolve`-based Gateway DNS workaround
  (`scripts/infer.sh`), reused verbatim in
  `scripts/demo2/20-test-inference.sh` and `40-test-negative.sh`.
- `docs/sandbox-audit.md` / `docs/BASELINE.md` — the sandbox's general
  cluster facts (version, GPU availability, etc.) this Demo 2 audit
  extends rather than re-discovers from scratch.

## OpenID Connect / OpenShift OAuth references

- OpenShift documentation on configuring an OpenID identity provider
  (used to interpret this sandbox's own `oauth/cluster`
  `identityProviders[].openID` spec, not to configure a new one):
  <https://docs.openshift.com/container-platform/latest/authentication/identity_providers/configuring-oidc-identity-provider.html>
- Red Hat Build of Keycloak (RHBK) — the specific in-cluster OIDC
  provider this sandbox happens to run; inspected live via its own
  Admin REST API (`/admin/realms/<realm>/...`), not via external docs,
  since the exact realm/client configuration is sandbox-specific.

## Explicitly NOT used as a source

- No older (pre-3.5) RHOAI release's MaaS documentation or example
  manifests were copied — every manifest here was validated with
  `oc apply --dry-run=server` against this cluster's actual installed
  CRDs before being treated as correct.
- No mock/simulated LLM backend was substituted for Demo 1's real
  native model at any point in any scenario.
