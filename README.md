# RHOAI 3.5 MaaS — publier un modèle, puis gouverner qui l'appelle

Démo généraliste.

**Pas à pas de la démo (champs, curl, observabilité) :**
[`GUIDE.md`](GUIDE.md), section **Feuille de tournage**.

Deux gestes, et seulement ceux-là :

```text
Publier   : déployer demo-llm et le publier dans MaaS
Gouverner : demo-team peut l'appeler, demo-quota dit combien de tokens
```

Le mode d'emploi complet est [`GUIDE.md`](GUIDE.md) (le PDF se régénère avec `make pdf`).

## Les noms

| Rôle | Nom | Fichier |
|---|---|---|
| Projet | `maas-demo` | `manifests/model/namespace.yaml` |
| Modèle | `demo-llm` | `manifests/model/llm.yaml` |
| Publication MaaS | `demo-llm` | `manifests/publish/model-ref.yaml` |
| Groupe | `demo-team` | créé par `scripts/govern/01-create-user.sh` |
| Utilisateur | `demo-user` | idem, mot de passe : `cat /home/lgheziel/Projects/rhoai-maas-demo/secrets/demo-user.password` |
| Quota (combien) | `demo-quota` | `manifests/govern/quota.yaml` |
| Accès (qui) | `demo-access` | `manifests/govern/access.yaml` |
| Petit quota (429) | `demo-low-quota` | `manifests/govern/low-quota.yaml` |

`MaaSSubscription` = combien. `MaaSAuthPolicy` = qui. Les deux sont nécessaires.

## Démarrer

```bash
oc login --server=<API> --token=<TOKEN>
git clone https://github.com/Lindagh1/rhoai-maas-demo.git && cd rhoai-maas-demo
bash scripts/bootstrap.sh
```

Puis [`GUIDE.md`](GUIDE.md), section 3 (le mot de passe) et section 4 (les clés API).

```bash
make publish          # le modèle, seulement
make govern-setup     # l'utilisateur, le quota, l'accès
make save-key         # après avoir créé les clés dans le dashboard
make call             # un curl d'inférence
make show-denials     # 403 sans accès, 403 sans quota, 429 quota épuisé
```

## Sécurité

- Les secrets sont générés à l'installation et ne sont jamais commités (`secrets/` est ignoré).
- Ne colle pas de token OpenShift dans le dépôt ni dans un chat.
- Les Gateways partagés et les modèles déjà présents sur la sandbox ne sont pas écrasés.
