# Kit de redéploiement — Sopra Steria MaaS Demo (RHOAI 3.5)

**But de ce document :** permettre de reconstruire, sur une **nouvelle
sandbox** RHOAI 3.5, exactement l'environnement de démo actuel (Demo 1
native + Demo 2 parcours utilisateur gouverné), avec quelques commandes,
sans tout refaire manuellement.

Ce document distingue explicitement :
- ce qui a été **réellement déployé et vérifié en live** sur la sandbox
  actuelle (pas seulement discuté/prévu)
- ce qui est **automatisé** vs ce qui reste **volontairement manuel**
- les **paramètres qui varient** d'une sandbox à l'autre
- les **limites connues** de cette version (déjà documentées ailleurs,
  rappelées ici pour mémoire)

## 1. Inventaire — ce qui est réellement en place sur la sandbox actuelle

### 1.1 Opérateurs installés (vérifiés en live)

| Opérateur | Canal | Rôle |
|---|---|---|
| `rhods-operator` (Red Hat OpenShift AI) | `stable-3.x` | Plateforme RHOAI, DataScienceCluster |
| `rhcl-operator` (Red Hat Connectivity Link) | `stable-1.4` | Dépendance Kuadrant/Authorino |
| `authorino-operator` | `stable` | Autorisation (AuthPolicy) |
| `cluster-observability-operator` (COO) | `stable` | Stack d'observabilité (Prometheus/Perses) |
| `opentelemetry-product` (Red Hat build of OpenTelemetry) | `stable` | Collecteur OTel requis par COO |

Confirmé : **les deux opérateurs COO + OpenTelemetry sont nécessaires
ensemble** pour que `DSCInitialization.spec.monitoring` passe `Ready`.
COO seul ne suffit pas (`MissingOperator: OpenTelemetryCollector operator`).

### 1.2 Chaîne fonctionnelle Demo 1 (publication native)

```text
LLMInferenceService (llm-d, CPU llm-d-inference-sim)
        │  namespace applicatif: rhoai-maas-demo
        ▼
MaaSModelRef (demo-simulator)
        │  publie le modèle dans le tenant MaaS
        ▼
Modèle découvrable via GET /v1/models et appelable via
POST /v1/chat/completions, gouverné par Demo 2
```

Namespace applicatif du modèle : `rhoai-maas-demo`  
Namespace du tenant MaaS (gouvernance) : `models-as-a-service`  
Namespace infra MaaS (détecté dynamiquement, jamais codé en dur) :
`redhat-ai-gateway-infra` (via `MaasTenantConfig.status.infraNamespace`)

### 1.3 Chaîne fonctionnelle Demo 2 (parcours utilisateur gouverné)

```text
Groupe OpenShift maas-demo2-developers
   └─ utilisateur maas-demo2-user (non-admin, OIDC réel)
        │
        ▼
MaaSSubscription (quota : COMBIEN)         MaaSAuthPolicy (accès : QUI)
   maas-demo2-subscription                     maas-demo2-access
   maas-demo2-subscription-ratelimit-test
        │                                           │
        └──────────────── les deux requis ──────────┘
                         ▼
        Clé API utilisateur (créée via dashboard, jamais scriptée)
                         ▼
        Inférence réelle OpenAI-compatible, gouvernée (403 / 429 réels)
```

### 1.4 Artefacts créés manuellement via le Dashboard (à ne pas perdre)

| Objet | Namespace | Créé via | Script de reproduction |
|---|---|---|---|
| Workbench `data-scientist-workbench` | `rhoai-maas-demo` | Dashboard, Create workbench | **Manuel, volontairement** — voir §3 |
| Secret `demo2-api-key` | `rhoai-maas-demo` | `scripts/demo2/22-wire-workbench-api-key.sh` | Automatisable une fois le workbench créé |
| Clés API `demo2-main-key`, `demo2-ratelimit-key` | — (côté MaaS, scopées par subscription) | Dashboard, Gen AI studio → API keys | **Manuel, volontairement** — voir §3 |
| Groupe `maas-demo2-developers` + user `maas-demo2-user` | OpenShift (OAuth/Keycloak) | `scripts/demo2/01-create-test-identity.sh` | Automatisé |

