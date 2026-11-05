# Preuves de validation

- `wizard-review.jpg` : vrai formulaire admin rempli jusqu’au récapitulatif, puis annulé car le modèle existait déjà. Le déploiement effectif a été réalisé par le manifeste.
- `maas-observability.jpg` : capture réelle du dashboard admin pendant les essais, 963 tokens / 9 appels / 1 refus à cet instant. Les compteurs continuent ensuite à évoluer.
- `user-subscription.jpg`, `user-key-form.jpg` : session navigateur réelle demo-user ; souscription accessible et formulaire rempli, puis annulé (clés de validation déjà créées via API).
- `traffic.json`, `quota.json` : réponses mesurées avec les clés du compte non-admin demo-user.
- `token-proof.json`, `usage-before.json`, `usage-after.json` : rapprochement exact des tokens des réponses et du compteur Limitador.
- `access-test.json` : 403 après retrait du groupe des bénéficiaires et retour en 200 après restauration. Vérifier le résultat, pas seulement la présence du fichier.
- `access-deletion-test.json` : anomalie conservée, HTTP 200 malgré la suppression de la policy ; voir les limites documentées.
- `idempotence.json` : comparaison des ressources entre deux reconstructions.
- `validation.txt` : validation API des manifestes.

Aucune clé ni valeur de mot de passe n’est incluse. Les logs complets de bootstrap et les secrets sont ignorés par Git.
