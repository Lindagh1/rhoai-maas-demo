# RHOAI 3.5 MaaS — Demo 1 (natif llm-d) + Demo 2 (parcours utilisateur)

Démos **reproductibles** pour sandboxes Red Hat OpenShift AI 3.5 :

```text
Demo 1 : LLMInferenceService (llm-d) → MaaSModelRef → modèle publié dans MaaS
Demo 2 : abonnements MaaS → clé API utilisateur → inférence gouvernée (quotas, 403/429, révocation)
```

## 📘 Le guide — un seul fichier, tout est dedans

**[`GUIDE.md`](GUIDE.md)** (ou son [PDF](GUIDE.pdf)) couvre **tout le
cycle**, dans l'ordre : prérequis → installation sur sandbox neuve →
où trouver les identifiants (admin, `maas-demo2-user`, clés API) →
démo live clic par clic (console + dashboard) → aide-mémoire →
dépannage → nettoyage → annexe technique.

C'est le seul document à ouvrir. Pas besoin de deviner où chercher.

Pour la matrice complète des scénarios testés (preuves PASS/BLOCKED/FAIL
par rapport à la documentation officielle) : [`DEMO2-RESULTS.md`](DEMO2-RESULTS.md).

## Démarrage ultra-rapide

```bash
oc login --server=<API> --token=<TOKEN>
git clone https://github.com/Lindagh1/rhoai-maas-demo.git && cd rhoai-maas-demo
bash scripts/bootstrap-redeployment.sh
```

Puis ouvrir [`GUIDE.md`](GUIDE.md) et suivre la section 3 (identifiants)
et 4 (clés API) pour les 2 étapes manuelles restantes.

---

## Structure du dépôt

Ce dépôt a accumulé plusieurs démos RHOAI construites sur les mêmes sandboxes. **Si tu cherches la Demo 1/Demo 2 MaaS, tout est dans [`GUIDE.md`](GUIDE.md) + `scripts/00-`→`99-`, `scripts/demo2/`, `manifests/`.**

| Dossier / fichier | Démo | Statut |
|---|---|---|
| `GUIDE.md`, `DEMO2-RESULTS.md`, `scripts/00-audit.sh` … `99-cleanup.sh`, `scripts/demo2/`, `manifests/platform/`, `manifests/model/`, `manifests/rhoai-operator/`, `manifests/demo2/`, `manifests/maas/maas-model-ref.yaml` | **Demo 1 + Demo 2 — MaaS natif llm-d + gouvernance** | Actif, maintenu |
| `manifests/maas/maas-subscription.yaml`, `manifests/maas/maas-auth-policy.yaml` | Gouvernance publique `system:authenticated` de l'ancien sandbox `t5lkh` | **Orphelin — non appliqué sur cette sandbox, ne pas réutiliser.** La gouvernance réelle et active passe par `manifests/demo2/10-*`/`11-*`/`12-*`, scopée au groupe `maas-demo2-developers`. |
| `scripts/install-rhoai-operator.sh`, `scripts/bootstrap.sh`, `scripts/preflight.sh`, `scripts/status.sh`, `scripts/api_key.sh`, `scripts/demo-auth.sh`, `scripts/demo-rate-limit.sh`, `scripts/validate.sh`, `scripts/test-idempotency.sh`, `scripts/cleanup.sh` | Installation RHOAI de base (ancien sandbox `t5lkh`) | Historique |
| `openshift-ai-demo/`, `manifests/fraud-detection-tutorial/`, `manifests/workbench-vscode-demo/` | Knowledge Advisor (RAG) / fraud-detection / workbench VS Code | Historique, autres démos |

Les manifests/scripts « historiques » et « orphelins » restent dans le dépôt pour traçabilité, mais **ne font pas partie du parcours Demo 1/Demo 2** décrit dans `GUIDE.md`, et ne doivent pas être appliqués sur une nouvelle sandbox.

Régénérer le PDF du guide localement : `bash scripts/generate_pdf.sh`

---

## Sécurité

- Les secrets sont générés à l'installation — **jamais** commités.
- Ne colle pas de token OpenShift dans le dépôt ni dans un chat.
- Les Gateways partagés et les modèles legacy existants ne sont pas écrasés.
- Pas de bascule silencieuse vers le Technology Preview vLLM-on-MaaS.
