# Logo et icône de l'app

Branche `logo`, posée sur `main` (V0.3) : un commit de code, un commit pour cette proposition.

## Ce qui est fait

- L'icône : cinq colonnes de points (2, 4, 6, 4, 2) sur un carré `encre`. Les points sont argile,
  la colonne centrale est crème. C'est la piste « niveaux sonores », choisie par Steven.
- `Support/Icone/generer-icone.swift` dessine l'icône avec AppKit, sans dépendance. Il produit le
  carré plein de 1024 px (`Support/Icone/icone-1024.png`) et l'`iconset` qui donne
  `Support/Aparte.icns`.
- `build.sh` copie l'`.icns` dans le bundle et `Info.plist` le déclare (`CFBundleIconFile`).
- Le logo de la barre latérale reprend les mêmes colonnes en petit (`LogoApparte`, `Sources/DA/DA.swift`),
  suivies du nom en New York.
- Le brief DA et le tableau sont à jour.

## Comment le tester

1. `./build.sh debug`, puis ouvre `build/Aparté.app`.
2. Regarde l'icône dans le Finder et le Dock, puis le logo en haut de la barre latérale.
3. En clair et en sombre : le carré `encre` du logo doit rester visible sur le fond sombre.
4. Pour régénérer l'icône : `swift Support/Icone/generer-icone.swift <dossier>`.

## Les décisions « À Steven » rencontrées

- **Le vrai logo et l'icône** : tranché, piste 2.
- **L'icône dans Xcode.** `icone-1024.png` est un carré plein, car macOS applique son arrondi. Le
  projet Xcode est le tien : recommandation, la glisser dans l'asset d'icône quand tu le crées.
  L'`.icns` de `build.sh` est arrondi à la main, seulement pour le bundle d'ici là.

## Ce qui reste

- Le logo de la barre latérale n'a pas été vérifié à l'écran, ni en mode sombre.
- Le contraste des points argile sur `encre` n'a pas été mesuré. Il vient des tokens du brief, mais
  ce sont des éléments graphiques (3:1 attendu).
- Aucune version monochrome (barre des menus, impression).
