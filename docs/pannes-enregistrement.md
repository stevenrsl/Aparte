# Pannes d'enregistrement

Essais du 2 novembre 2026, base `origin/v1-utilisable` (`f798b9f`).
macOS 27, Swift 6.4, arm64. Aucun changement du code de production.

## Reproduit par les tests

Commande depuis la racine du dépôt :

```sh
env -u APARTE_AUDIO_REFERENCE swift test --filter 'CaptureTests|InterfaceTests'
```

Résultat : **11 tests exécutés, dont 7 nouveaux ; 2 défauts connus, aucun échec inattendu**.
Les défauts sont encadrés par `withKnownIssue`, uniquement autour de l'attente qui échoue.
Ils restent exécutés : une correction fera signaler une disparition du défaut attendu.

| Cas | Test | Résultat observé |
|---|---|---|
| AAC tronqué vers son milieu, au milieu d'une trame ADTS | `panneAACTronqueAuMilieuDUneTrame` | Remux réussi ; durée correspondant aux trames complètes à 0,5 s près ; source inchangée ; aucun temporaire M4A résiduel. La moitié des octets n'est pas forcément la moitié de la durée. |
| AAC de zéro octet | `panneAACVideEstConserveSansM4A` | `terminerEnregistrement` remonte une erreur ; le fichier vide reste et aucun M4A n'est créé. |
| M4A valide déjà présent à côté de l'AAC | `panneM4AExistantNeDoitPasEtreEcrase` | **Défaut connu** : un M4A d'environ 8 s est remplacé par celui d'un AAC d'environ 2 s. Le test appelle le véritable `Recording.remux`, sans passage à la corbeille. |
| Deux réunions interrompues au même lancement | `panneDeuxReunionsInterrompuesAuMemeLancement` | Le véritable `ModeleApp.init` récupère les deux micros, à la racine et dans un dossier. Une piste système vide de la seconde réunion n'empêche pas cette récupération ; elle reste sur place avec une alerte. Notes et métadonnées inchangées. Recharger une seconde fois ne modifie pas les M4A et ne répète pas l'alerte. |
| Dossier supprimé après la première écriture | `panneDossierSupprimePendantEcriture` | **Défaut connu** : après suppression du dossier et de son AAC, la seconde écriture via `PisteAudio` ne signale aucune erreur. Le chemin audio n'existe plus. |
| Disque plein pendant l'écriture | `panneDisquePleinPendantEcriture` | Après de vraies écritures réussies, injection de `dskFulErr` (`-34`) au niveau `ExtAudioFileWrite`. `PisteAudio` signale une seule erreur malgré plusieurs tentatives. Le préfixe déjà enregistré est conservé et peut être remuxé. |
| `kill -9` pendant l'écriture | `panneKill9PendantEcriture` | Un producteur enfant utilise le vrai `PisteAudio` et écrit du son synthétique. Après son signal de disponibilité, le test lui envoie SIGKILL et vérifie sa terminaison par ce signal. L'AAC non fermé se remuxe ; plus de 8 s sont lisibles, avec moins de 0,5 s d'écart entre source et M4A. |

Les quatre tests préexistants de Capture/Interface passent également, notamment la
conservation en mémoire des notes après disparition du dossier, puis leur sauvegarde
quand celui-ci revient. Les tampons des anciens tests Capture sont maintenant explicitement
initialisés, et leur chemin d'écriture impossible est sous un temporaire créé par le test.

### Portée et sécurité des essais

- Sinusoïde de 440 Hz ou silence explicitement initialisé ; titres et notes inventés.
  Aucune donnée de réunion réelle, aucun micro, aucun service de transcription utilisé.
- Chaque nouveau test crée son propre dossier temporaire et le supprime par `defer`.
  L'environnement `APARTE_RACINE` est fixé **avant** la construction de `ModeleApp`,
  puis restauré. Les préférences d'emplacement ne sont pas modifiées.
