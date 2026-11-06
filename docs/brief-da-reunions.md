# Brief DA : Aparté, « Affiche »

Choisi par Steven le 6 novembre 2026, parmi les pistes de `aparte-directions/v2` : la direction E
« Affiche », avec les pastilles de couleur par personne de la direction D. Ce brief remplace l'ancien
en entier : le grain, l'argile, la colonne encre, les libellés `//` et la chasse fixe partout sont
abandonnés. Les jetons vivent dans `Sources/DA/DA.swift`. Une vue n'utilise que ces jetons, jamais une
couleur ou une taille en dur.

## L'intention

Chaque réunion a sa une, comme un magazine : le titre devient l'image, et le compte rendu se lit comme
un article. On voit en trois secondes ce qui a été décidé et qui fait quoi.

- **Une affiche par réunion.** Un aplat de couleur porte le titre en New York Black, très grand. Au pied
  de l'aplat, la frise-règle du déroulé.
- **Une lecture éditoriale.** Le texte courant est en New York, avec des sections numérotées en chiffres
  romains, un chapô, et une marge pour tes notes.
- **Un seul moment d'audace en plus** : l'écran en réunion (à trancher par Steven : tout en couleur ou
  non).
- **Une app Mac native.** Polices du système, mode sombre, contrôles natifs (interrupteurs, menus),
  VoiceOver, et Réduire les animations respecté.

## Les couleurs

Chaque couleur a sa variante sombre. Les contrastes sont mesurés selon WCAG 2.x : 4,5:1 au minimum pour
le texte, 3:1 pour les grands textes et les objets graphiques.

| Jeton | Rôle | Clair | Sombre | Contraste (clair / sombre) |
|---|---|---|---|---|
| `papier` | fond de lecture | `#F4EFE5` | `#16140F` | |
| `marge` | marge, champs, citation | `#EAE3D5` | `#211E17` | |
| `texte` | texte courant | `#1B1915` | `#EFE8DA` | 15,3 / 15,1 sur papier |
| `texteDoux` | chapô, citations, détails | `#4D473D` | `#C0B7A6` | 8,0 / 9,3 |
| `texteDiscret` | horodatages, étiquettes | `#6B6457` | `#9C927F` | 5,1 / 6,0 ; **4,59** / 5,4 sur marge |
| `filet` | filets et séparations | `#D9D1C1` | `#37322A` | (décor) |
| `aplat` | l'affiche, les actions principales | `#1F35B5` | `#3149C9` | |
| `surAplat` | texte sur l'aplat | `#F4EFE5` | `#F4EFE5` | 8,2 / 6,3 ; à 80 % d'opacité : 5,8 / **4,58** |
| `lien` | lien, élément choisi | `#1F35B5` | `#8FA2FF` | 8,2 / 7,7 |
| `ocre` | numéros de section, échéances | `#8F5A12` | `#E0A64E` | 5,0 / 8,5 ; **4,52** / 7,7 sur marge |
| `direct` | l'enregistrement, une alerte | `#C8371B` | `#FF6A47` | **4,56** / 6,5 sur papier, jamais sur marge en clair |
| `selection` | ligne choisie | `#E3E4F2` | `#23253A` | texte 13,9 / 12,3 ; discret **4,64** / 4,9 |

