# Réaliser une vidéo MaaS sans son

**Une vidéo lisible, avec de vrais gestes et des textes courts pour guider le spectateur.** Viser 8 à 10 minutes après montage, à partir d'une capture plus longue. Garder les étapes de remplissage des formulaires ; raccourcir les chargements et les hésitations.

## Choisir les outils et régler OBS

Sur ton poste Fedora avec GNOME/Wayland, utiliser **OBS Studio pour enregistrer l'écran**, puis **Kdenlive pour assembler les séquences et ajouter les textes**. Installer les versions stables depuis l'application **Logiciels**, en choisissant la source Flathub. Les sites officiels proposent aussi leurs liens d'installation : [OBS Studio](https://obsproject.com/download), [Kdenlive](https://kdenlive.org/download/).

Créer un dossier `maas-video` dans tes Vidéos, hors du dépôt Git. Il contiendra les captures originales et le montage.

**Dans OBS, préparer une capture locale :**

1. Au premier lancement, choisir l'usage **enregistrement** dans l'assistant. Il est aussi accessible via **Tools / Outils → Auto-Configuration Wizard**.
2. Dans **Scenes / Scènes**, créer `Demo MaaS`.
3. Dans **Sources → +**, choisir **Screen Capture (PipeWire)**, adapté à Wayland. Sélectionner l'écran destiné à la démo dans la fenêtre de partage.
4. Dans **Settings / Paramètres → Video**, viser un canevas et une sortie de **1920 × 1080**, à **30 images/seconde**. Si ton écran a une autre résolution, conserver les proportions ; des marges sont préférables à une image étirée ou à des champs coupés. Ne pas agrandir artificiellement une petite capture.
5. Dans **Output / Sortie**, mode **Simple**, choisir une qualité d'enregistrement élevée, par exemple **High Quality, Medium File Size** si proposée. Choisir le dossier `maas-video` et le format **MKV**.