### 1.5 Correctif réel capturé en live (drift cluster → repo)

Un vrai bug de plomberie observabilité a été diagnostiqué en live et
**n'était appliqué que sur le cluster, pas encore dans un manifeste
versionné** avant ce kit :

- Le Prometheus provisionné par le `MonitoringStack` de COO utilise un
  groupe d'API CRD **différent** (`monitoring.rhobs`) de celui des
  `PodMonitor` standards de la plateforme (`monitoring.coreos.com`), et
  n'a **aucun RBAC** pour lister des pods hors de son propre namespace.
- Conséquence : les métriques Limitador/`maas-api` n'étaient jamais
  scrapées, même avec un sélecteur `{}` censé tout matcher.
- Fix capturé dans `manifests/rhoai-operator/13-observability-rbac-podmonitors.yaml`
  (ClusterRole + RoleBindings namespace-scopés + miroirs `PodMonitor`
  sous `monitoring.rhobs/v1`), appliqué automatiquement par
  `scripts/25-enable-observability.sh`.

## 2. Paramètres qui varient entre sandboxes

Aucun de ces paramètres n'est codé en dur dans les scripts actifs — ils
sont détectés dynamiquement via `scripts/lib.sh` / `scripts/demo2/lib.sh`.

| Paramètre | Comment il est déterminé | Override possible |
|---|---|---|
| Domaine du cluster / hostname MaaS | `cluster_domain()` → `oc get ingresses.config.openshift.io cluster` | — (toujours dynamique) |
| Certificat TLS par défaut | `cert_name()` → ingress controller, fallback `router-certs-default` | — |
| Namespace infra MaaS | `infra_namespace()` → `MaasTenantConfig.status.infraNamespace`, fallback `redhat-ai-gateway-infra` | — |
| Fournisseur d'identité (Demo 2) | `detect_idp_strategy()` → `oauth/cluster` (htpasswd / Keycloak in-cluster / OIDC externe) | — |
| GPU disponible | `gpu_free_count()` → allocatable - requêtes réelles des pods | Si `0`, bascule automatique sur `llm-d-inference-sim` CPU |
| Nom/namespace du modèle Demo 2 | `DEMO2_MODEL_NAME` / `DEMO2_MODEL_NAMESPACE` | env var (défaut : `demo-simulator` / `rhoai-maas-demo`) |
| Utilisateur/groupe de démo | `DEMO2_USER` / `DEMO2_GROUP` | env var (défaut : `maas-demo2-user` / `maas-demo2-developers`) |
| Noms subscription/authpolicy | `DEMO2_SUBSCRIPTION` / `DEMO2_AUTHPOLICY` | env var |

Stockage : les PVC Postgres/modèle utilisent la `StorageClass` par
défaut du cluster cible — aucune classe nommée explicitement.

## 3. Ce qui est automatisé vs volontairement manuel

### Automatisé et idempotent (sans danger de relancer)

- Audit lecture seule (Demo 1 + Demo 2)
- Installation/activation des opérateurs et de MaaS
- Activation de l'observabilité (COO + OTel + fix RBAC/PodMonitor)
- Déploiement du modèle natif + publication MaaS
- Création de l'identité de test non-admin
- Application de la gouvernance (Subscription + AuthPolicy)
- Toutes les vérifications (`*-verify*`, `*-audit*`)

### Volontairement manuel (ne sera jamais scripté, par conception)

- **Création des clés API** côté utilisateur final — c'est le cœur de la
  démo (révélation one-shot dans le dashboard) ; scripter ça reviendrait
  à fabriquer un faux parcours utilisateur.
- **Création du Workbench** depuis le dashboard — le wiring interne
  (image, PVC, sidecar `kube-rbac-proxy`, ServiceAccount, HTTPRoute) géré
  par RHOAI n'a jamais été reproduit depuis du YAML brut dans ce projet ;
  seul le **patch** d'un Workbench déjà créé est automatisé
  (`scripts/demo2/22-wire-workbench-api-key.sh`).
