#!/usr/bin/env bash
# Gouverner — consolidated post-setup verification. Re-checks that the
# whole environment is in the expected working state: model Ready,
# governance objects Active, and both known API keys (if present)
# still ACTIVE. Read-only except for the quick GET /v1/models calls
# this already performs via scripts/govern/30-check-key.sh.
# NOTE: -e is deliberately omitted. This script accumulates PASS/FAIL across
# multiple checks and reports them all, rather than aborting at the first
# failure. The final exit code reflects the aggregate result.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/govern/lib.sh

require_login
echo "=============================================="
echo "Gouverner — Consolidated verification"
echo "=============================================="

FAIL=0

echo
echo "--- MaaSModelRef readiness ---"
PHASE=$(oc get maasmodelref "$DEMO_MODEL" -n "$DEMO_PROJECT" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$PHASE" == "Ready" ]]; then
  ok "MaaSModelRef phase: Ready"
else
  err "MaaSModelRef phase: $PHASE (expected Ready)"
  FAIL=1
fi

echo
echo "--- Governance objects ---"
for obj in \
  "maassubscription/${DEMO_QUOTA}" \
  "maassubscription/demo-low-quota" \
  "maasauthpolicy/${DEMO_ACCESS}"; do
  STATE=$(oc get "$obj" -n models-as-a-service -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
  if [[ "$STATE" == "Active" ]]; then
    ok "$obj: Active"
  else
    err "$obj: $STATE (expected Active)"
    FAIL=1
  fi
done

EXTRA_POLICY="demo-quota-policy"
if oc get maasauthpolicy "$EXTRA_POLICY" -n models-as-a-service >/dev/null 2>&1; then
  warn "Found unexpected duplicate MaaSAuthPolicy/${EXTRA_POLICY}. It is harmless but confusing; delete it to keep the demo tidy."
fi

echo
echo "--- API keys (if captured locally) ---"
for f in "$DEMO_APIKEY_FILE" "$SECRETS_DIR/${DEMO_USER}.ratelimit.apikey"; do
  if [[ -f "$f" ]]; then
    bash scripts/govern/30-check-key.sh "$f" active || FAIL=1
  else
    warn "$(basename "$f") not present — skipping (run Scenario C first if needed)."
  fi
done

echo
echo "=============================================="
if [[ "$FAIL" == "0" ]]; then
  ok "All checks passed."
else
  err "One or more checks failed — see above."
fi
echo "=============================================="
exit "$FAIL"