Le choix d'une source et l'assistant sont décrits dans le [démarrage OBS](https://obsproject.com/kb/quick-start-guide). La [source PipeWire](https://obsproject.com/kb/display-capture-sources) est prévue pour Wayland. OBS recommande MKV pour mieux préserver un enregistrement interrompu ; la conversion de conteneur vers MP4 est disponible via **File → Remux Recordings**. [Réglages d'enregistrement OBS](https://obsproject.com/kb/standard-recording-output-guide)

**Rendre la capture muette avant de commencer :**

- Dans **Settings → Audio**, mettre les périphériques audio globaux **Desktop Audio** et **Mic/Auxiliary Audio**, y compris leurs variantes, sur **Disabled / Désactivé**.
- Ne pas ajouter de source de capture audio. Si une piste reste dans le mixeur, la mettre en sourdine.
- Faire un essai de 20 secondes avec une page et le terminal : cliquer **Start Recording**, puis **Stop Recording**, et lire le fichier. Vérifier la netteté et l'absence de son. OBS peut activer le bureau et le micro par défaut : ce réglage est nécessaire. [Audio et essai préalable](https://obsproject.com/kb/quick-start-guide)

## Préparer une image lisible et filmer par séquences

**Préparer les fenêtres :** navigateur normal pour **ADMIN**, navigateur privé pour **DATA SCIENTIST**. Agrandir chaque fenêtre quand elle est utilisée. Fermer messagerie et onglets inutiles, activer Ne pas déranger et garder OBS hors de l'écran filmé pendant les gestes.

**Rendre les champs lisibles :** partir d'un zoom navigateur de 110 à 125 %, puis vérifier qu'aucun bouton utile n'est coupé. Augmenter la police du terminal, par exemple à 18 points. Garder les mêmes dimensions de fenêtre pendant toute la capture. Faire le test en lisant le fichier vidéo à sa taille de présentation, pas seulement l'aperçu OBS.

**Montrer les actions avec un rythme régulier :**

- Amener le curseur sur le champ ou le bouton, attendre une seconde, puis agir.
- Laisser deux secondes après le remplissage d'un champ important.
- Garder chaque résultat visible quatre à cinq secondes : Ready, quota, HTTP 200, tokens.
- Conserver la saisie des champs à vitesse normale. Couper les longues attentes au montage, avec un texte comme **« Chargement du modèle - attente raccourcie »**.

**Enregistrer une séquence par chapitre :** cliquer **Start Recording**, réaliser la séquence, puis **Stop Recording**. Renommer les fichiers dans l'ordre, par exemple `01-projet.mkv`, `02-modele.mkv`, `03-gouvernance.mkv`. Une erreur impose seulement de refaire la séquence concernée. Au montage, retirer les instants où OBS revient à l'écran.

**Préparer les secrets hors capture :** lire le mot de passe avant de démarrer OBS, puis ouvrir un terminal neuf pour la démo. La connexion peut être filmée avec le champ Password masqué. Ne pas réutiliser la capture de terminal contenant le mot de passe en clair.

**Pour la clé API :** filmer le formulaire rempli, puis arrêter l'enregistrement **avant** de cliquer sur **Create API key**, car sa valeur apparaîtra ensuite. Créer et copier la clé hors capture, fermer la fenêtre qui l'affiche, puis reprendre sur la liste des clés actives. Ajouter le texte **« Clé créée et copiée hors enregistrement »**. Filmer ensuite `make save-key` : son collage est masqué. Ne jamais ouvrir le fichier de clé à l'écran.

La sandbox validée contient déjà les ressources de démo. Pour filmer leur création réelle, préparer l'état de départ décrit dans la [feuille de démo](https://github.com/Lindagh1/rhoai-maas-demo/blob/codex/maas-demo-pedagogique/FEUILLE-DEMO.md). Une vidéo de création doit montrer les champs, la validation et le résultat ; une simple inspection d'objets existants doit être annoncée comme telle.

## Suivre le scénario et ajouter les textes

Sans voix, chaque chapitre doit annoncer **qui agit**, **ce qu'il fait**, puis montrer **la preuve**. Utiliser les textes ci-dessous comme titres ou bandeaux. Ce sont des repères de montage, pas des durées obligatoires.

**Ouverture - environ 5 secondes**

Texte : **« Du modèle Hugging Face à une API gouvernée »**. Sous-titre : **« OpenShift AI - administrateur et data scientist »**.

**1. ADMIN - Créer le projet - environ 40 secondes**

Filmer le nom `maas-demo`, la description et Create. Texte : **« Un projet pour héberger notre assistant »**. Résultat : le projet ouvert.

**2. ADMIN - Déployer Qwen - environ 2 minutes**

Montrer l'URI Hugging Face, le profil GPU, les paramètres et Publish as MaaS. Texte : **« Les poids viennent de Hugging Face ; l'inférence tourne dans OpenShift »**. Couper le chargement en l'annonçant. Résultat : **Ready**.

**3. ADMIN - Souscription et autorisation - environ 1 minute 30**

Montrer `demo-team`, `demo-llm`, **2 000 tokens / minute**, puis `demo-access`. Textes : **« La souscription définit le budget »**, puis **« L'autorisation donne accès au modèle »**. Résultat : gouvernance active.

**4. DATA SCIENTIST - Accéder au service - environ 1 minute 30**

Montrer le passage à la fenêtre privée, le compte `demo-user`, sa souscription et les champs de création de la clé. Texte : **« Je crée une clé liée à ma souscription »**. Insérer la coupure expliquée pour la valeur secrète. Résultat : clé active dans la liste.

**5. DATA SCIENTIST - Enregistrer et appeler - environ 1 minute 30**

Filmer `make save-key`, le collage masqué, puis `make call` avec l'adresse MaaS. Texte : **« La clé est enregistrée localement, puis utilisée par le client »**. Résultat : **HTTP 200**, réponse et **total_tokens**. Ne pas accélérer cette partie : elle explique le geste à reproduire.

**6. ADMIN - Mesurer l'usage - environ 1 minute**

Montrer le compteur avant les appels, `make traffic`, puis le compteur actualisé après collecte. Texte : **« Les tokens des réponses sont comptabilisés par MaaS »**. Annoter l'écart réellement mesuré ; ne pas reprendre les chiffres d'une ancienne répétition.

**Fin - environ 5 secondes**

Texte : **« Un modèle déployé, un accès gouverné, une consommation mesurée »**. Le bonus **HTTP 429** peut ajouter 30 à 45 secondes si la limite de consommation est un message central.

## Monter dans Kdenlive et exporter sans audio

**Créer le montage :** ouvrir Kdenlive, choisir **File / Fichier → New / Nouveau**, puis un projet **1080p à 30 images/seconde** si c'est le format des captures. Enregistrer le projet dans `maas-video`. Ajouter les fichiers avec **Add Clip or Folder / Ajouter un clip ou un dossier**, puis les glisser dans l'ordre sur la piste vidéo **V1**. Le projet `.kdenlive` sauvegarde le montage ; le rendu crée la vidéo à partager. [Démarrage Kdenlive](https://docs.kdenlive.org/en/getting_started/quickstart.html)

**Retirer les temps morts :** raccourcir les débuts et fins des clips avec leurs bords. Pour une attente au milieu, couper de part et d'autre, retirer l'attente, puis rapprocher les deux morceaux. Conserver quelques secondes avant et après chaque résultat. Utiliser des coupes simples et cohérentes ; la vidéo doit rester facile à suivre.

**Ajouter les textes :** clic droit dans le **Project Bin / Chutier → Add Title Clip / Ajouter un clip titre**. Saisir un texte du scénario, cliquer **Create Title**, puis placer le titre sur **V2**, au-dessus de la capture. Un titre sur cette piste se superpose à la vidéo. Dupliquer le titre pour conserver sa mise en forme. [Titres Kdenlive](https://docs.kdenlive.org/en/titles_and_graphics/titles/titles.html)

Pour le style, utiliser une police simple, blanche sur un fond sombre, deux lignes maximum. Partir de 32 à 40 pixels pour un bandeau en 1080p, puis juger la lisibilité sur la vidéo exportée. Garder le texte quatre à six secondes ; prolonger s'il faut lire une commande. Placer le bandeau à l'écart du champ ou du résultat montré. Conserver **ADMIN** ou **DATA SCIENTIST** au début de chaque chapitre.

**Exporter la vidéo finale :**

1. Ouvrir **File → Render / Rendu**, ou **Ctrl + Entrée**.
2. Choisir **MP4-H264/AAC** et garder la résolution et la cadence du projet.
3. Dans **More Options / Plus d'options**, conserver **Video** coché et **décocher Audio**. Le fichier final ne contiendra ainsi aucune piste audio.
4. Nommer la sortie `demo-maas-sans-son.mp4`, puis cliquer **Render to File / Rendre vers un fichier**. [Options de rendu, vidéo et audio](https://docs.kdenlive.org/en/exporting/render.html)

**Dernier contrôle avant de partager :** lire le MP4 exporté du début à la fin. Les champs et commandes sont lisibles ; le rôle est clair ; les titres restent assez longtemps ; les chargements coupés sont signalés ; aucun secret n'apparaît, même brièvement ; le fichier est bien muet. Le spectateur doit comprendre le parcours sans commentaire oral.