- Le producteur est compilé dans ce temporaire avec les sources Capture actuelles et les
  outils Xcode déjà présents (`xcrun swiftc`, `xcrun clang`). Aucune dépendance ajoutée.
- La simulation de disque plein injecte une petite bibliothèque dans **le seul enfant lancé
  par le test**. Elle retourne une erreur AudioToolbox, sans remplir de volume. Elle ne
  reproduit pas le comportement d'un système de fichiers réellement saturé ni celui des
  écritures de notes/métadonnées. Une première tentative d'injection aux appels POSIX
  ne déclenchait pas la panne ; elle a été remplacée par cette simulation vérifiée.
- SIGKILL ne vise que le PID de cet enfant encore actif. Nettoyage du processus par `defer`,
  nombre de tampons borné à 500 et attente de chaque traitement bornée à 5 s.
  Le test ne tue pas l'app Aparté et ne constitue pas un essai complet de son interface.
- La récupération au lancement utilise le vrai passage à la corbeille : deux petits AAC
  synthétiques y sont déposés par exécution. Le test préexistant de finalisation en dépose
  un autre. **Aucun parcours, vidage ni suppression dans la corbeille**, afin de préserver
  tout ce qui s'y trouvait déjà. Les autres essais appellent directement `remux`.

## Déduit de la lecture du code, sans reproduction matérielle

### Micro débranché pendant une réunion

`MicrophoneSource.start` (`Sources/Capture/Capture.swift`) choisit l'entrée une seule fois,
installe un tap, puis démarre `AVAudioEngine`. La classe n'observe ni changement de
configuration du moteur ni disparition du périphérique ; elle ne tente pas de redémarrage.
Le retour d'`AudioUnitSetProperty` lors du choix de l'entrée est également ignoré.

Le protocole `AudioSource` ne transmet que les tampons, sans événement d'interruption.
`PisteAudio.surErreur` est appelé lors d'une erreur d'ouverture/écriture du fichier, pas
lorsque les tampons cessent d'arriver. `SessionReunion.signalerAudio` ne sera donc pas
appelé par une simple absence de tampons ; aucun délai de surveillance n'est présent.
Le chrono dépend de la date de début, et les niveaux ne sont actualisés que lorsqu'un
tampon arrive : si le flux s'arrête silencieusement, le chrono peut continuer et les
derniers niveaux rester affichés sans alerte spécifique au micro.

**Non établi par ces tests :** arrêt effectif du moteur, bascule éventuelle vers le micro
interne, continuité audio et comportement au rebranchement. Cela dépend du matériel et
d'AVAudioEngine. Un essai physique de débranchement/rebranchement reste nécessaire.

### Conséquences des deux défauts reproduits

- `Recording.remux` retire explicitement la cible existante avant de déplacer le temporaire.
  Il compare la durée du nouveau M4A à l'AAC, pas à celle de l'ancien M4A.
  `terminerEnregistrement` utilise cette fonction, puis met l'AAC à la corbeille : au
  lancement, un ancien M4A plus long peut donc être perdu. Le test reproduit l'écrasement
  au niveau du remux ; cette conséquence au lancement est déduite de la chaîne d'appels.
- Un fichier supprimé mais encore ouvert peut rester inscriptible jusqu'à sa fermeture.
  `PisteAudio` ne vérifie pas que son chemin existe encore. Une sauvegarde ultérieure des
  notes/transcriptions peut signaler la disparition du dossier via `SessionReunion`, mais
  ce n'est pas une détection fiable de la perte du fichier audio à elle seule.

## Suite

Relecture par Claude Code, puis décision de Steven sur la proposition. Les deux défauts
restent à corriger dans une tâche distincte ; aucune politique de récupération n'a été
changée ici. Le débranchement physique du micro reste à tester. Aucune décision
« À Steven » n'a été nécessaire pour écrire ces tests.
