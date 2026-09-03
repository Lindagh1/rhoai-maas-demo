#!/usr/bin/env bash
# validate.sh - Run status + a lightweight health re-check (make validate).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
require_login

echo "=============================================="
echo "VALIDATE"
echo "=============================================="
./scripts/status.sh

echo ""
echo "--- Platform health re-check ---"
CRASHLOOPS=$(oc get pods -A --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || true)
OOMKILLS=$(oc get pods -A -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
n=0
for p in d['items']:
    for cs in p['status'].get('containerStatuses', []):
        if cs.get('lastState', {}).get('terminated', {}).get('reason') == 'OOMKilled':
            n+=1
print(n)
" 2>/dev/null || echo 0)
printf "%-30s %s\n" "CrashLoopBackOff pods" "$CRASHLOOPS"
printf "%-30s %s\n" "OOMKilled containers" "$OOMKILLS"
oc adm top nodes
echo "=============================================="
if [[ "$CRASHLOOPS" == "0" && "$OOMKILLS" == "0" ]]; then
  echo "VALIDATE: PASS"
else
  echo "VALIDATE: FAIL"
  exit 1
fi
