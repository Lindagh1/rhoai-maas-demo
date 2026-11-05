#!/usr/bin/env bash
# Explicit, bounded reset. Shared infrastructure and API-key database remain intact.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
require_login
assert_sandbox
[[ "${CONFIRM:-}" == yes ]] || { err 'CONFIRM=yes required: deletes only demo model/governance; keeps project and platform.'; exit 2; }
oc delete maassubscription demo-quota demo-low-quota -n models-as-a-service --ignore-not-found
oc delete maasauthpolicy demo-access demo-quota-policy -n models-as-a-service --ignore-not-found
oc delete maasmodelref demo-llm -n maas-demo --ignore-not-found
oc delete llminferenceservice demo-llm -n maas-demo --ignore-not-found --wait=true
info 'Demo reset. The project remains. For a live project-creation scene, use a fresh sandbox.'
