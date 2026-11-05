#!/usr/bin/env bash
# Single entry point to redeploy the full MaaS demo kit
# (Publier native publication + observability + Gouverner end-user journey
# governance) on a brand-new RHOAI 3.5 sandbox.
#
# This script is a thin, ordered orchestration layer over the already
# existing, independently idempotent scripts in this repo -- it does not
# duplicate their logic. Every step it calls is itself safe to re-run.
#
# What this script does NOT do, by design (see GUIDE.md sections 4 et 6):
#   - It does not create the end-user's API keys (Scenario C) -- that is a
#     genuine non-admin dashboard action, which is exactly the point of the
#     demo. API-based key creation is also possible with the user identity.
#   - It does not create a Workbench (Notebook) from scratch -- RHOAI's
#     dashboard-managed Notebook wiring (image, PVC, kube-rbac-proxy
#     sidecar, ServiceAccount, HTTPRoute) was never verified end-to-end
#     from raw YAML in this project; only patching an already-dashboard-
#     created Notebook was (scripts/govern/22-wire-workbench.sh).
#   - It never commits or pushes anything to Git.
#   - It never prints or stores secret values anywhere but the local,
#     gitignored secrets/ directory.
#
# Usage:
#   bash scripts/bootstrap.sh                 # everything
#   bash scripts/bootstrap.sh --publish-only   # Publier + observability only
#   bash scripts/bootstrap.sh --govern-only    # Gouverner only (Publier must already be done)
#   bash scripts/bootstrap.sh --skip-observability
#
# Prerequisites: `oc login` as a cluster-admin on the TARGET sandbox,
# already run manually, outside of this script (never pass tokens as
# arguments or paste them into chat/logs).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

RUN_DEMO1=1
RUN_DEMO2=1
RUN_OBSERVABILITY=1

for arg in "$@"; do
  case "$arg" in
    --publish-only) RUN_DEMO2=0 ;;
    --govern-only) RUN_DEMO1=0 ;;
    --skip-observability) RUN_OBSERVABILITY=0 ;;
    *) err "Unknown argument: $arg"; exit 2 ;;
  esac
done

require_login
assert_sandbox

echo "=============================================="
echo "MaaS demo kit — full redeployment"
echo "=============================================="
info "Target cluster: $(oc whoami --show-server)"
info "Steps: publish=${RUN_DEMO1} observability=${RUN_OBSERVABILITY} govern=${RUN_DEMO2}"
echo

run_step() {
  local label="$1"; shift
  echo "---------------------------------------------"
  info "STEP: $label"
  echo "---------------------------------------------"
  if "$@"; then
    ok "$label — done"
  else
    err "$label — FAILED. Stopping here (fix the error above, then re-run this same script; every step is idempotent)."
    exit 1
  fi
  echo
}

if [[ "$RUN_DEMO1" == "1" ]]; then
  run_step "Publier — read-only audit"            bash scripts/publish/00-audit.sh
  run_step "Publier — prerequisites"              bash scripts/publish/10-prerequisites.sh
  run_step "Publier — enable MaaS"                bash scripts/publish/20-enable-platform.sh
  if [[ "$RUN_OBSERVABILITY" == "1" ]]; then
    run_step "Publier — enable observability"     bash scripts/publish/25-observability.sh
  else
    warn "Skipping observability step (--skip-observability) — Observe & Monitor tabs will not be enabled."
  fi
  run_step "Publier — deploy native model"        bash scripts/publish/30-deploy-llm.sh
  run_step "Publier — publish to MaaS"            bash scripts/publish/40-publish.sh
  run_step "Publier — verify (1st pass)"          bash scripts/publish/50-verify.sh
fi

if [[ "$RUN_DEMO2" == "1" ]]; then
  run_step "Gouverner — detect identity provider"   bash scripts/govern/00-detect-login.sh
  run_step "Gouverner — create test identity"       bash scripts/govern/01-create-user.sh
  run_step "Gouverner — grant access (governance)"  bash scripts/govern/10-grant.sh
  run_step "Gouverner — read-only audit"            bash scripts/govern/05-audit.sh
fi

echo "=============================================="
ok "Automated redeployment complete."
echo "=============================================="
echo
echo "Remaining MANUAL steps (by design — see GUIDE.md sections 4 et 6):"
echo
echo "  1. Log in to the RHOAI dashboard as the demo end-user"
echo "     (username: ${DEMO_USER:-demo-user}; password in"
echo "     secrets/${DEMO_USER:-demo-user}.password, never printed here)."
echo "  2. Gen AI studio -> API keys -> Create API key, twice:"
echo "       - scoped to the main subscription"
echo "       - scoped to demo-low-quota"
echo "  3. Capture both keys locally, without ever pasting them anywhere else:"
echo "       make save-key"
echo "  4. Verify everything is green:"
echo "       make govern-verify"
echo "  5. (Optional, for the live demo's workbench step) create a Workbench"
echo "     from the dashboard, then wire the captured key into it:"
echo "       bash scripts/govern/22-wire-workbench.sh <namespace> <notebook-name> secrets/${DEMO_USER:-demo-user}.apikey"
echo
info "Full guide: GUIDE.md"
