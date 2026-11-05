# Fiche de travail : Aparté, l'outil de réunions qui remplace Cairn

Rédigée le 2 novembre 2026, à lire avant toute session sur ce projet. Elle fait suite au tri des
projets du même jour et à une discussion avec Steven sur ce qu'il gardait de Cairn.

## Ce qui a été décidé

- **Cet outil remplace Cairn.** Cairn est archivé, pas en pause. On ne reconstruit pas Cairn en plus
  petit : on garde l'organe qui servait vraiment, les réunions.
- **Il s'appelle Aparté** (`Aparte` dans le code et le repo), dans un nouveau repo privé :
  `stevenrsl/Aparte`.
- **macOS 27 au minimum.** C'est la première version qui offre PCC et les fournisseurs externes dans
  le framework Foundation Models.
- **Une note n'existe qu'attachée à une réunion.** Pas de notes libres, pas de projets, pas de tags.
  C'est la règle qui empêche de refaire une usine à gaz.
- **Des dossiers, et rien de plus.** Une réunion peut être rangée dans un dossier (un client, un
  tournage). Un dossier n'est qu'un dossier sur le disque : pas de statut, pas d'échéance, rien à
  gérer. L'écran dossier montre le fil des réunions, leurs décisions et les actions ouvertes.
- **Mac d'abord.** Puis, si elle est retenue, la détection de réunion. Puis Apple Calendar (lecture
  seule), puis l'iPhone, une fois l'outil éprouvé sur de vraies réunions. Apple Notes en dernier, et
  seulement par une action Raccourcis.
- **La DA est fixée** dans le [brief DA](brief-da-reunions.md), à lire avant tout travail
  d'interface.
- **Claude Code et Codex travaillent ensemble** selon le [plan des agents](plan-agents.md).
- **Deux usages dès la v1** : les visios (micro et son du Mac) et les réunions en présentiel
  (micro seul).
- **L'analyse se fait en local par défaut.** Private Cloud Compute (PCC) est autorisé, ainsi qu'un
  fournisseur externe (Claude, ChatGPT ou Mistral). Le choix se fait réunion par réunion, par
  Steven.
- **On part du code de transcription de Cairn**, que Steven juge « plutôt » propre, et pas d'un
  projet tiers comme meetily (autre pile, pas Apple Intelligence).

## Comment travailler avec Steven

Steven veut être accompagné, pas remplacé. Chaque chantier ci-dessous a ses décisions marquées
**À Steven** : les présenter avec les options et une recommandation, puis attendre sa réponse.
Ne pas les trancher dans le code « en attendant ».

Un commit par sujet, sur une branche par chantier.

## Les trois règles

1. **Rien n'est inventé.** Chaque décision, action ou question de l'analyse pointe vers un ou
   plusieurs horodatages de la transcription. Un élément sans source vérifiable n'est pas affiché.
   Un responsable ou une échéance n'apparaît que s'il a été dit.
2. **Rien ne quitte le Mac sans une action de Steven.** L'audio ne quitte jamais le Mac. La
   transcription n'en sort que lorsque Steven lance une analyse avec PCC ou un fournisseur externe
   pour cette réunion précise. Aucune télémétrie, aucun envoi automatique, aucun fournisseur
   externe par défaut.
3. **Les notes de Steven ne sont jamais réécrites.** L'analyse s'ajoute à côté, elle ne modifie
   pas ce qu'il a tapé.

Le conseil de Rushes s'applique aussi ici : pas de base de données, pas de compte utilisateur.

## Les chantiers

### 0. Le nom et le repo

**Décidé par Steven le 2 novembre 2026 :**
- Le nom : Aparté.
- Un nouveau repo, dans lequel on copie le module de transcription de Cairn une fois relu. Un fork
  élagué aurait été plus rapide, mais on aurait hérité du reste.

### 1. Relire et extraire la transcription de Cairn

