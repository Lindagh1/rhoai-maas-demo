#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
printf 'OpenShift: https://console-openshift-console.%s\n' "$(cluster_domain)"
printf 'OpenShift AI: %s\n' "$(oc get dashboard default-dashboard -o jsonpath='{.status.url}')"
printf 'export MAAS_URL=%s\n' "$(maas_host_url)"
