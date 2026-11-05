#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source scripts/lib.sh
export MAAS_URL="${MAAS_URL:-$(maas_host_url)}"
exec python3 scripts/client.py "$@"