- **Révocation/régénération de clé** côté utilisateur (Étape 6 du guide
  live) — c'est littéralement le geste UI qu'on démontre.

## 4. Reconstruire sur une sandbox neuve

### Pré-requis

```bash
oc login --server=<API> --token=<TOKEN>   # fait par toi, jamais collé dans le chat
git clone <ce repo>
cd rhoai-maas-demo
```

### Tout en une fois

```bash
bash scripts/bootstrap-redeployment.sh
```

Options :

```bash
bash scripts/bootstrap-redeployment.sh --demo1-only
bash scripts/bootstrap-redeployment.sh --demo2-only
bash scripts/bootstrap-redeployment.sh --skip-observability
```

Le script s'arrête au premier échec réel (chaque étape sous-jacente est
elle-même idempotente — relancer le script reprend sans tout refaire).

### Étapes manuelles restantes (affichées à la fin du script)

1. Se connecter au dashboard RHOAI en tant que `maas-demo2-user`
   (mot de passe dans `secrets/demo2/maas-demo2-user.password`)
2. **Gen AI studio → API keys → Create API key** — deux fois :
   - une clé scopée à `maas-demo2-subscription`
   - une clé scopée à `maas-demo2-subscription-ratelimit-test`
3. Capturer les deux clés sans jamais les coller ailleurs :
   ```bash
   make demo2-capture-keys
   ```
4. Vérifier que tout est vert :
   ```bash
   make demo2-verify
   ```
5. (Optionnel, pour l'Étape 3bis du guide live) créer un Workbench depuis
   le dashboard, puis :
   ```bash
   bash scripts/demo2/22-wire-workbench-api-key.sh <namespace> <notebook-name> secrets/demo2/maas-demo2-user.apikey
   ```

### Validation sans toucher au cluster

À tout moment, y compris sur un cluster déjà en place, pour vérifier que
le kit est cohérent avec les CRDs réellement disponibles **sans rien
muter** :

```bash
bash scripts/validate-redeployment.sh
```

## 5. Manifestes orphelins — à ne surtout pas réutiliser

`manifests/maas/maas-subscription.yaml` et
`manifests/maas/maas-auth-policy.yaml` appartiennent à un **ancien
sandbox** (`t5lkh`) et accordent un accès **public** à tout utilisateur
authentifié (`system:authenticated`). Ils ne sont **pas appliqués** sur
la sandbox actuelle (vérifié : `NotFound`) et ne font pas partie de ce
kit. La vraie gouvernance, scopée au groupe `maas-demo2-developers`, est
dans `manifests/demo2/10-*`/`11-*`/`12-*`.

## 6. Limites connues de cette version (rappel)

Déjà documentées en détail dans `docs/demo2/05-troubleshooting.md` et
`DEMO2-RESULTS.md` — rappel synthétique :

- Une clé API révoquée renvoie `403`, pas le `401` documenté.
- Supprimer la subscription d'une clé renvoie `403` "subscription not
  found", pas `429`.
- L'onglet **Observe & Monitor → Dashboard → Usage** peut rester à `0`
  même après du vrai trafic : les métriques Limitador n'exposent pas de
  label `user` exploitable sur cette build. L'onglet **Models** est en
  revanche fiable, y compris côté utilisateur non-admin.
- Le chemin "AI asset endpoints" pour une clé temporaire est bloqué par
  un vrai `403`, même pour un propriétaire de projet.
- L'étape "Environment variables" du wizard de création de Workbench ne
  s'applique pas toujours réellement (voir §3 et le script de patch
  dédié).

## 7. Sécurité — rappels non négociables

- Aucun secret en clair n'est jamais committé (`secrets/` est dans
  `.gitignore`).
- Aucune clé API n'est jamais collée dans le chat, dans un log, ou dans
  un argument de commande visible.
- Aucun token `oc login` n'est jamais réutilisé littéralement dans une
  commande tracée si une session valide existe déjà (`oc whoami`
  suffit à vérifier).
- Tout token/clé exposé par erreur (collé dans le chat, visible sur une
  capture d'écran) doit être considéré compromis et régénéré.
