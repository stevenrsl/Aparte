# Plan : Claude Code et Codex sur le même projet

Rédigé le 2 novembre 2026. À lire avec la [fiche de travail](fiche-reunions-2026-11.md) et le
[brief DA](brief-da-reunions.md). Ce plan dit qui fait quoi, et comment deux agents travaillent sur
le même repo sans se marcher dessus.

## Le principe

Deux agents qui codent la même chose en même temps, c'est des conflits et deux versions d'une même
idée. Ici, chacun a un rôle :

- **Claude Code est l'atelier.** Il construit les chantiers de la fiche, dans l'ordre, un par un.
- **Codex est le relecteur et l'artisan.** Il relit chaque proposition de Claude Code au regard des
  règles, écrit les tests *avant* le code quand c'est possible, et prend des tâches **isolées**,
  bien bornées, qui ne touchent pas le chantier en cours.
- **Steven est le chef de projet.** Il tranche les décisions « À Steven », fusionne les branches, et
  teste sur de vraies réunions. Aucun agent ne fusionne dans `main`.

Chaque agent relit le travail de l'autre. Personne ne valide son propre code.

## Les fichiers communs

| Fichier | Lu par | Rôle |
|---|---|---|
| `AGENTS.md` | Codex, et Claude Code via `CLAUDE.md` | Les règles permanentes : les trois règles de la fiche, le style, la façon de travailler, ce plan en résumé |
| `CLAUDE.md` | Claude Code | Une ligne `@AGENTS.md` et, au besoin, ce qui ne concerne que Claude Code |
| `docs/fiche-reunions-2026-11.md` | les deux | Le périmètre et les chantiers |
| `docs/brief-da-reunions.md` | les deux | La DA |
| `docs/plan-agents.md` | les deux | Ce plan |
| `docs/tableau.md` | les deux | Qui travaille sur quoi, en ce moment |
| `.github/pull_request_template.md` | les deux | Le format de chaque proposition |

Une seule source de vérité pour les règles : `AGENTS.md`. `CLAUDE.md` l'importe au lieu de le
recopier, pour que les deux agents lisent exactement la même chose.

## Le tableau

`docs/tableau.md` évite que les deux agents prennent la même tâche.

```markdown
| Tâche | Agent | Branche | État | Fichiers touchés |
|---|---|---|---|---|
| Relire la transcription de Cairn | Claude Code | `relecture-cairn` | en cours | docs/rapport-cairn.md |
| Module DA (couleurs, typo, grain) | Codex | `da-tokens` | en relecture | Sources/DA/ |
```

- Un agent **inscrit sa tâche avant de commencer**, avec les dossiers qu'il va toucher.
- Il ne prend pas une tâche dont les fichiers recoupent une ligne « en cours » de l'autre.
- Il passe la ligne à « en relecture » quand il ouvre sa proposition, et Steven la retire après la
  fusion.

## Les règles de travail

- **Une tâche, une branche, un agent.** Les branches portent le nom de la tâche.
- **Un commit par sujet**, des messages en français, courts.
- **Les décisions « À Steven » ne se tranchent jamais dans le code.** L'agent qui en rencontre une
  s'arrête, la présente avec les options et une recommandation, et attend.
- **Le projet Xcode est créé par Steven.** Le code vit dans un package Swift (`Package.swift`) que
  l'app importe. Aucun agent ne modifie `project.pbxproj`.
- **Pas de nouvelle dépendance** sans l'accord de Steven.
- Les trois règles de la fiche s'appliquent à tout : rien n'est inventé, rien ne quitte le Mac sans
  action de Steven, ses notes ne sont jamais réécrites.

## Le format d'une proposition

Chaque branche se termine par une proposition (pull request) avec quatre parties :

1. **Ce qui est fait**, en quelques lignes.
2. **Comment le tester**, pas à pas, y compris sur une vraie réunion si besoin.
3. **Les décisions « À Steven » rencontrées**, avec la recommandation.
4. **Ce qui reste**, ou ce qui a été volontairement laissé de côté.

L'autre agent relit avec une question : la proposition respecte-t-elle la fiche, le brief et les
trois règles ? Ses remarques vont dans la proposition. Steven fusionne quand les deux sont
d'accord, ou tranche quand ils ne le sont pas.

## La structure du code

Un package Swift, découpé pour que deux agents puissent travailler en parallèle sans toucher les
mêmes fichiers :

| Module | Contenu | Chantier |
|---|---|---|
| `Transcription` | Transcription en direct, segments horodatés | 1 |
| `Capture` | Micro et son du Mac, deux pistes | 2 |
| `Stockage` | Dossiers, réunions, lecture et écriture des fichiers | 2 |
| `Analyse` | L'interface `Analyste`, les fournisseurs, la validation des sources | 3 et 4 |
| `DA` | Couleurs, typographie, grain, composants de base | en parallèle |
| `Interface` | Les écrans SwiftUI | au fil des chantiers |

## Qui fait quoi, chantier par chantier

| Étape | Claude Code | Codex, en parallèle |
|---|---|---|
| 0. Mise en place | `AGENTS.md`, `CLAUDE.md`, `docs/tableau.md`, le modèle de proposition, le squelette du package | Relit la mise en place |
| 1. Transcription de Cairn | Lit le code de Cairn, écrit le rapport, extrait le module `Transcription` | Écrit les tests du module à partir du rapport |
| 2. Capture et stockage | Modules `Capture` et `Stockage`, écran « En réunion » | Module `DA` d'après le brief : couleurs clair et sombre, polices embarquées, texture de grain |
| 3. Analyse locale | Découpage, synthèse, écran « Compte rendu » | Écrit **d'abord** les tests de la validation des sources (un élément sans horodatage réel est écarté), que Claude Code fait passer |
| 4. PCC et fournisseur externe | Branchement dans l'interface, choix réunion par réunion | Les clients des fournisseurs externes, la clé dans le trousseau |
| 5. Finitions | Accueil, dossiers, réglages | Export Markdown, « Copier le compte rendu », relecture d'accessibilité (contrastes, VoiceOver) |

Ce partage est un point de départ. Si un chantier s'avère plus simple ou plus long que prévu,
Steven réattribue dans le tableau.

## Ce qui ne marche pas avec deux agents

- **Leur faire coder la même fonctionnalité pour comparer.** Ça double le travail et la relecture.
  Si Steven veut comparer deux approches, il le demande explicitement, sur deux branches nommées.
- **Les laisser se relire en boucle.** Une relecture, une correction, puis Steven tranche.
- **Leur donner des consignes différentes.** Toute nouvelle règle va dans `AGENTS.md`, nulle part
  ailleurs.

## À Steven

- **La plateforme de relecture** : les propositions sur GitHub (Codex peut relire une pull request
  qu'on lui confie), ou en local, en passant les branches d'un agent à l'autre. Recommandation :
  GitHub, pour garder une trace de chaque décision.
- **Le rythme** : un chantier à la fois côté Claude Code, avec au plus une tâche Codex en parallèle.
