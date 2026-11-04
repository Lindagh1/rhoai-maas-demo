#!/usr/bin/env bash
# Gouverner — remove ONLY the subscription/authpolicy pair (not the test
# identity, not the model). Useful to re-demonstrate Scenario A ("no
# subscription") on demand, and as part of the full Gouverner cleanup.
# Requires CONFIRM=yes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/govern/lib.sh

require_login
if [[ "${CONFIRM:-}" != "yes" ]]; then
  err "Refusing to delete MaaS governance objects without CONFIRM=yes."
  echo "Re-run: CONFIRM=yes bash scripts/govern/99-cleanup.sh"
  exit 2
fi

for obj in maassubscription/demo-quota \
           maassubscription/demo-low-quota \
           maasauthpolicy/demo-access \
           maasauthpolicy/demo-quota-policy; do
  oc delete "$obj" -n models-as-a-service --ignore-not-found=true
done
ok "Gouverner subscription/authpolicy objects removed (including the known duplicate-policy cleanup if present). Test identity, group, and model are untouched."
