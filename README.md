# RHOAI 3.5 — Models-as-a-Service (MaaS) Demo

Reproducible **Models-as-a-Service** demo for OpenShift AI 3.5: gateway, Kuadrant,
Authorino, PostgreSQL, MaaS tenant, CPU simulator model, subscription, auth policy,
and rate-limit demos.

## Quick start

```bash
oc login <api-url> --token=<token>

git clone https://github.com/Lindagh1/rhoai-maas-demo.git
cd rhoai-maas-demo

make preflight    # read-only: is the cluster ready?
make bootstrap    # idempotent full install
make status       # readiness report
make validate     # end-to-end smoke test
make infer        # call the model via MaaS API (creates .env.local)
```

## Demo flow (~15 min)

See **[docs/DEMO_GUIDE.pdf](docs/DEMO_GUIDE.pdf)** (click-by-click) or
[docs/DEMO_GUIDE.md](docs/DEMO_GUIDE.md).

| Step | Command / UI | Story |
|---|---|---|
| Preflight | `make preflight` | Cluster healthy, MaaS prerequisites listed |
| Bootstrap | `make bootstrap` | Gateway + Kuadrant + MaaS + demo model |
| Inference | `make infer` | OpenAI-compatible `/v1/chat/completions` via gateway |
| Auth demo | `make demo-auth` | 403 without `MaaSAuthPolicy`, 200 when restored |
| Rate limit | `make demo-rate-limit` | Kuadrant / Limitador throttling |

## Architecture

- **Gateway** `maas-default-gateway` in `openshift-ingress`
- **Kuadrant + Authorino** for authn/authz at the gateway
- **MaaS** tenant `default-tenant`, subscription + auth policy
- **Demo model** `demo-simulator` (CPU, no extra GPU) in `rhoai-maas-demo`

## Safety

- Does **not** modify pre-existing GPU workloads in other namespaces
- `make bootstrap` is idempotent — safe to run twice
- `make cleanup` removes only demo-owned resources

## Docs

| File | Description |
|---|---|
| [docs/DEMO_GUIDE.md](docs/DEMO_GUIDE.md) | Presenter guide (UI + CLI) |
| [PREFLIGHT.md](PREFLIGHT.md) | Example preflight output |
| [BASELINE.md](BASELINE.md) | Cluster baseline snapshot |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues |

## Requirements

- OpenShift 4.x + RHOAI 3.5
- Cluster-admin (patches DSC, installs operators)
- No additional GPU required (CPU simulator)
