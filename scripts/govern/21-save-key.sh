#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
umask 077
mkdir -p secrets
chmod 700 secrets
read -rsp 'Clé de demo-quota : ' key; echo
[[ "$key" == sk-oai-* ]] || { echo 'Clé MaaS attendue.' >&2; exit 1; }
printf '%s' "$key" > secrets/demo-user.apikey
read -rsp 'Clé de demo-low-quota (Entrée pour ignorer) : ' key; echo
if [[ -n "$key" ]]; then
 [[ "$key" == sk-oai-* ]] || { echo 'Clé MaaS attendue.' >&2; exit 1; }
 printf '%s' "$key" > secrets/demo-user.ratelimit.apikey
fi
unset key
echo 'Clé(s) enregistrée(s) dans secrets/, sans affichage.'
