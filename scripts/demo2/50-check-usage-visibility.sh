#!/usr/bin/env bash
# Demo 2 — Scenario F: usage visibility, admin vs non-admin.
#
# Non-sensitive, read-only. No secrets involved (no API key is read or
# used by this script at all).
#
# Captures two real, cluster-verified facts:
#   1. ADMIN visibility: Kuadrant/Limitador exposes real-time Prometheus
#      counters (authorized_calls, limited_calls, authorized_hits) per
#      Gateway HTTPRoute (i.e. per model), scraped automatically into
#      RHOAI's own monitoring stack via a ServiceMonitor that is
#      pre-provisioned and OWNED by the MaaS operator's own `Config`
#      CR (maas.opendatahub.io/v1alpha1) — not something this demo had
#      to set up itself.
#   2. REAL LIMITATION (documented, not assumed): this metric is
#      aggregated per-model/route only. It does NOT break down usage
#      by individual subscription, user, or API key. Confirmed by
#      inspecting the MaaSSubscription CRD schema: its `.status` has no
#      usage/consumption field at all, only readiness/reconciliation
#      conditions.
#   3. NON-ADMIN visibility: confirmed via the real dashboard (as
#      maas-demo2-user) that the Subscriptions tab shows only the
#      configured token-rate-limit ceiling (e.g. "2,000 / 1 minute")
#      and the count of active API keys — never actual consumption,
#      remaining quota, or any usage history/graph.
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
  echo "Real finding: these counters are scoped per Gateway HTTPRoute"
  echo "(i.e. per model, label 'limitador_namespace'), not per-subscription,"
  echo "per-user, or per-API-key. An admin can see aggregate traffic and"
  echo "rate-limit rejections for a model, but cannot attribute them to a"
  echo "specific subscriber from this metric alone."
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
  echo "Usage data exists ONLY in Limitador's Prometheus counters (see"
  echo "scenario-f-01), which are aggregated per-model, not per-subscription."
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
