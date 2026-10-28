# RHOAI 3.5 MaaS — Demo 1 (natif llm-d) + Demo 2 (parcours utilisateur)

Démos **reproductibles** pour sandboxes Red Hat OpenShift AI 3.5 :

```text
Demo 1 : LLMInferenceService (llm-d) → MaaSModelRef → modèle publié dans MaaS
Demo 2 : abonnements MaaS → clé API utilisateur → inférence gouvernée (quotas, 403/429, révocation)
```

Demo 2 réutilise le modèle et l'infrastructure de la Demo 1 sans les modifier — voir
[`DEMO2-RESULTS.md`](DEMO2-RESULTS.md) pour l'état complet (PASS/BLOCKED/FAIL par scénario).

## Corporate Scenario (guide officiel `rhoai-maas-guide`)

Piste **séparée** des Demo 1/Demo 2 ci-dessous : suit tel quel le guide
officiel [rh-aiservices-bu/rhoai-maas-guide](https://github.com/rh-aiservices-bu/rhoai-maas-guide)
(installation MaaS Phases 0-6 + sa démo "Corporate Scenario" — un CIO
déploie MaaS sur 3 divisions avec accès/quotas différenciés). Le guide est
vendored dans [`vendor/rhoai-maas-guide/`](vendor/rhoai-maas-guide/), bugs
réels trouvés et corrigés documentés dans
[`vendor/rhoai-maas-guide/PATCHES.md`](vendor/rhoai-maas-guide/PATCHES.md).
Résultats complets : [`docs/CORPORATE-SCENARIO-RESULTS.md`](docs/CORPORATE-SCENARIO-RESULTS.md).

## Chemin recommandé

### Sandbox neuve → tout en une commande

```bash
oc login --server=<API> --token=<TOKEN>
git clone https://github.com/Lindagh1/rhoai-maas-demo.git && cd rhoai-maas-demo
bash scripts/bootstrap-redeployment.sh
```

Ça installe Demo 1 (modèle natif + MaaS + observabilité) et prépare Demo 2
(identité + gouvernance) de façon idempotente, puis affiche à l'écran les
2 seules étapes volontairement manuelles (créer les clés API dans le
dashboard). Détails complets : [`docs/REDEPLOYMENT.md`](docs/REDEPLOYMENT.md).

### Pas-à-pas (si tu veux du contrôle étape par étape)

1. **Installer Demo 1**  
   `make demo1-all`
2. **Préparer Demo 2**  
   `make demo2-audit` puis `make demo2-setup`
3. **Vérifier l'état avant la salle**  
   `make demo2-verify`

### Puis, dans les deux cas, pour jouer la démo

4. **Créer les clés API** (dashboard, en session `maas-demo2-user`) puis  
   `make demo2-capture-keys` et `make demo2-verify`
5. **Suivre le guide live**  
   [`docs/GUIDE-DEMO-LIVE-DEMO2.md`](docs/GUIDE-DEMO-LIVE-DEMO2.md) (ou son [PDF](docs/GUIDE-DEMO-LIVE-DEMO2.pdf)) pour Demo 2, [`docs/GUIDE-DEMO-LIVE.md`](docs/GUIDE-DEMO-LIVE.md) pour Demo 1

Ce repo distingue volontairement :
- les **scripts de préparation/admin** (`make demo1-*`, `make demo2-*`, `scripts/bootstrap-redeployment.sh`)
- le **guide live client** (ce qu'on montre à l'écran)
- les **constats réels** quand le produit ne se comporte pas exactement comme la doc.

---

## Structure du dépôt

Ce dépôt a accumulé plusieurs démos RHOAI construites sur les mêmes sandboxes. **Si tu cherches la Demo 1 MaaS, reste dans `scripts/00-`→`99-`, `manifests/platform/`, `manifests/model/`, `manifests/maas/` et `docs/GUIDE-*`.**

| Dossier / fichier | Démo | Statut |
|---|---|---|
| `scripts/00-audit.sh` … `99-cleanup.sh`, `manifests/platform/`, `manifests/model/`, `manifests/rhoai-operator/`, `docs/GUIDE-*`, `docs/sandbox-audit.md` | **Demo 1 — MaaS natif llm-d** | Actif, maintenu |
| `manifests/maas/maas-model-ref.yaml` | Publication MaaS du modèle Demo 1 | Actif, maintenu |
| `scripts/demo2/`, `manifests/demo2/`, `docs/demo2/`, `docs/GUIDE-DEMO-LIVE-DEMO2.md`, `DEMO2-RESULTS.md` | **Demo 2 — parcours utilisateur MaaS** (abonnements, clés API, quotas, révocation) | Actif, maintenu |
| `manifests/maas/maas-subscription.yaml`, `manifests/maas/maas-auth-policy.yaml` | Gouvernance publique `system:authenticated` de l'ancien sandbox `t5lkh` | **Orphelin — non appliqué sur cette sandbox, ne pas réutiliser.** La gouvernance réelle et active passe par `manifests/demo2/10-*`/`11-*`/`12-*`, scopée au groupe `maas-demo2-developers`. |
| `scripts/install-rhoai-operator.sh`, `scripts/bootstrap.sh`, `scripts/preflight.sh`, `scripts/status.sh`, `scripts/api_key.sh`, `scripts/demo-auth.sh`, `scripts/demo-rate-limit.sh`, `scripts/validate.sh`, `scripts/test-idempotency.sh`, `scripts/cleanup.sh`, `docs/BASELINE.md`, `docs/PREFLIGHT.md` | Installation RHOAI de base (ancien sandbox `t5lkh`) | Historique |
| `openshift-ai-demo/`, `manifests/fraud-detection-tutorial/`, `manifests/workbench-vscode-demo/` | Knowledge Advisor (RAG) / fraud-detection / workbench VS Code | Historique, autres démos |
| `docs/sandbox-t5lkh/` | Docs spécifiques à l'ancien sandbox `t5lkh` | Historique |

Les manifests/scripts « historiques » et « orphelins » restent dans le dépôt pour traçabilité, mais **ne font pas partie du parcours Demo 1/Demo 2** décrit ci-dessous, et ne doivent pas être appliqués sur une nouvelle sandbox.

**Kit de redéploiement sur sandbox neuve** : voir [`docs/REDEPLOYMENT.md`](docs/REDEPLOYMENT.md) — inventaire complet, script de bootstrap unique, validation sans mutation, et liste précise de ce qui reste volontairement manuel (dashboard).

---

## Guides (commence ici)

| Guide | Pour qui | Markdown | PDF |
|---|---|---|---|
| **Kit de redéploiement (sandbox neuve)** | Toi, avant tout le reste | [`REDEPLOYMENT.md`](docs/REDEPLOYMENT.md) | — |
| **Installation (Demo 1)** | Toi, avant la démo | [`GUIDE-INSTALLATION-DEMO1.md`](docs/GUIDE-INSTALLATION-DEMO1.md) | [`PDF`](docs/GUIDE-INSTALLATION-DEMO1.pdf) |
| **Démo live Demo 1 (clics console)** | Présentation client | [`GUIDE-DEMO-LIVE.md`](docs/GUIDE-DEMO-LIVE.md) | [`PDF`](docs/GUIDE-DEMO-LIVE.pdf) |
| **Démo live Demo 2 (dashboard + terminal)** | Présentation client | [`GUIDE-DEMO-LIVE-DEMO2.md`](docs/GUIDE-DEMO-LIVE-DEMO2.md) | [`PDF`](docs/GUIDE-DEMO-LIVE-DEMO2.pdf) |
| Setup + reproduction (Demo 2) | Toi, avant la démo | [`docs/demo2/06-new-sandbox-reproduction.md`](docs/demo2/06-new-sandbox-reproduction.md) | — |
| Résultats détaillés (Demo 2) | Toi / client technique | [`DEMO2-RESULTS.md`](DEMO2-RESULTS.md) | — |
| Troubleshooting | Quand ça coince | [`troubleshooting.md`](docs/troubleshooting.md), [`docs/demo2/05-troubleshooting.md`](docs/demo2/05-troubleshooting.md) | — |

Régénérer les PDF localement : `bash scripts/generate_pdf.sh`

---

## Installation rapide — équivalent sans `make`

Pour une sandbox neuve, la commande à retenir reste celle de la section
**« Chemin recommandé »** en haut de ce fichier
(`bash scripts/bootstrap-redeployment.sh`). Ce qui suit est l'équivalent
manuel de **Demo 1 seule**, script par script, pour qui préfère ne pas
passer par `make` ou `bootstrap-redeployment.sh` :

```bash
git clone https://github.com/Lindagh1/rhoai-maas-demo.git
cd rhoai-maas-demo

oc login --server="$SANDBOX_API" --token="$SANDBOX_TOKEN" --insecure-skip-tls-verify=true

bash scripts/00-audit.sh
bash scripts/10-prerequisites.sh
bash scripts/20-enable-maas.sh
bash scripts/25-enable-observability.sh
bash scripts/30-deploy-native-model.sh
bash scripts/40-publish-maas.sh
bash scripts/50-verify.sh && bash scripts/50-verify.sh   # 2x : vérifie aussi l'idempotence
```

Nettoyage (ressources de la démo seulement) :

```bash
CONFIRM=yes bash scripts/99-cleanup.sh
```

---

## Documentation Red Hat (3.5)

- [Govern LLM access with MaaS](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service)
- [Distributed inference with llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploy_models_using_distributed_inference_with_llm-d/deploying-models-using-distributed-inference_distributed-inference)
- [Supported configurations](https://access.redhat.com/articles/rhoai-supported-configs)

---

## Sécurité

- Les secrets sont générés à l’installation — **jamais** commités.
- Ne colle pas de token OpenShift dans le dépôt ni dans un chat.
- Les Gateways partagés et les modèles legacy existants ne sont pas écrasés.
- Pas de bascule silencieuse vers le Technology Preview vLLM-on-MaaS.