- Lire le code de transcription de Cairn avant d'en copier une ligne. Repérer ce qu'il utilise
  (`SpeechAnalyzer`/`SpeechTranscriber` ou une API plus ancienne), comment il gère la locale
  française, les permissions et l'horodatage des segments.
- Faire à Steven un court rapport : ce qui est sain, ce qui est fragile, ce qu'on réécrit.
- Extraire un module autonome, testé sur un fichier audio de référence (une vraie réunion
  enregistrée, avec l'accord des participants). Ce fichier reste hors du repo : le test lit son
  chemin en local et se saute s'il est absent. Un extrait relu par Steven sert de vérité pour juger
  le texte obtenu.

### 2. La capture audio

- Le micro avec `AVAudioEngine`, le son du Mac avec un *process tap* Core Audio (macOS 14.4 et
  plus).
- **Deux pistes séparées** plutôt qu'un mixage : la piste micro, c'est Steven, la piste système,
  ce sont les autres. On obtient ainsi en visio un « moi / eux » gratuit, sans diarisation. En
  présentiel, tout passe par le micro.
- **Les voix, l'écho et les noms, repris de Cairn** (décidé par Steven le 2 novembre 2026, ce qui lève
  le « hors v1 » sur les voix, et accorde la dépendance FluidAudio). Après la réunion, Aparté relit
  l'enregistrement sur le Mac : voix séparées en présentiel et sur le son du Mac, que Steven nomme, écho du
  haut-parleur marqué sur la piste du micro, noms connus corrigés. La transcription du direct reste dans
  `transcription-direct.json`. Les modèles (21 Mo) se téléchargent une fois depuis Hugging Face, sans rien
  envoyer de l'enregistrement.
  **Décidé par Steven le 3 novembre 2026 :** dans le doute, l'écho reste dans la transcription qui sert de
  preuve plutôt que d'être retiré, quitte à voir parfois des doublons dans le compte rendu. Il est marqué
  « écho probable », sur toute la ligne, pour qu'un vrai « non » ne disparaisse jamais.
- Un indicateur d'enregistrement toujours visible. Les permissions (micro, capture audio)
  demandées au premier enregistrement, avec une phrase claire.
- **Le consentement** : une ligne discrète dans la vue d'enregistrement rappelle de prévenir les
  participants. Pas de fenêtre de confirmation.

**Décidé par Steven le 2 novembre 2026 :** le choix de l'entrée est prévu dès la v1, pour pouvoir
brancher un micro externe en présentiel. C'est peu de travail.

### 3. Le stockage

Un dossier par réunion, lisible sans l'app, rangé dans le dossier choisi (ou à la racine si
aucun) :

```
Documentaire voile/
  2026-11-04 Point client/
    meta.json           titre, date, durée, participants si saisis, fournisseurs utilisés
    micro.m4a
    systeme.m4a         seulement en visio
    transcription.json  segments horodatés, piste d'origine
    notes.md            les notes de Steven, chaque ligne horodatée
    analyse.json        la dernière analyse, avec ses sources
    analyse.md          la même, lisible
    analyses/           les analyses précédentes, si on en relance une avec un autre fournisseur
```

**À Steven :** l'emplacement (dans `~/Documents/Aparté/` ou un dossier de son choix). Recommandation :
un dossier choisi au premier lancement, qu'il peut mettre dans iCloud Drive s'il le veut. Ça
reste son choix, pas une synchro de l'app.

**Décidé par Steven le 2 novembre 2026 :** une réunion se renomme, se déplace entre dossiers et se met à la
Corbeille depuis l'app, après confirmation pour la Corbeille. Son dossier sur le disque suit, et rien
de ce qu'elle contient n'est réécrit, sauf le titre dans `meta.json`.

### 4. Les notes pendant la réunion

- Un éditeur texte simple à côté de la transcription en direct. Chaque ligne reçoit l'horodatage
  du moment où elle est commencée.
- C'est le cœur de l'idée de Granola : **les notes servent d'ancres**. L'analyse regarde en
  priorité les passages autour de ce que Steven a noté.
