#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
umask 077
mkdir -p secrets
chmod 700 secrets
read -rsp 'Clé de demo-quota (Entrée pour conserver si déjà enregistrée) : ' key; echo
if [[ -n "$key" ]]; then
 [[ "$key" == sk-oai-* ]] || { echo 'Clé MaaS attendue.' >&2; exit 1; }
 printf '%s' "$key" > secrets/demo-user.apikey
elif [[ -s secrets/demo-user.apikey ]]; then
 echo 'Clé principale existante conservée.'
else
 echo 'Aucune clé principale enregistrée. Relancer make save-key et coller la clé de demo-quota.' >&2
 exit 1
fi
chmod 600 secrets/demo-user.apikey
read -rsp 'Clé de demo-low-quota (Entrée pour ignorer) : ' key; echo
if [[ -n "$key" ]]; then
 [[ "$key" == sk-oai-* ]] || { echo 'Clé MaaS attendue.' >&2; exit 1; }
 printf '%s' "$key" > secrets/demo-user.ratelimit.apikey
 chmod 600 secrets/demo-user.ratelimit.apikey
fi
unset key
echo 'Clé(s) enregistrée(s) dans secrets/, sans affichage.'
