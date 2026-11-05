#!/usr/bin/env bash
# Prepare the shared platform and identity, leaving model creation for the live demo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
for step in publish/00-audit publish/10-prerequisites publish/20-enable-platform publish/25-observability govern/01-create-user; do
 bash "scripts/$step.sh"
done
oc apply -f manifests/model/hardware-profile.yaml
printf '\nPlateforme prête. Commencer FEUILLE-DEMO.md pour créer le projet et le modèle.\n'
