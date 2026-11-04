# Tableau des tâches

Qui travaille sur quoi, en ce moment. Inscris ta tâche avant de commencer. Ne prends pas une tâche
dont les fichiers recoupent une ligne « en cours » de l'autre agent. Le fonctionnement complet est
dans le [plan des agents](plan-agents.md).

| Tâche | Agent | Branche | État | Fichiers touchés |
|---|---|---|---|---|
| Micro Bluetooth : plantage au démarrage et audio vide | Pickle | `micro-bluetooth` | en relecture | `Package.swift`, `Sources/CaptureObjC/`, `Sources/Capture/Capture.swift`, `Sources/Capture/Recording.swift`, `Tests/CaptureTests/MicroBluetoothTests.swift`, `Tests/CaptureTests/PannesEnregistrementTests.swift` |
| Titres de sujets sans mots inventés (#16) | Luna | `titres-sujets` | en relecture | `Sources/Analyse/Analyse.swift` (DecoupageSujets), `Tests/AnalyseTests/TitresSujetsTests.swift`, `docs/tableau.md` |
| Comptes rendus périmés après une relecture (issue #16, défaut grave n°2) | Dev | `analyse-perimee` | en relecture | `Sources/Analyse/Analyse.swift`, `Sources/Interface/Modele.swift`, `Sources/Interface/Vues.swift`, `Tests/AnalyseTests/`, `Tests/InterfaceTests/` |
| Build de test : intégration de `micro-bluetooth` et `analyse-perimee` (local, hors `main`) | Claude Code | `build-integration` | en cours | `docs/tableau.md` |