- Pas de mise en forme riche en v1 : du Markdown simple.

### 5. L'analyse

- Une seule interface `Analyste`, plusieurs fournisseurs :
  - **Local** (Foundation Models sur l'appareil) : la fenêtre de 4 096 tokens est partagée entre
    l'entrée et la sortie. On découpe la transcription en segments d'environ cinq minutes, on
    produit une structure `@Generable` par segment, puis une synthèse des segments.
  - **PCC** : retiré de l'app (décidé par Steven le 2 novembre 2026), car il faut une autorisation
    `com.apple.developer.private-cloud-compute` qu'Apple accorde sur demande. À reprendre une fois accordée.
  - **Externe** : l'API du fournisseur choisi, en une fois. La clé est rangée dans le trousseau,
    jamais dans le repo ni dans un fichier.
  - **Analyse automatique** (demandée par Steven le 2 novembre 2026) : après la relecture, une réunion sans
    analyse est analysée toute seule, en local seulement. L'externe reste toujours lancé
    par Steven, réunion par réunion, après confirmation.
  - Vérifié le 2 novembre 2026 : le framework Foundation Models accepte d'autres modèles par le
    protocole `LanguageModel`, à partir de macOS 27. Chaque fournisseur peut livrer un package
    Swift. Apple cite Anthropic et Google ; rien de trouvé pour ChatGPT ou Mistral, où il faudrait
    sans doute écrire l'adaptation nous-mêmes. Vérifier ce qui existe vraiment au moment du
    chantier, avant d'écrire nos propres clients HTTP.
- **Une sortie commune** quel que soit le fournisseur : résumé, décisions, actions, questions
  ouvertes. Chaque élément porte ses horodatages sources et, si possible, la phrase exacte.
- **Une validation après coup** : un élément dont les horodatages n'existent pas ou dont la phrase
  est introuvable dans la transcription est écarté (règle 1).
- **« En bref » est rédigé par le modèle** (décidé par Steven le 2 novembre 2026, à la place du seul résumé construit) :
  deux ou trois phrases, comme dans Cairn. Une reformulation peut se tromper : l'écran dit qui l'a rédigée,
  chaque phrase garde ses sources, et une phrase qui nomme une personne, un chiffre ou un moment absent de
  ses lignes est retirée. Sans phrase valide, le résumé construit revient.
- **Chaque élément est reformulé, avec sa citation dessous** (décidé par Steven le 5 novembre 2026, à la place de
  la citation seule retenue le 2 novembre, après l'essai sur une vraie réunion de 59 minutes : 59 « décisions » illisibles
  face aux 3 actions de Cairn). Une phrase courte à la façon de Cairn, puis la phrase entière de la transcription, qui
  reste affichée comme preuve. Une reformulation peut se tromper : le modèle doit donner le numéro de la ligne qui la
  prouve, sans quoi l'élément est écarté, et elle laisse place à la citation si elle nomme une personne, un chiffre ou un
  moment absent de ce passage, ou si elle change le sens d'une négation. Ce contrôle ne prouve pas qu'elle dit vrai : la
  citation dessous permet de vérifier d'un coup d'œil. Plafonds : 8 décisions, 10 actions, 6 questions, 5 points clés.
- **Les sujets et les points clés** (sujets demandés par Steven le 2 novembre 2026, repris de Cairn ; rédaction étendue
  le 5 novembre 2026 avec la décision ci-dessus) : au plus 8 sujets, titrés par le modèle, chacun avec ses points et leurs
  sources. Un titre avec un nom, un chiffre ou un moment jamais dit devient son premier point.
- **Répartir une réunion** (demandé par Steven le 2 novembre 2026) : Steven choisit un dossier par sujet, et chaque
  dossier reçoit un extrait sans audio. La réunion d'origine ne change pas. Un extrait est une réunion
  marquée `origine`, faute de « notes libres », hors v1.
- Seule la transcription et les notes partent chez un fournisseur. Jamais l'audio.
- L'analyse affiche le fournisseur qui l'a produite.

**Décidé par Steven le 2 novembre 2026 :** le fournisseur externe de la v1 est Mistral. Faute de package pour le
protocole `LanguageModel`, un client HTTP, d'après celui de Cairn. Le modèle y choisit des numéros de
lignes, comme en local : le texte rendu reste celui de la transcription.

**À Steven :**
- Le fournisseur par défaut quand on clique « Analyser ». Recommandation : local, toujours, avec
  un menu pour en choisir un autre.

### 6. Relire l'analyse

- Un clic sur une décision ou une action affiche le passage de la transcription et relit l'audio
  à ce moment-là.
- C'est ce qui rend la règle 1 vérifiable par Steven, pas seulement par le code.

### 7. L'export

- Le Markdown est déjà sur le disque. Ajouter « Copier le compte rendu » (résumé, décisions et
  actions, sans la transcription), prêt à coller dans un mail ou dans Notion.

## Hors v1

Notes libres, projets, tags, synchro par l'app, recherche
entre réunions, base de données, compte. Chacun peut revenir plus tard, mais seulement si l'usage
le réclame.

Prévus après la v1, dans cet ordre, et dessinés sur le canvas (sauf la détection de réunion) :

1. **La détection de réunion** : quand une app de visio prend le micro, Aparté le signale et propose
   de démarrer en un clic, **jamais d'enregistrement automatique**. Ne couvre pas le présentiel.
   L'app doit rester active en arrière-plan, et il faut éviter les fausses alertes (la dictée, par
   exemple). **À Steven** : la retenir ou non, à décider après le jalon de l'étape 2, une fois une
   vraie réunion enregistrée.
