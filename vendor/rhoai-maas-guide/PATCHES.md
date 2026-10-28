# Local patches on top of vendored upstream

Vendored from https://github.com/rh-aiservices-bu/rhoai-maas-guide
at commit `ca26a4561673c05a19cd1be5e2eb7663cdb8b17d`.

Every edit made directly inside this vendored copy must be listed here so a
future re-vendor from a newer upstream commit can replay (or re-check the
relevance of) each one.

| File | Change | Reason |
|---|---|---|
| `scripts/setup-maas.sh` | `POSTGRES_PASSWORD` generation falls back to `python3 -c "import secrets; ..."` when `openssl` is not on `PATH` | The agent/runner host for this sandbox has no `openssl` binary and no passwordless `sudo` to install one. Purely a local-tooling compatibility fix — does not change cluster-side behavior. |
