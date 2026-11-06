# Pourquoi Cairn reste meilleur, et que faire d'Aparté

Claude Code, 6 novembre 2026, à la demande de Steven. Base : la même réunion enregistrée par les deux
apps le 5 novembre (« Vocal docu-mxh », 59 min), le code de Cairn (`~/Documents/GitHub/_Pause/Cairn`) et
celui d'Aparté (`main`, 26c98aa).

## Ce que montre la même réunion

| | Cairn | Aparté |
|---|---|---|
| Transcription | **Illisible.** « de chaque queliqué.-être pour toi », « ondance sur la pas tout le nombre de personnes » : presque aucune phrase n'a de sens | **Bonne.** « Maxime me disait que tu vis à côté de Paris, donc ça tombe bien aussi » : 375 segments lisibles, voix séparées et nommées |
| Qui rédige | Mistral (un gros modèle, en ligne) | Apple Intelligence, le petit modèle sur le Mac |
| Ce qui nourrit le compte rendu | **Tes notes**, puisque la transcription était inutilisable | La transcription, découpée en passages |
| Résultat | 6 points clés, 3 actions, 3 sujets. Court, propre, utile | 5 points clés, 3 décisions, 8 actions, 5 sujets, une citation sous chaque ligne |
| Qualité | Ce qui compte est là (NDA, éclairage, 4 interviews) | Du bruit pris pour des actions : « Être pris à 9h22 », « Arrêter de travailler avec ce personnage ». « Le contexte doit être fourni » est donné comme une décision |
| Règle 1 | Enfreinte : « (Steven) » sur le NDA et « 📅 2026-11-12 » sur l'éclairage n'ont été dits nulle part | Respectée : chaque ligne a sa source… mais une source ne rend pas une ligne pertinente |

**Le moteur de Cairn n'est pas meilleur.** Sur cette réunion, sa transcription est même bien pire.
Aparté a déjà repris la capture, la transcription et les consignes de rédaction de Cairn
(`docs/rapport-cairn.md`, `Sources/Analyse/Redaction.swift`), puis les a corrigées : son du Mac accéléré,
écho, voix, noms.

## Pourquoi Cairn paraît meilleur quand même

1. **Le rédacteur.** Mistral écrit bien, le petit modèle local non. Sur 59 minutes, le modèle d'Apple ne
   voit qu'un passage à la fois et ne sait pas ce qui compte dans toute la réunion.
2. **Les quotas poussent à remplir.** Aparté demande jusqu'à 2 décisions et 3 actions *par passage*. Sur
   une dizaine de passages, ça fait jusqu'à 30 candidats, et le modèle en trouve toujours. Cairn avait
   mesuré l'inverse : « laisse vide » et une seule lecture, et le modèle s'arrête de lui-même. La
   validation d'Aparté vérifie que la ligne a été dite, pas qu'elle compte. Le bruit passe donc.
3. **Tes notes ne servent pas d'appui.** Ce sont elles qui disent ce qui compte pour toi. Cairn s'en est
   servi, Aparté les met seulement à côté.
4. **La forme.** Cairn affiche une liste courte. Aparté met une citation brute de l'oral sous chaque ligne
   (« tiens, à 9h22, ») : c'est la preuve, mais elle salit la lecture.
5. **L'interface.** Cairn a un vrai système de design (« Laine » : couleurs OKLCH, contrastes mesurés,
   inspiré de Notion et Claude). Aparté s'est construit sur un brief chargé : libellés `//` en chasse fixe,
   angles carrés, grain, brun argile, colonne encre. Le résultat ressemble à un terminal, pas à l'outil
   calme qu'on voulait.
6. **La méthode.** Entre le 2 et le 6 novembre : 25 propositions, 9 agents nommés (Claude Code, Codex,
   Pickle, Luna, Panko, Dev, Biscuit, Miso, Lens), 17 dossiers de travail. 30 commits ont touché
   `Vues.swift`, et le tableau avait une dizaine de lignes « en relecture » en même temps. Personne n'a
   tenu le produit de bout en bout sur une vraie réunion avant d'ajouter la couche suivante.

## Les options

### A. Garder le moteur d'Aparté, refaire la rédaction et l'interface (recommandé)

- **Rédaction :** une seule synthèse de toute la réunion (les passages ne servent qu'à la préparer), sans
  quota, avec « laisse vide plutôt que deviner ». Tes notes servent d'ossature. Une action doit être un
  engagement : un verbe et quelqu'un qui s'engage, sinon elle est écartée.
- **Règle 1 gardée, mais discrète :** l'horodatage à côté de chaque ligne suffit. La citation s'ouvre au
  clic au lieu d'être imprimée partout.
- **Un rédacteur fort en un geste :** « Rédiger avec Mistral » mis en avant sur chaque réunion. Ça reste
  ta décision, réunion par réunion (règle 2). Voir la décision 2.
- **Interface :** refonte complète par l'agent design (voir plus bas).
- **Garde :** la capture, la transcription, les voix, le stockage en dossiers lisibles. C'est la partie
  d'Aparté qui marche, et mieux que Cairn.

Coût : la rédaction se fait en quelques jours. L'interface est le gros du travail.

### B. Reprendre le moteur entier de Cairn

À écarter. Il ramènerait la transcription qui a échoué le 5 novembre, l'iPhone, les carnets, et une
rédaction qui invente des responsables et des dates. Ce qui est bon chez Cairn (les consignes, la capture
`.aac`) est déjà dans Aparté.

### C. Revenir à Cairn et l'alléger

Option honnête, à ne pas oublier. Cairn fait plus (projets, tâches, iPhone) et tu l'utilises. Mais il fait
23 000 lignes, il est lourd à lancer, et il faudrait y reporter tout ce qu'Aparté a corrigé dans la capture.
Aparté, avec 6 000 lignes et un seul usage, est la base la plus saine pour un outil de réunion.

## Les décisions à prendre

1. **L'option** : A, B ou C. Recommandé : A.
2. **La règle 2 et le rédacteur.** Le petit modèle d'Apple ne rédigera jamais comme Mistral. Trois voies :
   - (a) tout en local, en acceptant un compte rendu plus maigre mais propre ;
   - (b) local par défaut, et « Rédiger avec Mistral » en un clic sur chaque réunion. Recommandé : c'est
     compatible avec la règle 2 telle qu'elle est écrite ;
   - (c) un réglage « Mistral pour toutes mes réunions », ce qui change la règle 2. À toi de voir.
3. **La règle 1 à l'écran** : la citation au clic plutôt qu'imprimée sous chaque ligne. Recommandé.
4. **La DA** : le brief actuel est remplacé par une nouvelle direction, inspirée de Revolut, Claude et
   Notion Calendar. L'agent design propose deux ou trois pistes en images, tu choisis, puis on réécrit le
   brief.
5. **La méthode** : toi et moi, plus l'agent design. Fin de Codex, d'OpenCode, du tableau et du plan des
   agents. `AGENTS.md` est mis à jour en ce sens dans cette branche.

## L'ordre proposé

1. La rédaction (option A) sur la réunion du 5 novembre, jusqu'à ce que le compte rendu soit au moins
   aussi utile que celui de Cairn. C'est le cœur du produit, et ça se mesure tout de suite.
2. En parallèle, l'agent design propose les directions. Tu en choisis une.
3. La refonte des écrans, un écran à la fois, en commençant par le compte rendu.
4. Un essai sur une vraie réunion avant chaque fusion.
