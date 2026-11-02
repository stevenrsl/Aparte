# Brief DA : l'outil de réunions

Rédigé le 2 novembre 2026. À lire avec la [fiche de travail](fiche-reunions-2026-11.md) avant toute
session qui touche à l'interface. La référence visuelle est la rangée « Définitive » du canvas
*Réunions — directions DA* (six écrans, de l'accueil aux réglages). Si ce brief et le canvas
divergent, montrer l'écart à Steven plutôt que trancher.

## L'intention

Un outil qu'on ouvre en pleine réunion client et qui se fait oublier. Calme, chaud, organique,
avec un seul moment d'audace : l'enregistrement en cours. La DA mêle quatre sources que Steven a
validées une à une :

- **la structure de Lisière** : deux colonnes franches, alignées sur les mêmes filets ;
- **l'esprit des pixels** (direction « Mistral ») : angles carrés, libellés en chasse fixe avec
  « // », une colonne sombre ;
- **le chrono de Signal** : chiffres matriciels et niveaux sonores en points ;
- **la conversation de Galets** : la transcription en bulles, eux à gauche, moi à droite.

Le tout dans la palette argile de Steven, avec du grain sur toute l'interface.

## La fenêtre

Tous les écrans partagent la même charpente. Ne pas la casser d'un écran à l'autre.

| Zone | Mesure | Contenu |
|---|---|---|
| Barre de titre | 42 pt, fond `surface` | Feux de la fenêtre ; à droite, au besoin, un réglage en `mono` |
| Barre latérale | 228 pt, fond `surface`, filet à droite | Logo, Accueil, Toutes les réunions, la réunion en cours s'il y en a une, les dossiers, Réglages en bas |
| Colonne principale | le reste | En-tête de 172 pt, puis le contenu |
| Colonne encre | 420 pt, fond `encre`, collée au bord droit, pleine hauteur | En-tête de 172 pt (chrono, source, chiffres), puis la transcription ou une liste |

- Les deux en-têtes font **exactement 172 pt** et se ferment sur le même filet. C'est ce qui donne
  l'alignement que Steven a demandé ; rien ne doit flotter ni avoir de marge propre.
- Marges intérieures : 36 pt dans la colonne principale, 28 pt dans la colonne encre (24 pt pour la
  transcription en bulles).
- Séparations par **filets de 1 pt**, jamais par des ombres ou des cartes.
- **Angles carrés partout.** Seuls les feux de la fenêtre sont ronds.
- La bande de pixels en haut de la fenêtre a été **retirée** par Steven. Ne pas la remettre.

## Les couleurs

La palette de Steven, plus quelques valeurs dérivées pour la lisibilité et le mode sombre. À
déclarer en couleurs d'asset avec une variante claire et une variante sombre.

### Clair

| Token | Valeur | Rôle |
|---|---|---|
| `creme` | `#F5EEE6` | Fond de la colonne principale |
| `surface` | `#E9D8C9` | Barre latérale, barre de titre, puces d'horodatage, encadrés |
| `encre` | `#40332D` | Texte, colonne sombre, bouton principal, élément sélectionné |
| `terracotta` | `#A65F46` | Aplats seulement : curseur de saisie, repère du résumé, carré du logo, carré de l'enregistrement |
| `terracotta-texte` | `#8E4E38` | Terracotta pour du texte : horodatages des notes, italique des titres, liens |
| `argile` | `#D4A88B` | Le signal sur fond encre : enregistrement, « Terminer », mes bulles, puce active |
| `encre-douce` | `#6E5A50` | Texte secondaire, libellés `//` |
| `filet` | `#DCC7B6` | Filets sur fond crème |
| `champ` | `#FBF7F2` | Fond des champs de saisie |

### Sur la colonne encre (identique en clair et en sombre)

| Token | Valeur | Rôle |
|---|---|---|
| `colonne-texte` | `#F5EEE6` | Texte courant |
| `colonne-doux` | `#E9D8C9` | Texte secondaire |
| `colonne-signal` | `#D4A88B` | Libellés `//`, horodatages, signal |
| `bulle-eux` | `#54443C` | Fond des bulles des autres participants |
| `colonne-filet` | `#5A4A42` | Filets et cases vides de la barre de progression |
| `chrono-repos` | `#A08A7D` | Chrono à `00:00`, avant l'enregistrement |

### Sombre

| Token | Valeur |
|---|---|
| `creme` → fond | `#2A211D` |
| `surface` | `#231B18` |
| `encre` (texte) | `#F5EEE6` |
| `encre` (colonne, boutons) | `#40332D` |
| `encre-douce`, `terracotta-texte` | `#D4A88B` |
| `filet` | `#4A3C35` |
| `champ` | `#231B18` |

### Règles

- **Le terracotta est rare.** Un ou deux aplats par écran au plus. Il ne passe pas en petit texte
  sur la crème (4,3:1) : utiliser `terracotta-texte`.
- **Sur la colonne encre, le signal est l'argile**, jamais le terracotta (illisible).
- Sur un aplat argile, le texte est `encre`, jamais crème.
- Tout texte respecte 4,5:1 (3:1 au-dessus de 24 pt) dans les deux thèmes.
- Pas de dégradés, pas d'ombres portées, pas d'emoji.

## La typographie

| Rôle | Police | Taille | Notes |
|---|---|---|---|
| Titre d'écran | New York | 38 pt, interligne 1,05 | La fin du titre en italique `terracotta-texte` (« Point montage, *documentaire voile* ») |
| Titre de section | New York italique | 22 pt | « *Mes notes* », « *Transcription* » |
| Titre de réunion dans une liste | New York | 20 pt | |
| Résumé du compte rendu | New York | 20 pt, interligne 1,5 | Précédé d'un trait terracotta de 3 pt |
| Texte courant | Zalando Sans | 14 pt ; 16 pt pour les notes | Interligne 1,45 à 1,55 |
| Libellé | JetBrains Mono | 11 pt, approche +0,02 em | En minuscules, préfixé par `//` : « // décisions » |
| Horodatage | JetBrains Mono | 11 pt | `04:12`, `22:20 · moi` |
| Chrono et grands chiffres | Doto 800 | 68 pt (chrono), 52 à 56 pt (source, compteurs) | Chiffres tabulaires, interligne 0,82 |

- **New York est une police système** : rien à embarquer, `Font.system(.title, design: .serif)`.
- **Zalando Sans, JetBrains Mono et Doto sont à embarquer** dans l'app. Les trois sont sous licence
  libre sur Google Fonts : garder leur fichier de licence dans le repo.
- Pas de quatrième famille. Doto ne sert qu'aux chiffres.

## Le grain

Il rend l'interface organique. Il doit se sentir, pas se voir.

- Une **texture de bruit** en niveaux de gris, générée une fois (256 × 256 px, se répète sans
  couture), posée par-dessus toute la fenêtre.
- Clair : fusion **multiplication**, opacité **16 %**. Sombre : fusion **écran**, opacité **8 %**.
- En SwiftUI : une `Image` en mosaïque en `.overlay`, `.blendMode(…)`, `.allowsHitTesting(false)`.
  Pas de shader recalculé à chaque image.
- Désactivé quand « Augmenter le contraste » ou « Réduire la transparence » est actif dans les
  réglages d'accessibilité de macOS.

## Les composants

- **Libellé `//`** : JetBrains Mono 11 pt, `encre-douce` (ou `colonne-signal` sur l'encre).
- **Puce d'horodatage** : fond `surface`, texte `encre`, carrée. Active : fond `argile`, texte
  `encre`. Un clic ouvre la source.
- **Élément sélectionné** (décision, dossier, entrée de la barre latérale) : bloc `encre`, texte
  crème, petit carré argile de 7 pt devant.
- **Bulles de transcription** : carrées. Eux à gauche sur `bulle-eux`, texte crème ; moi à droite
  sur `argile`, texte encre. Phrase en cours de transcription : bordure argile en tirets, sans fond.
  Bulle source d'une décision : filet argile de 3 pt à gauche.
- **Chrono** : Doto 68 pt, avec à côté les niveaux de Moi (points argile) et d'Eux (points crème).
  Pas de clignotement.
- **Niveaux sonores** : colonnes de points de 5 pt (7 pt pour le test du micro).
- **Barre de progression d'écoute** : rangée de carrés pleins argile, vides `colonne-filet`.
- **Case à cocher** : carré de 14 pt, bordure 2 pt.
- **Boutons** : principal en aplat `encre`, texte crème ; signal en aplat `argile`, texte encre, sur
  la colonne encre uniquement ; secondaire en bordure 1 pt, fond transparent. Carrés, sans ombre.
- **Logo provisoire** : carré de 2 × 2 pixels (encre, terracotta, argile, encre) suivi du nom en
  New York.

## Les écrans

1. **Accueil** : salutation, réunions récentes (date, titre, résumé en une ligne, dossier, nombre
   de décisions et d'actions). Colonne encre : démarrage rapide (Visio ou Présentiel, ⌘N) et
   « À faire suite aux réunions », chaque action renvoyant au moment où elle a été dite. C'est une
   liste à cocher, pas un gestionnaire de tâches.
2. **Nouvelle réunion** : titre, dossier, type, micro, analyste. Colonne encre : test du micro et du
   son du Mac, bouton « Démarrer l'enregistrement » (⌘↩). Le rappel de prévenir les participants
   est un encadré, jamais une fenêtre de confirmation.
3. **En réunion** : mes notes horodatées à gauche ; chrono, niveaux et transcription en bulles à
   droite.
4. **Compte rendu** : résumé, décisions, actions, question ouverte, chacune avec sa puce de source.
   Colonne encre : écoute du passage source, l'échange en bulles, ma note à ce moment.
5. **Dossier** : le fil chronologique des réunions du dossier, les dernières décisions avec leur
   source, le nombre d'actions ouvertes. **Un dossier n'est qu'un dossier sur le disque** : pas de
   statut, pas d'échéance, rien à gérer. (La fiche de travail est à mettre à jour sur ce point :
   elle ne prévoyait pas de dossiers.)
6. **Réglages** : analyste par défaut, micro, emplacement des réunions. Colonne encre : ce qui
   quitte le Mac, en clair (l'audio jamais, la transcription seulement sur choix, aucune
   télémétrie).

## Les textes de l'interface

- Tutoiement, phrases courtes, le vocabulaire de Steven (« réunion », « dossier », « compte
  rendu »), jamais celui du code.
- Les libellés `//` en minuscules ; les titres en phrase normale.
- Un bouton dit ce qu'il fait : « Démarrer l'enregistrement », « Copier le compte rendu ».

## À Steven

- **Le nom de l'app** et donc le vrai logo. Le carré de pixels est provisoire.
- **L'icône de l'app** : à dessiner une fois le nom choisi, dans la même palette.
- **L'intensité du grain** : 16 % est un point de départ, à juger sur son écran réel.
