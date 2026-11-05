# Validation du 5 novembre 2026

## Environnement observé

OpenShift 4.20.42, OpenShift AI 3.5.2, un GPU NVIDIA. Modèle réel `Qwen/Qwen2.5-0.5B-Instruct`, publié comme `maas-demo/demo-llm`. Les fichiers ont été téléchargés par le storage initializer et chargés par vLLM. Le seul pod actuel du modèle utilise le GPU ; le simulateur précédent a disparu au terme du rollout.

## Vérifications effectuées

- Manifestes acceptés par l'API en dry-run, plus validation de la syntaxe Bash/Python.
- Modèle Ready et rollout terminé ; publication MaaS Ready ; souscriptions et autorisation actives.
- Création de clés avec le token OAuth réel de `demo-user`, puis découverte et inférence avec ces clés, sans token admin pour les appels modèle.
- Cinq appels principaux en HTTP 200. Chaque réponse contient 107 tokens pour le prompt de test et la limite de sortie utilisés.
- Compteur `authorized_hits` de la souscription principale : **963 → 1 498**, soit **535 tokens**, exactement la somme des cinq réponses. Voir `evidence/token-proof.json` et les instantanés associés.
- Autorisation : retrait de `demo-team` des bénéficiaires → 403 ; restauration des bénéficiaires exacts → 200. Voir `evidence/access-test.json`.
- Petit quota : premier appel 200, suivant 429. Voir `evidence/quota.json`.
- Dashboard admin **MaaS démo** ouvert dans OpenShift AI : compteurs réels et courbe par souscription, capture dans `evidence/maas-observability.jpg`.
- Deux exécutions complètes du bootstrap après correction. La seconde conserve UID et génération de six Deployments vérifiés (modèle, gateway, PostgreSQL, MaaS API, Authorino, dashboard operator), le même pod modèle et le même contenu du secret PostgreSQL. Voir `evidence/idempotence.json`.
- Enregistrement des clés : essais isolés du script avec des valeurs fictives ; première saisie, conservation des clés avec Entrée, refus d'une entrée invalide et permissions 0600 vérifiés, sans modifier les clés réelles.
- Deux PDF régénérés et examinés visuellement : guide de préparation (5 pages), feuille de démo remaniée pour débutants (10 fiches/pages).

## Défauts corrigés

Le parcours principal utilisait toujours un simulateur CPU, même si l'on demandait un vrai modèle. Il utilise maintenant Qwen sur GPU, et le simulateur devient un choix explicite.

L'ancien guide présentait essentiellement des objets existants et un assistant à annuler. La nouvelle feuille décrit la création sur un état préparé : source, type de modèle, profil, répliques, options MaaS, groupe, limite, fenêtre temporelle et autorisation.

Une ancienne gateway issue d'un changement de GatewayClass portait le même sélecteur que la gateway active. Le Service envoyait une partie du trafic vers cette ancienne instance, d'où les échecs TLS intermittents. L'ancien Deployment a été réduit à zéro. Ce changement est propre à l'historique de cette sandbox.

Le dashboard natif Usage attend des noms et labels différents de ceux exportés ici. La nouvelle vue Perses interroge les compteurs réellement présents et ne fabrique pas de label utilisateur.

Les scripts ne valident plus un déploiement sur la seule présence d'un pod Running, ne redémarrent plus systématiquement l'opérateur dashboard, fusionnent la configuration de monitoring et ne réinitialisent plus un mot de passe Keycloak en cas de fichier local absent. Le nettoyage de démo conserve PostgreSQL, ses volumes et la gateway partagée.

## Portée et limites

La reconstruction complète a été rejouée sur la sandbox existante. Une installation intégrale sur une seconde sandbox vierge n'a pas été effectuée : la disponibilité des catalogues, versions, droits, certificats, GPU et du fournisseur d'identité reste à vérifier sur la cible.

Les formulaires admin ont été ouverts et remplis jusqu'au récapitulatif, puis annulés pour éviter un doublon. Le déploiement effectif a été réalisé par les manifestes. Les clés de validation ont été créées via l'API avec l'identité `demo-user`. Une vraie connexion navigateur avec ce même utilisateur a ensuite confirmé la souscription, le modèle, le quota et les clés actives. Le formulaire de création a été rempli (nom, description, souscription et date d'expiration), puis annulé puisque les clés nécessaires existaient déjà. Le bouton final de création graphique reste le geste à jouer pendant la démonstration. Les captures `user-subscription.jpg` et `user-key-form.jpg` montrent ces écrans sans secret.

**Anomalie de suppression d'autorisation observée :** après suppression de `demo-access`, l'inférence restait en 200 au-delà de deux minutes. La map `model_access` de l'AuthPolicy générée `maas-gateway-auth` contenait encore le modèle et `demo-team`. Le cache de 60 secondes ne suffit donc pas à expliquer ce résultat. Les chemins d'inférence générique et explicite ont tous deux répondu 200. La policy a été restaurée ; aucun correctif du contrôleur partagé n'a été improvisé. Voir `evidence/access-deletion-test.json`.

Le test livré modifie les bénéficiaires de la policy sans la supprimer : le contrôleur met alors à jour la règle, l'accès devient 403, puis revient en 200 après restauration. `make show-denials` vérifie ce comportement et restaure les bénéficiaires dans un bloc `finally`. Une suppression de policy ne doit pas être présentée comme un mécanisme de révocation validé sur cette build.

Le Llama préexistant `my-first-model/llama-32-3b-instruct` reste arrêté avec l'accord de l'utilisateur pour laisser le GPU à Qwen. Sa définition reste disponible. Les autres démonstrations présentes sur le cluster n'ont pas été nettoyées.

Le suivi par souscription est un compteur technique et une aide au showback. Le nombre de tokens n'est pas un coût financier ; la consommation par utilisateur/clé n'est pas disponible dans les séries observées. Le compteur se réinitialise au redémarrage de Limitador.
