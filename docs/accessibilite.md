# Accessibilité

État au 2 novembre 2026. Rien n'a été essayé avec VoiceOver ni au clavier dans l'app : ce qui suit vient de
la lecture du code et de calculs.

## Contrastes calculés

Seuil : 4,5:1 pour le texte courant.

| Texte sur fond | Clair | Sombre |
|---|---|---|
| `encre` sur `creme` | 10,56 | 13,69 |
| `encre` sur `surface` | 8,75 | 14,70 |
| `encreDouce` sur `creme` | 5,63 | 7,33 |
| `encreDouce` sur `surface` | 4,67 | 7,87 |

Les paires fixes de la colonne sombre sont dans `Sources/DA/DA.swift` et ne changent pas avec le mode.
Le rendu sombre de l'en-tête du compte rendu a été vu dans un rendu de test. Le reste de l'écran n'a pas été vu.

## Ce qui a été ajouté pour VoiceOver

- Les horodatages se lisent « 12 minutes 3 secondes », et le chrono a un nom.
- Un élément du compte rendu se lit en une fois : la phrase, le responsable, l'échéance, le moment.
- L'élément choisi et l'entrée active de la barre latérale sont annoncés comme sélectionnés.
- Une alerte en réunion est lue dès qu'elle apparaît.

## Au clavier

- `⌘N` : nouvelle réunion. `⌘⏎` : démarrer. `⇧⌘T` : terminer la réunion.
- Les autres boutons dépendent de l'accès complet au clavier de macOS.

## À essayer

Parcourir les écrans avec VoiceOver et avec l'accès complet au clavier : la bonne lecture et l'ordre de
parcours n'ont jamais été vérifiés.
