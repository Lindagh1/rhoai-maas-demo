#!/usr/bin/env bash
# Single entry point to redeploy the FULL Sopra Steria MaaS demo kit
# (Demo 1 native publication + observability + Demo 2 end-user journey
# governance) on a brand-new RHOAI 3.5 sandbox.
#
# This script is a thin, ordered orchestration layer over the already
# existing, independently idempotent scripts in this repo -- it does not
# duplicate their logic. Every step it calls is itself safe to re-run.
#
# What this script does NOT do, by design (see docs/REDEPLOYMENT.md):
#   - It does not create the end-user's API keys (Scenario C) -- that is a
#     genuine non-admin dashboard action, which is exactly the point of the
#     demo and cannot be safely scripted (one-time secret reveal).
#   - It does not create a Workbench (Notebook) from scratch -- RHOAI's
#     dashboard-managed Notebook wiring (image, PVC, kube-rbac-proxy
#     sidecar, ServiceAccount, HTTPRoute) was never verified end-to-end
#     from raw YAML in this project; only patching an already-dashboard-
#     created Notebook was (scripts/demo2/22-wire-workbench-api-key.sh).
#   - It never commits or pushes anything to Git.
#   - It never prints or stores secret values anywhere but the local,
#     gitignored secrets/ directory.
#
# Usage:
#   bash scripts/bootstrap-redeployment.sh                 # everything
#   bash scripts/bootstrap-redeployment.sh --demo1-only     # Demo 1 + observability only
#   bash scripts/bootstrap-redeployment.sh --demo2-only     # Demo 2 governance only (Demo 1 must already be done)
#   bash scripts/bootstrap-redeployment.sh --skip-observability
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
    --demo1-only) RUN_DEMO2=0 ;;
    --demo2-only) RUN_DEMO1=0 ;;
    --skip-observability) RUN_OBSERVABILITY=0 ;;
    *) err "Unknown argument: $arg"; exit 2 ;;
  esac
done

require_login
assert_sandbox

echo "=============================================="
echo "Sopra Steria MaaS demo kit — full redeployment"
echo "=============================================="
info "Target cluster: $(oc whoami --show-server)"
info "Steps: demo1=${RUN_DEMO1} observability=${RUN_OBSERVABILITY} demo2=${RUN_DEMO2}"
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
  run_step "Demo 1 — read-only audit"            bash scripts/00-audit.sh
  run_step "Demo 1 — prerequisites"              bash scripts/10-prerequisites.sh
  run_step "Demo 1 — enable MaaS"                bash scripts/20-enable-maas.sh
  if [[ "$RUN_OBSERVABILITY" == "1" ]]; then
    run_step "Demo 1 — enable observability"     bash scripts/25-enable-observability.sh
  else
    warn "Skipping observability step (--skip-observability) — Observe & Monitor tabs will not be enabled."
  fi
  run_step "Demo 1 — deploy native model"        bash scripts/30-deploy-native-model.sh
  run_step "Demo 1 — publish to MaaS"            bash scripts/40-publish-maas.sh
  run_step "Demo 1 — verify (1st pass)"          bash scripts/50-verify.sh
  run_step "Demo 1 — verify (2nd pass, idempotence)" bash scripts/50-verify.sh
fi

if [[ "$RUN_DEMO2" == "1" ]]; then
  run_step "Demo 2 — detect identity provider"   bash scripts/demo2/00-detect-identity-provider.sh
  run_step "Demo 2 — create test identity"       bash scripts/demo2/01-create-test-identity.sh
  run_step "Demo 2 — grant access (governance)"  bash scripts/demo2/10-admin-grant-access.sh
  run_step "Demo 2 — read-only audit"            bash scripts/demo2/05-audit.sh
fi

echo "=============================================="
ok "Automated redeployment complete."
echo "=============================================="
echo
echo "Remaining MANUAL steps (by design — see docs/REDEPLOYMENT.md):"
echo
echo "  1. Log in to the RHOAI dashboard as the demo end-user"
echo "     (username: ${DEMO2_USER:-maas-demo2-user}; password in"
echo "     secrets/demo2/${DEMO2_USER:-maas-demo2-user}.password, never printed here)."
echo "  2. Gen AI studio -> API keys -> Create API key, twice:"
echo "       - scoped to the main subscription"
echo "       - scoped to the rate-limit-test subscription"
echo "  3. Capture both keys locally, without ever pasting them anywhere else:"
echo "       make demo2-capture-keys"
echo "  4. Verify everything is green:"
echo "       make demo2-verify"
echo "  5. (Optional, for Étape 3bis of the live guide) create a Workbench"
echo "     from the dashboard, then wire the captured key into it:"
echo "       bash scripts/demo2/22-wire-workbench-api-key.sh <namespace> <notebook-name> secrets/demo2/${DEMO2_USER:-maas-demo2-user}.apikey"
echo
info "Full runbook: docs/REDEPLOYMENT.md"
