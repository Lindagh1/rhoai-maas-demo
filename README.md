# RHOAI 3.5 MaaS — Demo 1 (natif llm-d)

Démo **reproductible** pour sandboxes Red Hat OpenShift AI 3.5 :

```text
LLMInferenceService (llm-d) → MaaSModelRef → modèle publié dans MaaS
```

La Demo 2 (abonnements, clés API, quotas) est volontairement hors scope.

---

## Guides (commence ici)

| Guide | Pour qui | Markdown | PDF |
|---|---|---|---|
| **Installation** | Toi, avant la démo | [`GUIDE-INSTALLATION-DEMO1.md`](docs/GUIDE-INSTALLATION-DEMO1.md) | [`PDF`](docs/GUIDE-INSTALLATION-DEMO1.pdf) |
| **Démo live (clics)** | Présentation client | [`GUIDE-DEMO-LIVE.md`](docs/GUIDE-DEMO-LIVE.md) | [`PDF`](docs/GUIDE-DEMO-LIVE.pdf) |
| Troubleshooting | Quand ça coince | [`troubleshooting.md`](docs/troubleshooting.md) | — |

Régénérer les PDF localement : `bash scripts/generate_pdf.sh`

---

## Installation rapide

```bash
git clone https://github.com/Lindagh1/rhoai-maas-demo.git
cd rhoai-maas-demo
git checkout main

oc login --server="$SANDBOX_API" --token="$SANDBOX_TOKEN" --insecure-skip-tls-verify=true

bash scripts/00-audit.sh
bash scripts/10-prerequisites.sh
bash scripts/20-enable-maas.sh
bash scripts/30-deploy-native-model.sh
bash scripts/40-publish-maas.sh
bash scripts/50-verify.sh
bash scripts/50-verify.sh
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
