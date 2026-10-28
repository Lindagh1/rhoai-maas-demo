# vendor/

Third-party repositories vendored (copied, not submoduled) into this repo so
that the exact version used for a deployment is committed and reproducible on
a brand new sandbox, independent of upstream changes.

## rhoai-maas-guide

Source: https://github.com/rh-aiservices-bu/rhoai-maas-guide
Vendored commit: `ca26a4561673c05a19cd1be5e2eb7663cdb8b17d` (2026-10-22)
Guide site: https://rh-aiservices-bu.github.io/rhoai-maas-guide/

This is the official Red Hat AI Services BU companion guide for RHOAI
Models-as-a-Service (MaaS), used here to install MaaS end-to-end
(`scripts/setup-maas.sh`) and to run the "Corporate Scenario" demo
(`demo/corporate-scenario/`).

Local patches on top of the vendored upstream commit are tracked in
[`PATCHES.md`](rhoai-maas-guide/PATCHES.md) — keep that file in sync with any
edit made directly in this vendored copy so a future re-vendor from upstream
can replay them.
