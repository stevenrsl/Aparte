# Aparté

App Mac de notes et d'enregistrement de réunions, avec une analyse en local. Elle remplace Cairn.
macOS 27 au minimum.

Avant de travailler, lis ces documents. Ils font foi, dans cet ordre :

1. [La fiche](docs/fiche-reunions-2026-11.md) : le périmètre, les règles, les chantiers.
2. [L'étude Cairn / Aparté](docs/etude-cairn-aparte.md) : pourquoi on refait la rédaction et
   l'interface (6 novembre 2026).
3. [Le brief DA](docs/brief-da-reunions.md) : la direction artistique. Il est en refonte : l'ancienne
   DA (`//`, chasse fixe, angles carrés, grain) n'est plus la référence.

## Les trois règles

1. **Rien n'est inventé.** Chaque décision, action ou question de l'analyse pointe vers des
   horodatages de la transcription. Un élément sans source vérifiable n'est pas affiché. Un
   responsable ou une échéance n'apparaît que s'il a été dit.
2. **Rien ne quitte le Mac sans que Steven l'ait choisi.** L'audio ne quitte jamais le Mac. Par
   défaut, la transcription et les notes partent chez Mistral pour rédiger le compte rendu (décidé
   par Steven le 6 novembre 2026). Le modèle local rédige quand il n'y a pas de clé ou pas de réseau,
   quand Mistral échoue, ou pour une réunion ou un dossier marqués « Garder sur ce Mac ». L'écran dit
   toujours qui a rédigé. Aucune télémétrie, aucun autre envoi.
3. **Les notes de Steven ne sont jamais réécrites.** L'analyse s'ajoute à côté.

Pas de base de données, pas de compte utilisateur.

## Comment travailler

- **Steven veut être accompagné, pas remplacé.** Une décision « À Steven », ou un choix qui engage la
  suite (structure, dépendance, version de macOS) : arrête-toi, présente les options avec une
  recommandation, attends sa réponse. Ne tranche rien dans le code « en attendant ».
- Si une demande va contre la fiche ou le brief, dis-le avant de l'exécuter.
- **Steven et Claude Code, seuls** (décidé par Steven le 6 novembre 2026). Plus de Codex, d'OpenCode,
  de tableau ni de plan des agents. Claude Code confie l'interface à un seul agent spécialisé,
  [design-aparte](.claude/agents/design-aparte.md), et relit ce qu'il produit.
- **Une tâche, une branche.** La branche porte le nom de la tâche. L'agent design travaille dans son
  propre dossier (`git worktree`), jamais dans celui de Claude Code.
- **Un commit par sujet**, avec un message en français, court.
- **Chaque branche se termine par une proposition** au format de
  [.github/pull_request_template.md](.github/pull_request_template.md), avec les rendus des écrans
  touchés. Steven tranche.
- **Personne ne fusionne dans `main` sans l'accord de Steven**, donné pour cette branche.
- **Un essai sur une vraie réunion** avant de fusionner un changement de la rédaction.
- **Le projet Xcode est créé par Steven.** Le code vit dans le package Swift. Aucun agent ne modifie
  `project.pbxproj`.
- **Pas de nouvelle dépendance** sans l'accord de Steven.
- Toute nouvelle règle va dans ce fichier, nulle part ailleurs.

## Les textes de l'interface

- Tutoiement, phrases courtes.
- Le vocabulaire de Steven (« réunion », « dossier », « compte rendu »), jamais celui du code.
- Les libellés `//` en minuscules, les titres en phrase normale.
- Un bouton dit ce qu'il fait : « Démarrer l'enregistrement », « Copier le compte rendu ».
