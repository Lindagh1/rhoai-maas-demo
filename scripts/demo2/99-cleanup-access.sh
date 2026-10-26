#!/usr/bin/env bash
# Demo 2 — remove ONLY the subscription/authpolicy pair (not the test
# identity, not the model). Useful to re-demonstrate Scenario A ("no
# subscription") on demand, and as part of the full Demo 2 cleanup.
# Requires CONFIRM=yes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/demo2/lib.sh

require_login
if [[ "${CONFIRM:-}" != "yes" ]]; then
  err "Refusing to delete MaaS governance objects without CONFIRM=yes."
  echo "Re-run: CONFIRM=yes bash scripts/demo2/99-cleanup-access.sh"
  exit 2
fi

for obj in maassubscription/maas-demo2-subscription \
           maassubscription/maas-demo2-subscription-ratelimit-test \
           maasauthpolicy/maas-demo2-access; do
  oc delete "$obj" -n models-as-a-service --ignore-not-found=true
done
ok "Demo 2 subscription/authpolicy objects removed. Test identity, group, and model are untouched."
