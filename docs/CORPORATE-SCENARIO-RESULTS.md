# Corporate Scenario (official `rhoai-maas-guide`) — results on this sandbox

Sandbox: `api.ocp.mqgbd.sandbox840.opentlc.com` (RHOAI 3.5.2, single-node
OpenShift on AWS). This is a **separate track** from this repo's own
Demo 1/Demo 2 (see root [`README.md`](../README.md)) — it follows the
official [rh-aiservices-bu/rhoai-maas-guide](https://github.com/rh-aiservices-bu/rhoai-maas-guide)
end-to-end: its own `scripts/setup-maas.sh` (Phases 0-6) to install MaaS,
then its `demo/corporate-scenario/` ("CIO rolls out MaaS across three
divisions") as **the demo**.

The guide is vendored (copied, not submoduled) into
[`vendor/rhoai-maas-guide/`](../vendor/rhoai-maas-guide/) at upstream
commit `ca26a4561673c05a19cd1be5e2eb7663cdb8b17d`, so it's reproducible on
a future sandbox without depending on upstream staying unchanged. Every
local edit on top of that commit — real cluster-side bugs found and
fixed, plus one documented environment characteristic — is tracked in
[`vendor/rhoai-maas-guide/PATCHES.md`](../vendor/rhoai-maas-guide/PATCHES.md).

## Reproduce on a new sandbox

```bash
oc login --server=<API> --token=<TOKEN>
git clone <this repo> && cd rhoai-maas-demo

# Phases 0-6: operators, platform config, MaaS platform, RHOAI config,
# deploy+verify the simulator model. Idempotent - safe to re-run.
bash vendor/rhoai-maas-guide/scripts/setup-maas.sh --model simulator

# Persist the base model's governance (setup-maas.sh Phase 5 only
# re-applies this if no LLMInferenceService exists yet - on a sandbox
# where the model is already deployed from a previous partial run,
# apply it explicitly):
oc apply -k vendor/rhoai-maas-guide/manifests/05-maas-models/simulator/maas/

# Corporate scenario demo (3 divisions, differentiated access + quotas):
cd vendor/rhoai-maas-guide/demo/corporate-scenario
DEMO_PASSWORD='<pick one>' ./setup-demo.sh
DEMO_PASSWORD='<same>'     ./run-demo.sh
DEMO_PASSWORD='<same>'     ./verify-scenario.sh
```

Tear down just the corporate-scenario additions (keeps the base MaaS
install and the general-purpose model):

```bash
cd vendor/rhoai-maas-guide/demo/corporate-scenario && ./cleanup-demo.sh
```

## What was actually found and fixed on this sandbox

Full root-cause writeups for all of these are in
[`vendor/rhoai-maas-guide/PATCHES.md`](../vendor/rhoai-maas-guide/PATCHES.md).
Summary:

| # | Finding | Severity | Fix |
|---|---|---|---|
| 1 | Local runner had no `openssl` on `PATH` (no passwordless `sudo` to install it) | local tooling | `setup-maas.sh` falls back to `python3 -c "import secrets; ..."` |
| 2 | **Real bug:** Phase 0/4 preflight only checked the nested `aigateway.modelsAsAService.managementState`, missed the parent `aigateway.managementState: Removed` left over from this sandbox's pre-provisioned DSC (compounded by `llamastackoperator: Managed`, which the guide's own manifest comment says blocks the whole runlevel-32 module batch) — so Phase 4 was silently skipped and `maas-api`/all `maas.opendatahub.io` CRDs never appeared | **high** (MaaS never actually turns on) | Targeted `oc patch` on the live DSC; preflight now checks both fields |
| 3 | **Real bug:** `maas-api` crash-looped — "expected 1 gateway service... found 2" — because this sandbox's pre-existing `Gateway/maas-default-gateway` (under a different, pre-existing GatewayClass) got re-pointed at the guide's own GatewayClass, and the old per-class Service was never garbage-collected | **high** | Deleted the orphaned Service (verified same owner/selector/endpoints as the live one), restarted `maas-api` |
| 4 | **Real bug, high severity:** `verify.sh`'s cleanup deleted the entire shared `models-as-a-service` tenant namespace (it only checked for leftover `maassubscription`/`maasauthpolicy`, not the `Tenant`/`MaasTenantConfig` it doesn't own) — took down `maas-api` and the whole platform for ~30-45s until the operator self-healed | **high** (briefly took down the platform) | Removed the "delete namespace" branch entirely from `verify.sh`'s cleanup |
| 5 | Environment characteristic (not a MaaS bug): this is a **single-node** sandbox; isolated connections to the Gateway/NLB drop at roughly 1-in-15-20 under light load and up to ~30% under rapid-fire bursts, reproduced on a trivial unauthenticated `GET /maas-api/health` with zero MaaS logic involved | environmental | Added bounded (3-attempt), narrowly-scoped retries — only on literal `000`/`500`/empty-body, never on a real HTTP status — to `verify.sh` Phase 4, `run-demo.sh`, and `verify-scenario.sh` |

## Base install (Phases 0-6) — final state

- RHOAI 3.5.2, `aigateway`/`modelsAsAService`: `Managed`, `AIGatewayReady=True`, `ModelsAsAServiceReady=True`
- `maas-api` (1/1 Running, `redhat-ai-gateway-infra`), PostgreSQL, Gateway `maas-default-gateway` Programmed
- `facebook-opt-125m-simulated` (`llm` ns): `MaaSModelRef` Ready, `MaaSAuthPolicy/simulator-access` Active, `MaaSSubscription/simulator-free`+`simulator-premium` Active
- `manifests/06-verification/verify.sh`: **14/15** passed (post-fix runs) — the one miss each run was an isolated `HTTP 000` on a different, unrelated check each time (never the same check twice), consistent with finding #5 above, not a governance defect

## Corporate scenario — final state

- 6 htpasswd users (`sales-1/2`, `eng-1/2`, `prod-1/2`), 3 groups (`corp-sales`, `corp-engineering`, `corp-products`), IDP `corp-demo` added additively alongside the sandbox's existing `rhbk` OIDC provider
- 2 new models: `deepseek-r2-llmd` (`llm` ns), `gemini-flash-cloud` (`cloud-models` ns) — both `MaaSModelRef` Ready
- 3 subscriptions (`corp-sales`/`corp-engineering`/`corp-products`, priority 30, Active) + 2 auth policies (`corp-deepseek-access`, `corp-cloud-access`, Active)
- `./run-demo.sh`: full division-level access matrix confirmed correct across multiple runs (sales-1 sees 1 model, denied on 2; eng-1 sees all 3, hits rate-limit on the cloud model; prod-1 sees 2, denied on cloud) — remaining per-request noise in "other" counts is the documented connection-drop characteristic, not wrong governance
- `./verify-scenario.sh`: **14/15 passed, twice in a row** (run 1: miss on `sales-1 -> facebook-opt-125m-simulated`; run 2: miss on `sales-1 -> deepseek-r2-llmd` — two different, unrelated checks, both a bare `000`). Every access-control decision, the rate-limit test, the key-multiplication test, and all 4 config-drift checks passed both times.

## Secrets

`DEMO_PASSWORD` for the 6 corporate-scenario users is generated locally
and kept at `secrets/corporate-scenario/demo-password.txt` (gitignored,
never committed, never printed to a log or chat). The admin cluster token
used to log in to this sandbox was shared in plaintext in chat by the
user at the start of this session — treat it as compromised and rotate
it; it also appeared once in a local-debugging `curl -v` command the
agent ran against the cluster (never persisted anywhere, but visible in
that one tool-call's console output).