`aplat` est **un jeton unique**. S'il faut une couleur par dossier, on la déclinera là, en mesurant
chaque couleur contre `surAplat` (au moins 4,5:1 à 80 % d'opacité).

## Les pastilles des personnes

Chaque responsable a une pastille ronde, de la même couleur dans toutes les réunions. La couleur dépend
du nom, par un hachage stable (`Pastille.couleurs(pour:)`), et l'initiale est écrite dedans. La
pastille n'apparaît que si le responsable a été dit (règle 1).

| Couleur | Fond | Initiale | Contraste |
|---|---|---|---|
| bleu | `#1D55E0` | blanc | 6,1 |
| orange | `#FF7A1A` | noir `#0A0A0A` | 7,6 |
| violet | `#6C3BEB` | blanc | 6,1 |
| vert | `#0E7A4E` | blanc | 5,4 |
| framboise | `#C81E5B` | blanc | 5,5 |
| moutarde | `#E8B21C` | noir | 10,2 |
| pétrole | `#0B6E7A` | blanc | 6,0 |

Le nom est toujours écrit à côté de la pastille : sa couleur aide à repérer la personne, elle ne
porte jamais seule l'information. En sombre, le bleu, le violet et le pétrole n'atteignent qu'environ
3:1 contre le papier, ce qui suffit pour un objet graphique.

## La typographie

Uniquement des polices du système, sans téléchargement.

| Jeton | Police | Usage |
|---|---|---|
| `Ecriture.une(taille)` | New York Black, 40 à 54 pt, interlignage serré | titre de la réunion sur l'aplat |
| `Ecriture.section` | New York Black 28 pt, numéro en italique `ocre` | « I Décidé », « II À faire » |
| `Ecriture.chapo` | New York italique 17 pt | le résumé « en bref » |
| `Ecriture.lecture` / `lectureForte` | New York 16 pt, regular ou semibold | décisions, actions, sujets |
| `Ecriture.personne` | New York Black italique 16 pt | le nom d'un responsable |
| `Ecriture.citation` | New York italique 14,5 pt | la citation ouverte, tes notes |
| `Ecriture.etiquette` | SF Pro Expanded semibold 10 pt, capitales, espacement 0,8 | les surtitres |
| `Ecriture.horodatage` | SF Pro Expanded medium 10,5 pt, chiffres tabulaires | toutes les heures |
| `Ecriture.interface` / `interfaceForte` | SF Pro 13 pt | boutons, interrupteurs, messages |

## L'espace et les formes

- **Grille de 4 pt** : `Espace.s1` (4), `s2` (8), `s3` (12), `s4` (16), `s6` (24), `s8` (32), `s10` (40).
- **Rayons** : `Rayon.petit` (4) pour les étiquettes et les blocs numérotés, `Rayon.moyen` (8) pour la
  citation ; les boutons sont en capsule.
- **Animations** : `Duree.courte` (0,15 s) pour une sélection, `Duree.moyenne` (0,25 s) pour ouvrir une
  citation. Rien ne bouge si Réduire les animations est activé.

## Le compte rendu

```
┌ barre latérale ┬────────────── aplat (l'affiche) ───────────────┬─ marge 320 pt ─┐
│                │ surtitre : dossier · date · horaire · durée      │ Garder sur     │
│                │ Titre en New York Black, éditable                │ ce Mac         │
│                │ Rédigé par Mistral · Copier · Refaire · Gérer    │ En suspens     │
│                │ ─┼──┼── frise-règle (0′ → durée) ──┼──┼─         │ Tes notes      │
│                ├──────────────────────────────────────────────────┤  ou            │
│                │ chapô (en bref)                                  │ Transcription  │
│                │ I Décidé    1  texte …………………………… 12:40      │                │
│                │ II À faire  ☐ ● Karim  texte  échéance  18:22    │                │
│                │ III Sujets, puis Qui parle                       │                │
└────────────────┴──────────────────────────────────────────────────┴────────────────┘
```

- **La frise-règle.** Une graduation par minute, plus longue tous les quarts d'heure, en `surAplat`.
  Au-dessus, à leur moment : les décisions en blocs numérotés, les actions en pastilles de personne,
  les questions en « ? ». Deux marques trop proches passent sur une seconde rangée. Cliquer une marque
  choisit l'élément.
- **Chaque ligne garde son horodatage** (règle 1), à droite, en `horodatage`. Cliquer la ligne ouvre la
  citation dessous, avec « Écouter ce passage » et « Voir dans la transcription ». Choisir ne lance
  jamais le son.
- **Qui a rédigé** est toujours visible sur l'aplat : « Rédigé par Mistral » ou « Rédigé sur ce Mac ».
  Si Mistral a échoué, une phrase le dit sous l'aplat.
- **L'interrupteur « Garder sur ce Mac »** est en haut de la marge. Si le dossier est gardé, il est
  activé, grisé, et une phrase dit pourquoi.
- **La marge** montre tes notes (jamais réécrites, règle 3) et « En suspens » (les questions). Elle
  bascule sur la transcription quand on la demande, ou quand on choisit une note ou un sujet.
- **Les états** : relecture et rédaction (une phrase et une barre de progression sur l'aplat), échec
  (la raison, puis « Rédiger le compte rendu »), pas encore de compte rendu, aucune phrase transcrite,
  compte rendu périmé (une ligne `ocre` sous l'aplat).

## Les textes

Les règles d'`AGENTS.md` :

- Tutoiement, phrases courtes.
- Le vocabulaire de Steven (« réunion », « dossier », « compte rendu »), jamais celui du code.
- Les titres en phrase normale. Les surtitres en capitales (`etiquette`), sans `//`.
- Un bouton dit ce qu'il fait : « Démarrer l'enregistrement », « Copier le compte rendu ».

## Encore à faire

L'accueil, l'écran en réunion, le dossier, les réglages et la barre latérale gardent l'ancienne DA
jusqu'à leur refonte, un écran à la fois. Les anciens jetons (`Color.creme`, `argile`, `Typo`,
`Libelle`, `GrainOverlay`, les polices embarquées) seront retirés avec le dernier écran qui s'en sert.
