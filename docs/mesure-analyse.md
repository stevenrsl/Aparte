# Mesure de l'analyse locale

Mesuré le 2 novembre 2026, sur macOS 27, avec le modèle local d'Apple Intelligence. Cinq fausses
réunions inventées, écrites dans `Tests/AnalyseTests/MesureOublisTests.swift`, avec 20 éléments attendus,
lancées deux fois :

```sh
APARTE_MESURE=2 swift test --filter mesureOublis
```

| Sur 40 éléments attendus | Citation recopiée par le modèle | Lignes choisies et confirmées |
|---|---|---|
| Trouvés et bien rangés | 18 | 30 |
| Trouvés mais mal rangés | 5 | 6 |
| Manqués | 17 | 4 |
| Éléments en trop | 49 | 16 |
| Écartés par la validation | 9 | 0 |

## Ce qui a changé

- Le modèle ne recopie plus de phrase : il choisit des numéros de lignes, donc le texte rendu est
  toujours celui de la transcription.
- Une passe par catégorie, puis une seconde lecture de chaque ligne retenue, avec ses voisines.
- Pas de tirage au hasard : la même réunion donne le même compte rendu.
- Une ligne de moins de 4 mots n'est jamais retenue.

## Les limites de cette mesure

- **Les réunions et les consignes ont le même auteur.** Les phrases sont propres et les chiffres sont
  sans doute meilleurs que sur une vraie réunion. Ils comparent deux méthodes, ils ne promettent rien.
- **Vraie réunion de référence (9 min) :** 12 décisions, 3 actions, 3 questions, aucun passage perdu.
  Ce sont des nombres seuls : personne n'a encore relu si ces éléments sont justes, et 12 décisions
  semblent beaucoup.
- Un élément en trop reste une citation exacte : c'est son classement qui est faux, pas ses mots.
- La seconde lecture retire plus d'éléments en trop, mais elle a aussi fait perdre 2 éléments sur 40.
