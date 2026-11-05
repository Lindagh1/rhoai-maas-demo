# OpenShift AI MaaS : du modèle Hugging Face à l'appel API

**L'histoire :** l'administrateur met un assistant à disposition d'une équipe Data Science. Il déploie ses poids depuis Hugging Face, publie le modèle dans MaaS, définit une souscription et une autorisation. Le data scientist crée sa propre clé, appelle le modèle et l'administrateur voit les tokens consommés.

- [Guide de préparation et de reconstruction](GUIDE.md)
- [Feuille de démonstration : clics, champs, phrases à dire](FEUILLE-DEMO.md)
- [Validation et limites observées](docs/VALIDATION.md)

## Deux façons de démarrer

Après connexion `oc login` en administrateur sur la sandbox cible :

```bash
make prepare   # plateforme + identité ; création du projet/modèle en direct
# OU
make demo      # reconstruction complète pour préparer une répétition
make endpoints # liens de CETTE sandbox
```

Le modèle par défaut est **Qwen/Qwen2.5-0.5B-Instruct**, réellement téléchargé depuis Hugging Face et servi par vLLM sur **1 GPU**. La source Hugging Face héberge les poids ; l'inférence s'exécute dans OpenShift. Aucun jeton Hugging Face n'est nécessaire pour ce modèle public.

`MODEL_MODE=simulator make demo` est une répétition CPU explicitement simulée. Elle ne démontre ni le chargement de vrais poids ni la qualité d'un LLM.

## Les noms à retenir

- Projet `maas-demo` : l'espace de la démonstration.
- Déploiement et publication `demo-llm` : l'assistant partagé.
- Groupe `demo-team` et compte `demo-user` : les consommateurs.
- Souscription `demo-quota` : les modèles disponibles et la limite de 2 000 tokens/minute.
- Autorisation `demo-access` : le droit d'atteindre le modèle.
- Souscription optionnelle `demo-low-quota` : 50 tokens/minute pour montrer le 429.

Les identifiants restent stables pour conserver les clés existantes. Les libellés visibles expliquent le rôle de chaque objet.

## Prouver que cela fonctionne

Créer une clé en tant que `demo-user` dans **Gen AI studio → API keys**, puis `make save-key` pour la stocker localement.

```bash
make call         # réponse réelle et usage.prompt_tokens/completion_tokens/total_tokens
make traffic      # cinq appels bornés
make quota-test   # clé séparée du petit quota ; attend un 429
make usage        # compteurs réels côté admin
```

Le client `scripts/client.py` fonctionne sans `oc` et sans droits admin lorsqu'on lui fournit `--url`. Les scripts de préparation utilisent `oc` pour découvrir le domaine de la nouvelle sandbox. Aucun domaine ni secret de sandbox n'est enregistré dans les manifestes.

La compatibilité cible est **RHOAI 3.5 / OpenShift 4.20**, testée sur 3.5.2 / 4.20.42. Voir le guide pour les prérequis et la différence entre une relance sur cette sandbox et une installation sur une sandbox neuve.
