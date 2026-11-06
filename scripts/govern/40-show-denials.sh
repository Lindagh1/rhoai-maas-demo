#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source scripts/lib.sh
require_login
assert_sandbox
export MAAS_URL="${MAAS_URL:-$(maas_host_url)}"
python3 scripts/verify-access.py
bash scripts/govern/20-call.sh --key-file secrets/demo-user.ratelimit.apikey --count 5 --expect-429 --output evidence/quota.json
