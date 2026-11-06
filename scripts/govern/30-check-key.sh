#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source scripts/lib.sh
export MAAS_URL="${MAAS_URL:-$(maas_host_url)}"
python3 - "${1:-secrets/demo-user.apikey}" "${2:-active}" <<'PY'
import os,sys,pathlib
sys.path.insert(0,'scripts')
from client import request
code,_=request(os.environ['MAAS_URL'],pathlib.Path(sys.argv[1]).read_text().strip(),'/v1/models')
expected={200} if sys.argv[2]=='active' else {401,403}
print('Key check: HTTP',code)
sys.exit(0 if code in expected else 1)
PY
