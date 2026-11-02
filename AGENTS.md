# Aparté

App Mac de notes et d'enregistrement de réunions, avec une analyse en local. Elle remplace Cairn.
macOS 27 au minimum.

Avant de travailler, lis ces documents. Ils font foi, dans cet ordre :

1. [La fiche](docs/fiche-reunions-2026-11.md) : le périmètre, les règles, les chantiers.
2. [Le brief DA](docs/brief-da-reunions.md) : la direction artistique, avant tout travail d'interface.
3. [Le plan des agents](docs/plan-agents.md) : qui fait quoi, Claude Code et Codex.

## Les trois règles

1. **Rien n'est inventé.** Chaque décision, action ou question de l'analyse pointe vers des
   horodatages de la transcription. Un élément sans source vérifiable n'est pas affiché. Un
   responsable ou une échéance n'apparaît que s'il a été dit.
2. **Rien ne quitte le Mac sans une action de Steven.** L'audio ne quitte jamais le Mac. La
   transcription n'en sort que lorsque Steven lance une analyse avec PCC ou un fournisseur externe,
   pour cette réunion précise. Aucune télémétrie, aucun envoi automatique, aucun fournisseur externe
   par défaut.
3. **Les notes de Steven ne sont jamais réécrites.** L'analyse s'ajoute à côté.

Pas de base de données, pas de compte utilisateur.

## Comment travailler

- **Steven veut être accompagné, pas remplacé.** Une décision « À Steven », ou un choix qui engage la
  suite (structure, dépendance, version de macOS) : arrête-toi, présente les options avec une
  recommandation, attends sa réponse. Ne tranche rien dans le code « en attendant ».
- Si une demande va contre la fiche ou le brief, dis-le avant de l'exécuter.
- **Claude Code dirige Codex.** Il répartit les tâches, rédige les consignes de Codex et lui confie
  les relectures. Steven reste le chef de projet : il tranche les décisions « À Steven » et fusionne.
  Codex garde un avis indépendant quand il relit : un désaccord remonte à Steven.
- **Le tableau :** inscris ta tâche dans [docs/tableau.md](docs/tableau.md) avant de commencer. Passe
  la ligne à « en relecture » quand tu ouvres ta proposition.
- **Une tâche, une branche, un agent.** La branche porte le nom de la tâche.
- **Chaque agent travaille dans son propre dossier** (un clone ou un `git worktree`), jamais dans
  celui de l'autre. Ne change pas de branche dans un dossier qui n'est pas le tien.
- **Un commit par sujet**, avec un message en français, court.
- **Chaque branche se termine par une proposition** au format de
  [.github/pull_request_template.md](.github/pull_request_template.md). L'autre agent la relit au
  regard de la fiche, du brief et des trois règles : une relecture, une correction, puis Steven
  tranche.
- **Aucun agent ne fusionne dans `main`**, et personne ne valide son propre code.
- **Le projet Xcode est créé par Steven.** Le code vit dans le package Swift. Aucun agent ne modifie
  `project.pbxproj`.
- **Pas de nouvelle dépendance** sans l'accord de Steven.
- Toute nouvelle règle va dans ce fichier, nulle part ailleurs.

## Les textes de l'interface

- Tutoiement, phrases courtes.
- Le vocabulaire de Steven (« réunion », « dossier », « compte rendu »), jamais celui du code.
- Les libellés `//` en minuscules, les titres en phrase normale.
- Un bouton dit ce qu'il fait : « Démarrer l'enregistrement », « Copier le compte rendu ».