2. **Apple Calendar** : lecture seule des calendriers choisis ; titre, participants et dossier
   proposés d'après l'événement ; un rappel au début de l'événement, **jamais d'enregistrement
   automatique**.
3. **iPhone** : pensé pour le présentiel, avec une Live Activity. **À Steven** : la synchro passe
   forcément par le dossier des réunions dans iCloud Drive, donc les réunions quittent le Mac.
4. **Apple Notes** : une action Raccourcis qui envoie le compte rendu seulement (ni audio ni
   transcription). Pas d'interface officielle d'Apple pour écrire dans Notes : ne pas bâtir
   dessus.

## Les questions encore ouvertes

- La détection de réunion, à décider après le jalon de l'étape 2.

## L'ordre

| Étape | Quoi | Jalon |
|---|---|---|
| 1 | Relecture et extraction de la transcription de Cairn | Le rapport à Steven |
| 2 | Capture sur deux pistes, stockage, notes horodatées | Une vraie réunion enregistrée, sans analyse |
| 3 | Analyse locale découpée, validation des sources, relecture | Un compte rendu dont chaque ligne se vérifie |
| 4 | PCC et le fournisseur externe | La même réunion analysée par les trois, comparée |
| 5 | Export, finitions | Cairn n'est plus ouvert |

## Arbitrages V0.5 — décision de Steven du 2026-11-05

Ces choix remplacent les indications antérieures correspondantes :
- Un clic sélectionne et montre le passage sans lancer le son. Seul « Écouter ce passage » lance l'écoute.
- Le démarrage est en haut de la barre latérale : modes Visio et Présentiel explicites, « Préparer » secondaire. En réunion, ce bloc montre le titre, « Enregistrement en cours », le chrono et le retour, sans second démarrage.
- Le titre du compte rendu contient uniquement le nom de la réunion ; le dossier figure dans le lien de retour. Pas de virgule en italique ni de titre automatiquement proposé par le modèle en V0.5.

Le grand chrono reste réservé à l'enregistrement. Dans le compte rendu, le repère compact « Passage à 04:12 » accompagne « Écouter ce passage » (arbitrage technique de Pickle, 2026-11-05).
