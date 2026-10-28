# Local patches on top of vendored upstream

Vendored from https://github.com/rh-aiservices-bu/rhoai-maas-guide
at commit `ca26a4561673c05a19cd1be5e2eb7663cdb8b17d`.

Every edit made directly inside this vendored copy must be listed here so a
future re-vendor from a newer upstream commit can replay (or re-check the
relevance of) each one.

| File | Change | Reason |
|---|---|---|
| `scripts/setup-maas.sh` | `POSTGRES_PASSWORD` generation falls back to `python3 -c "import secrets; ..."` when `openssl` is not on `PATH` | The agent/runner host for this sandbox has no `openssl` binary and no passwordless `sudo` to install one. Purely a local-tooling compatibility fix — does not change cluster-side behavior. |
| `scripts/setup-maas.sh` Phase 0 + Phase 4 gate | Preflight's "is MaaS already Managed?" check now also requires `.spec.components.aigateway.managementState == Managed` (parent), not just the nested `.spec.components.aigateway.modelsAsAService.managementState`. | **Real cluster-side bug found on this sandbox** (`mqgbd.sandbox840`), not a local-tooling issue — see root-cause writeup below. |

## Cluster-side bug: Phase 0 preflight false-positive on `aigateway` parent `managementState: Removed`

**Symptom:** On a fresh sandbox with RHOAI 3.5.2 pre-provisioned by the
OpenTLC catalog, the pre-existing `DataScienceCluster/default-dsc` already
had:

```yaml
spec:
  components:
    aigateway:
      managementState: Removed          # parent: Removed
      modelsAsAService:
        managementState: Managed        # nested: Managed
    llamastackoperator:
      managementState: Managed          # guide wants: Removed
    ogx:
      managementState: Removed          # guide wants: Managed
```

`setup-maas.sh`'s Phase 0 preflight only reads the **nested**
`aigateway.modelsAsAService.managementState` field to decide
`HAS_MAAS_MANAGED`. Since that nested field was already `Managed` on this
sandbox (but the parent `aigateway` component was `Removed`), the script
logged `modelsAsService: Managed` and later `DSC already has MaaS: Managed,
skipping` in Phase 4 — so it never applied
`manifests/04-rhoai-config/datasciencecluster.yaml`, which is the only place
that also flips `llamastackoperator` to `Removed` and `ogx`/`aigateway`
(parent) to `Managed`.

Net effect: Phase 5 (deploy model) still worked — KServe/LLMInferenceService
doesn't need `aigateway` — so the `facebook-opt-125m-simulated` model came
up `Ready` and looked like a success. But `maas-api` never deployed, no
`maas*.opendatahub.io` CRDs were ever registered
(`maasmodelref`/`maassubscription`/`maasauthpolicy` all `NotFound`), and
`AIGatewayReady`/`ModelsAsAServiceReady` stayed `False (Removed)` the whole
time. Running Phase 6 verification against this state fails outright (no
`maas-api`, no CRDs).

**Root cause (per the guide manifest's own in-line comment, confirmed live
on this cluster):** `llamastackoperator: Managed` is deprecated and, left
`Managed`, aborts the whole module-provisioning batch at runlevel 32 —
which blocks `aigateway` and `mlflowoperator` from ever installing their
CRDs, regardless of what `modelsAsAService.managementState` says. This
sandbox's pre-provisioned DSC had `llamastackoperator: Managed`, so
`aigateway` was permanently stuck even though someone/something had already
flipped the nested MaaS flag.

**Fix applied to the live cluster (targeted merge patch, not a full
`datasciencecluster.yaml` apply, to avoid touching unrelated pre-provisioned
components like `trainer`/`kueue` on this shared sandbox):**

```bash
oc patch datasciencecluster default-dsc --type=merge -p '{
  "spec": {
    "components": {
      "aigateway": {"managementState": "Managed", "modelsAsAService": {"managementState": "Managed"}},
      "llamastackoperator": {"managementState": "Removed"},
      "ogx": {"managementState": "Managed"},
      "mlflowoperator": {"managementState": "Managed"}
    }
  }
}'
```

**Fix applied to this vendored script:** Phase 0 and the Phase 4 gate now
also check the parent `aigateway.managementState`, so a future run (or a
different sandbox with the same pre-provisioned drift) re-applies Phase 4
instead of silently skipping it. See the diff in `scripts/setup-maas.sh`.
