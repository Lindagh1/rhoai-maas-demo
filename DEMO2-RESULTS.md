# Demo 2 Results — MaaS End-User Journey (RHOAI 3.5)

**Sandbox:** OpenTLC disposable sandbox  
**Identity provider verified live:** in-cluster Keycloak / OpenShift OAuth  
**Model under test:** Demo 1's `demo-simulator`  
**Test identity:** `maas-demo2-user` in `maas-demo2-developers`

Statuts : **PASS** / **FAIL** / **BLOCKED** / **NOT TESTED**.

## Résumé exécutif

Demo 2 est **globalement démontrable et reproductible** sur une sandbox
neuve via ce repo.

Les points solides :
- accès gouverné par `MaaSSubscription` + `MaaSAuthPolicy`
- création de clé utilisateur réelle
- inférence OpenAI-compatible réelle
- refus réels `403` et `429`
- révocation/régénération réelle d'une clé
- observabilité fiable via l'onglet `Models` et les compteurs Limitador

Le point faible à annoncer honnêtement :
- la vue `Observe & Monitor → Usage` peut exister mais rester à `0` ou
  partielle malgré du vrai trafic ; ce n'est pas la bonne preuve live à
  utiliser pour un suivi par utilisateur sur cette build

## Tableau des scénarios

| Scenario | Statut | Notes |
|---|---|---|
| A — utilisateur sans subscription | **PASS** | L'utilisateur ne peut pas créer de clé exploitable |
| B — admin accorde l'accès | **PASS** | Manifests idempotents + visualisation dashboard admin |
| C — création de clé via API keys | **PASS** | Flow utilisateur fonctionnel |
| C — clé temporaire via AI asset endpoints | **BLOCKED** | vrai `403`, ne pas utiliser ce chemin |
| D — inférence réelle | **PASS** | `GET /v1/models` = `200`, `POST /v1/chat/completions` = `200` |
| E.1 — suppression AuthPolicy | **PASS** | vrai `403` sur l'inférence |
| E.2 — suppression subscription | **PASS** | vrai `403` `requested subscription not found` |
| E.3 — dépassement de quota | **PASS** | vrai `429` |
| F — visibilité usage côté utilisateur | **PASS** | limite visible, pas de consommation réelle |
| F — métriques admin via Limitador | **PASS** | bonne source de vérité technique |
| F — dashboard admin `Usage` | **FAIL** | écran visible mais pas fiable sur cette build |
| G — révocation / régénération de clé | **PASS** | révocation observée en `403`, nouvelle clé OK |

## Divergences réelles par rapport à la doc

1. Une clé révoquée renvoie `403`, pas `401`.
2. Supprimer la subscription principale d'une clé renvoie `403`, pas `429`.
3. `AI asset endpoints` n'est pas utilisable ici pour la génération de clé.
4. L'appel d'inférence doit utiliser l'**id complet** du modèle.
5. L'onglet `Usage` n'est pas une source fiable de visibilité par utilisateur sur cette build.

## Recommandation de démonstration

Pour une démo client claire et robuste :
- montrer la gouvernance dans le dashboard admin
- créer la clé dans le dashboard utilisateur
- faire l'appel depuis un vrai workbench utilisateur
- prouver les `403` et `429` avec de vrais appels
- montrer l'onglet `Models`
- traiter l'onglet `Usage` comme une limite connue, pas comme une preuve produit

## Références utiles

- guide live : `docs/GUIDE-DEMO-LIVE-DEMO2.md`
- reproduction sandbox neuve : `docs/demo2/06-new-sandbox-reproduction.md`
- troubleshooting : `docs/demo2/05-troubleshooting.md`
- matrice détaillée : `docs/demo2/04-test-scenarios.md`
