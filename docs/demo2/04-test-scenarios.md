# Demo 2 — Matrice de scénarios vérifiés

Ce document est la vérité terrain de Demo 2 : ce qui a été vérifié, ce
qui a divergé de la doc officielle, et ce qu'il vaut mieux montrer en
live.

Statuts utilisés : **PASS** / **FAIL** / **BLOCKED** / **NOT TESTED**.

## Scenario A — utilisateur sans subscription

| Champ | Résultat |
|---|---|
| Objectif | Vérifier le comportement d'un vrai utilisateur sans accès MaaS |
| Attendu | L'utilisateur ne peut pas créer de clé utile |
| Observé | Texte UI réel : `Request a subscription`, `No API keys`, `No subscriptions available` |
| Conclusion | **PASS** |

## Scenario B — l'admin accorde l'accès

| Champ | Résultat |
|---|---|
| Chemin vérifié | Manifests + `make demo2-grant-access` |
| Observé | `MaaSSubscription` x2 + `MaaSAuthPolicy` actifs, `MaaSModelRef` prêt |
| Dashboard admin | Visualisation et suppression/recréation manuelles vérifiées en live |
| Conclusion | **PASS** |

## Scenario C — l'utilisateur crée une vraie clé API

| Champ | Résultat |
|---|---|
| Chemin vérifié | **Gen AI studio → API keys** |
| Observé | subscription visible, expiration max 90 jours, clé révélée une seule fois |
| Limitation réelle | le chemin `AI asset endpoints` est bloqué par un vrai `403` |
| Conclusion | **PASS** (API keys) / **BLOCKED** (AI asset endpoints) |

## Scenario D — inférence réelle

| Champ | Résultat |
|---|---|
| Chemin vérifié | `GET /v1/models` puis `POST /v1/chat/completions` |
| Observé | `200` puis `200`, vraie réponse, vrai bloc `usage` |
| Point important | le modèle doit être appelé avec son **id complet** `publishers/.../models/...` |
| Conclusion | **PASS** |

## Scenario E — tests négatifs

| Test | Attendu | Observé | Conclusion |
|---|---|---|---|
| E.1 Sans `MaaSAuthPolicy` | `403` | `403` sur l'inférence | **PASS** |
| E.2 Sans la subscription principale | docs laissent penser à `429` | `403` avec `requested subscription not found` | **PASS** avec vrai constat produit |
| E.3 Dépassement du petit quota | `429` | `429` après une séquence bornée de requêtes | **PASS** |

Point important : pour E.1, `GET /v1/models` peut rester en `200` avec une
liste vide. La preuve à montrer en live est donc l'appel d'inférence.

## Scenario F — visibilité de l'usage

| Vue | Observé | Conclusion |
|---|---|---|
| Utilisateur non-admin | voit la limite configurée et l'onglet `Models`, pas la consommation restante | **PASS** |
| Admin, métriques techniques | `make demo2-check-usage` montre les vrais compteurs Limitador | **PASS** |
| Admin, dashboard `Observe & Monitor → Usage` | l'onglet existe visuellement sur cette build mais peut rester à 0 même après vrai trafic | **FAIL** pour une vue fiable par utilisateur |

Détail utile : les métriques réelles portent des labels de subscription,
et `authorized_hits` porte aussi le modèle, mais pas de label utilisateur
exploitable pour alimenter correctement la vue `Usage` telle qu'elle est
requêtée sur cette build.

## Scenario G — révocation / régénération

| Champ | Résultat |
|---|---|
| Attendu doc | `401` après révocation |
| Observé | `403` après révocation |
| Régénération | une nouvelle clé repart immédiatement en `200` |
| Conclusion | **PASS** avec divergence réelle vis-à-vis de la doc |

## À retenir pour la démo live

- montrer le couple `Subscription` + `AuthPolicy`
- faire l'inférence depuis un vrai workbench utilisateur
- démontrer les `403` et `429` sur de vrais appels
- utiliser l'onglet `Models` comme vue observabilité fiable
- présenter l'onglet `Usage` comme une limite connue, pas comme une promesse produit
