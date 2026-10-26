# Demo 2 — Repartir proprement sur une sandbox neuve

Ce document est le chemin le plus simple pour retrouver une sandbox
présentable, sans deviner quelles étapes sont optionnelles.

## Objectif

Sur une sandbox RHOAI 3.5 neuve, on veut pouvoir :
- installer Demo 1
- préparer Demo 2 de manière idempotente
- obtenir un état vérifiable avant la démo
- garder la partie utilisateur finale (création/révocation de clé) comme un vrai geste humain dans le dashboard

## Prérequis

- session `oc login` cluster-admin
- `bash`, `make`, `curl`, `python3`, `dig`
- dépôt cloné localement

## Chemin nominal

### 1. Installer Demo 1

```bash
make demo1-all
```

Ce target inclut désormais l'observabilité nécessaire pour que les
onglets **Observe & Monitor** soient déjà prêts avant Demo 2.

### 2. Auditer Demo 2 avant toute mutation

```bash
make demo2-audit
```

À faire sur chaque nouvelle sandbox. Ce script dit :
- quel IdP est présent
- si `maas-demo2-user` et `maas-demo2-developers` existent déjà
- si les objets de gouvernance Demo 2 existent déjà
- si les secrets locaux attendus existent déjà

### 3. Créer l'identité de démo

```bash
make demo2-create-identity
```

Ce script est idempotent mais touche l'infra d'identité. Sur une sandbox
jetable dédiée à la démo, c'est le bon chemin. Sur un environnement
partagé d'entreprise avec un IdP externe, il faut s'arrêter et suivre
`docs/demo2/09-auth-oidc-entra.md`.

### 4. Accorder l'accès MaaS

```bash
make demo2-grant-access
```

Ce target :
- valide les manifests par `--dry-run=server`
- applique la subscription principale
- applique la petite subscription dédiée au test de rate limit
- applique l'authorization policy

### 5. Vérifier l'état cible avant la salle

```bash
make demo2-verify
```

C'est la commande de vérité. Elle doit être verte avant toute répétition
ou démo live.

## Étapes volontairement manuelles

### 6. Créer la clé utilisateur réelle

Cette étape doit rester humaine, car c'est justement la valeur de la
Demo 2.

En session `maas-demo2-user` :
1. **Gen AI studio → API keys**
2. créer une clé pour `maas-demo2-subscription`
3. capturer sa valeur dans `secrets/demo2/maas-demo2-user.apikey`
4. créer aussi une clé pour `maas-demo2-subscription-ratelimit-test`
5. la stocker dans `secrets/demo2/maas-demo2-user.ratelimit.apikey`

Rappel : ne jamais coller une valeur de clé dans le chat ni dans une
commande shell visible à l'écran.

### 7. Jouer le parcours live

Suivre ensuite :
- `docs/GUIDE-DEMO-LIVE-DEMO2.md` pour la version présentatrice
- `docs/demo2/08-presentation-script.md` pour le script parlé

## Ce qui est automatisé vs non automatisé

### Automatisé et idempotent

- installation de Demo 1
- enablement de l'observabilité dashboard
- création de l'identité de démo sur sandbox compatible
- application de la gouvernance MaaS
- vérifications de cohérence

### Manuel par design

- création de clé API côté utilisateur
- révocation/régénération de clé
- navigation dashboard montrée au client

## Ce qu'il faut annoncer honnêtement sur une sandbox neuve

- L'onglet **Models** dans `Observe & Monitor` fonctionne bien et vaut le détour.
- L'onglet **Usage** peut exister visuellement mais rester vide ou partiel,
  même après du vrai trafic.
- Les compteurs admin fiables restent ceux de Limitador (`make demo2-check-usage`).
- Une clé révoquée renvoie `403` sur cette build observée, pas `401`.
- `AI asset endpoints` n'est pas le bon chemin pour la clé de cette démo.

## Si on veut tout remettre à zéro côté Demo 2

```bash
make demo2-cleanup-access CONFIRM=yes
```

Cela supprime uniquement les objets de gouvernance Demo 2. Le modèle de
Demo 1 et l'identité restent en place.
