# Rapport : la transcription de Cairn

Écrit le 2 novembre 2026, dans l'urgence d'une première version utilisable. J'ai lu `Speech.swift`,
`AudioBuffers.swift`, `Sources.swift`, `Recording.swift`, `build.sh` et `Info.plist`. Je n'ai pas lu
`Listener.swift` (26 Ko), le chef d'orchestre de Cairn : l'orchestration d'Aparté est réécrite sans lui.

## Les quatre questions de la fiche

- **L'API :** `SpeechAnalyzer` et `SpeechTranscriber`, la plus récente, sur l'appareil.
- **Le français :** `fr-FR` passe par `supportedLocale(equivalentTo:)`, et le système installe le modèle.
- **Les permissions :** micro par `AVCaptureDevice`, son du Mac par un *process tap*, qui ne demande
  que l'enregistrement audio du système, pas l'enregistrement de l'écran.
- **L'horodatage :** `result.range`, relatif au début de l'audio remis à l'analyseur.

## Ce qui est sain, et repris

- Le transcripteur en direct et le transcripteur de fichier, allégés.
- `AudioBuffers` et `StreamConverter`, tels quels.
- Le son du Mac par *process tap*, tel quel, renommé.
- L'écriture en `.aac` pendant la réunion, puis le passage en `.m4a` sans réencodage. Un `.m4a` coupé
  par un plantage est illisible, un `.aac` non : c'est le meilleur morceau de Cairn.

## Ce qui est fragile

- **Swift 5 :** le code audio repose sur `@unchecked Sendable` et reste en mode Swift 5 dans les modules
  `Transcription` et `Capture`. À passer en Swift 6 plus tard.
- **Le décalage entre pistes :** chaque piste compte le temps depuis son premier son. Aparté mesure ce
  moment, le garde dans `meta.json` et ramène tout sur l'horloge de la réunion. La mesure se fait à
  l'arrivée du premier tampon, sans la latence matérielle de chaque entrée.
- **Changement de micro en pleine réunion :** Cairn ne le gère que sur iPhone. Sur Mac, débrancher le
  micro peut couper la piste. Non testé.
- **Aucun test** de ce code dans Cairn, d'après les noms de fichiers de test.

## Ce qui n'est pas repris

- `FluidAudio` et `Voices.swift` : repris depuis, à la demande de Steven (voir la fiche).
- `NameFixer` et le vocabulaire du projet : repris depuis, avec le titre, le dossier et les noms déjà donnés
  aux voix à la place des carnets. `Echo` aussi, qu'il faut pour une visio sans casque.
- Le registre des écoutes en cours : au lancement, Aparté termine les `.aac` qu'il trouve.
- Tout le code iPhone.

## Ce que cela ne prouve pas

Je n'ai pas jugé la justesse du texte. Il faut l'extrait de vérité relu par Steven pour ça.
