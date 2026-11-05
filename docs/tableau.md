# Tableau des tâches

Qui travaille sur quoi, en ce moment. Inscris ta tâche avant de commencer. Ne prends pas une tâche
dont les fichiers recoupent une ligne « en cours » de l'autre agent. Le fonctionnement complet est
dans le [plan des agents](plan-agents.md).

| Tâche | Agent | Branche | État | Fichiers touchés |
|---|---|---|---|---|
| Intégration de #18, #19, #20 et nettoyage du dépôt | Pickle | `build-integration` | en cours | `docs/`, `README.md` |
| Présence de la clé sans lecture, tests d'interface relancés, petits nettoyages | Dev | `trousseau-presence` | fusionné dans `build-integration` | `Sources/Analyse/Mistral.swift`, `Sources/Interface/Modele.swift`, `Sources/Stockage/Stockage.swift`, `Tests/InterfaceTests/`, `Tests/StockageTests/` |
| Élisions et tirets des titres de sujets | Luna | `titres-finitions` | fusionné dans `build-integration` | `Sources/Analyse/Analyse.swift`, `Tests/AnalyseTests/TitresSujetsTests.swift` |
| Essai complet de l'app sur audio de synthèse | Biscuit | aucune | fait, à rejouer sur le build final | aucun |
| Contrôle des écrans | Pickle (Miso n'a rien exécuté) | `controle-ecrans` | fusionné dans `build-integration` | `Sources/Interface/Vues.swift`, `Sources/DA/DA.swift`, `Tests/InterfaceTests/RendusEcrans.swift` |
| Défauts de l'essai : analyse automatique, réunion récupérée, fausse alerte de coupure | Dev | `defauts-essai` | fusionné dans `build-integration` | `Sources/Interface/Modele.swift`, `Sources/Capture/Capture.swift`, `Sources/Interface/Vues.swift` (`sansAnalyse` seulement), tests liés |
| Corrections après l'essai sur une vraie réunion : son du Mac accéléré, écran vide, compte rendu à la Cairn, noms des voix | Claude Code | `corrections-essai-cairn` | terminé, base V0.5 | `Sources/Capture/`, `Sources/Analyse/`, `Sources/Interface/`, `Sources/Stockage/`, `Tests/`, `docs/fiche-reunions-2026-11.md`, `README.md` |

| Assemblage V0.5 et découpage des vues | Luna | `v0-5` | en cours | `Sources/Interface/`, `Tests/InterfaceTests/RendusEcrans.swift`, `docs/` |
| Accueil et dossier plus denses | Claude Code | `accueil-dense` | en relecture | `docs/brief-da-reunions.md`, `Sources/DA/DA.swift`, `Sources/Interface/Vues.swift`, `Sources/Interface/Modele.swift`, `Tests/InterfaceTests/` |
| Logo et icône de l'app | Claude Code | `logo` | en relecture | `Support/`, `build.sh`, `Sources/DA/DA.swift`, `docs/brief-da-reunions.md`, `docs/proposition-logo.md` |

| Contrôle préalable de la base V0.5 et des rendus | Panko | `v05-controle-base` | en cours | `Tests/InterfaceTests/RendusEcrans.swift` |

| Découpage des vues V0.5 par écran, sans changement de comportement | Luna | `v0-5` | compilé et testé, relecture attendue | `Sources/Interface/` |
| Contrat de navigation vers un moment du compte rendu | Panko | `v05-navigation` | en cours | `Sources/Interface/Modele.swift`, `Sources/Interface/Vues.swift`, `Sources/Interface/EcranCompteRendu.swift`, `Tests/InterfaceTests/` |

| Navigation V0.5 : parcours et barre latérale | Panko | `v05-navigation` | en relecture | `Sources/Interface/Modele.swift`, `Vues.swift`, `EcransAccueil.swift`, `EcransDossier.swift`, `EcranNouvelle.swift`, `Sources/AparteApp/main.swift`, tests |
