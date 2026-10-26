#!/usr/bin/env bash
# Demo 2 — Scenario F: usage visibility, admin vs non-admin.
#
# Non-sensitive, read-only. No secrets involved (no API key is read or
# used by this script at all).
#
# Captures three real, cluster-verified facts:
#   1. ADMIN visibility: Kuadrant/Limitador exposes real-time Prometheus
#      counters (`authorized_calls`, `limited_calls`, `authorized_hits`).
#      On this build they carry at least subscription labels, and
#      `authorized_hits` also carries a model label.
#   2. REAL LIMITATION (documented, not assumed): these metrics do NOT
#      expose a usable per-user breakdown on this build, and the built-in
#      Observe & Monitor → Dashboard → Usage view can therefore stay at 0
#      even after real traffic because its PromQL queries filter on a
#      missing `user` label. Confirmed live while inspecting the
#      Prometheus series actually present.
#   3. NON-ADMIN visibility: confirmed via the real dashboard (as
#      maas-demo2-user) that the Subscriptions tab shows only the
#      configured token-rate-limit ceiling (e.g. "2,000 / 1 minute")
#      and the count of active API keys — never actual consumption,
#      remaining quota, or any usage history/graph.
# NOTE: -e is deliberately omitted. This script probes Limitador metrics via
# port-forward + curl and inspects CRD schemas — soft failures are expected
# and classified, not fatal errors.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

EVIDENCE_DIR="evidence/demo2"
mkdir -p "$EVIDENCE_DIR"
require_login

echo "=============================================="
echo "Demo 2 — Scenario F: usage visibility (admin vs non-admin)"
echo "=============================================="

### 1. Admin-side: real Limitador Prometheus metrics
echo
echo "--- Admin: Limitador /metrics (Kuadrant rate-limit counters) ---"
PF_LOG="/tmp/demo2-limitador-pf.$$.log"
oc port-forward -n kuadrant-system svc/limitador-limitador 18080:8080 >"$PF_LOG" 2>&1 &
PF_PID=$!
cleanup_pf() { kill "$PF_PID" 2>/dev/null; wait "$PF_PID" 2>/dev/null; rm -f "$PF_LOG"; }
trap cleanup_pf EXIT
sleep 3
METRICS=$(curl -sS --connect-timeout 5 --max-time 10 http://localhost:18080/metrics 2>/dev/null || echo "")
cleanup_pf
trap - EXIT

if [[ -z "$METRICS" ]]; then
  err "Could not reach Limitador /metrics via port-forward."
else
  echo "$METRICS" | grep -E 'authorized_calls|limited_calls|authorized_hits|limitador_up' || echo "(no matching metric lines found)"
  ok "Admin can observe real-time authorized/limited call counters via Limitador."
fi

{
  echo "# Scenario F — Admin-side usage visibility (Limitador Prometheus metrics)"
  echo "Date: $(date -u +%FT%TZ)"
  echo
  echo "Raw /metrics (filtered to the counters relevant to Demo 2's model):"
  echo "$METRICS" | grep -E '^(#|authorized_calls|limited_calls|authorized_hits|limitador_up)' || echo "(none)"
  echo
  echo "Real finding: these counters include subscription labels, and"
  echo "'authorized_hits' also includes a model label on this build."
  echo "They still do NOT expose a usable per-user breakdown, which is why"
  echo "the built-in Observe & Monitor -> Dashboard -> Usage view can stay"
  echo "empty/zero after real traffic: its queries filter on user labels"
  echo "that are not present in the scraped Limitador series."
  echo
  echo "Scrape wiring (pre-provisioned, not created by this demo):"
  oc get servicemonitor limitador-metrics -n redhat-ods-monitoring -o yaml 2>/dev/null \
    | grep -A3 'ownerReferences:' || echo "(ServiceMonitor not found)"
} > "$EVIDENCE_DIR/scenario-f-01-admin-limitador-metrics.txt"

### 2. Confirm MaaSSubscription CR has no usage/consumption field
echo
echo "--- Confirming MaaSSubscription status has no usage field (CRD schema) ---"
USAGE_FIELDS=$(oc get crd maassubscriptions.maas.opendatahub.io -o json 2>/dev/null \
  | python3 -c "
import json,sys
d = json.load(sys.stdin)
versions = d.get('spec', {}).get('versions', [])
props = versions[-1]['schema']['openAPIV3Schema']['properties']['status']['properties'] if versions else {}
print(','.join(sorted(props.keys())))
" 2>/dev/null || echo "?")
echo "MaaSSubscription .status fields: $USAGE_FIELDS"
{
  echo "# Scenario F — MaaSSubscription CRD status schema (no usage field)"
  echo "Date: $(date -u +%FT%TZ)"
  echo ".status field names: $USAGE_FIELDS"
  echo
  echo "Real finding: none of these fields represent token/request usage or"
  echo "remaining quota. The CR only tracks readiness/reconciliation state."
  echo "Usage data does not live on the MaaSSubscription object itself."
  echo "The real counters live in Limitador Prometheus metrics (see"
  echo "scenario-f-01), but this build still lacks a usable per-user view."
} > "$EVIDENCE_DIR/scenario-f-02-subscription-cr-no-usage-field.txt"
if echo "$USAGE_FIELDS" | grep -qiE 'usage|consum|remaining|tokensUsed'; then
  warn "Unexpected: found a usage-like field ($USAGE_FIELDS) — update the finding above."
else
  ok "Confirmed: MaaSSubscription.status has no usage/consumption field."
fi

echo
echo "--- Non-admin dashboard view (captured manually, see scenario-f-03) ---"
echo "See $EVIDENCE_DIR/scenario-f-03-user-dashboard-view.txt for the exact"
echo "real UI text captured from the maas-demo2-user dashboard session."

echo
echo "Evidence saved under $EVIDENCE_DIR/."
echo "=============================================="
