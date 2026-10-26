# Demo 2 — Script parlé (10–12 min)

But : raconter Demo 2 simplement, sans vendre plus que ce que la
plateforme montre vraiment.

## Avant la salle

- `make demo2-verify`
- session admin prête
- session `maas-demo2-user` prête
- workbench utilisateur prêt si possible

## 0:00–1:00 — Cadre

> « Demo 1 a montré comment publier un modèle dans MaaS. Demo 2 répond à
> la question suivante : qui peut l'appeler, avec quelles limites, et que
> voit vraiment l'utilisateur final ? »

## 1:00–2:30 — Côté admin : la gouvernance

Montrer :
- `MaaSSubscription`
- `MaaSAuthPolicy`
- puis **Settings → MaaS governance**

À dire :

> « La subscription porte le quota. L'authorization policy porte le droit
> d'accès. Les deux sont nécessaires. »

## 2:30–4:00 — Côté utilisateur : la clé API

Montrer dans **Gen AI studio → API keys** :
- la subscription visible
- la création de clé
- l'expiration max 90 jours
- le fait que la valeur de clé n'est révélée qu'une fois

À dire :

> « Cette clé est liée à une subscription précise, et sa valeur ne peut
> pas être relue plus tard. »

## 4:00–6:00 — Inférence réelle depuis un workbench utilisateur

Montrer :
- `GET /v1/models` → `200`
- `POST /v1/chat/completions` → `200`
- vraie réponse + vrai `usage`

À dire :

> « On appelle le modèle avec la vraie identité utilisateur, pas avec un
> token admin déguisé. »

## 6:00–8:30 — Ce qui se passe quand la gouvernance casse

Montrer successivement :
- suppression de l'AuthPolicy → `403`
- suppression de la subscription principale → `403` `requested subscription not found`
- boucle avec la petite clé dédiée → `429`

À dire :

> « Les refus ne sont pas simulés. On touche les vrais objets de
> gouvernance, puis on fait un vrai appel HTTP. »

Point important à rappeler :
- pour la policy absente, la vraie preuve live est l'inférence
- `/v1/models` peut rester en `200` avec une liste vide

## 8:30–10:00 — Qui voit quoi comme usage

Montrer :
- onglet `Models` côté utilisateur ou admin
- éventuellement onglet `Usage` côté admin

À dire :

> « L'onglet Models est une bonne vue live. L'onglet Usage peut exister,
> mais rester à zéro sur cette build même après du vrai trafic. Donc on
> ne le vend pas comme une preuve de suivi par utilisateur. »

Si question technique hors pitch :

```bash
make demo2-check-usage
```

## 10:00–11:00 — Révoquer / régénérer

Montrer :
- révocation d'une clé
- réutilisation de cette clé → `403`
- création d'une nouvelle clé
- nouvel appel → `200`

À dire :

> « Sur cette version observée, une clé révoquée renvoie 403, pas 401.
> On vous donne le comportement réel, pas une paraphrase de la doc. »

## 11:00–12:00 — Conclusion

> « Cette démo montre un vrai modèle, un vrai utilisateur, de vraies
> règles de gouvernance et de vraies réponses HTTP. Les points forts sont
> réels, et les limites le sont aussi — notamment la visibilité d'usage
> par utilisateur sur cette build. »

## Si ça déraille

- revenir à `make demo2-verify`
- restaurer avec `make demo2-grant-access`
- regarder `docs/demo2/05-troubleshooting.md`
