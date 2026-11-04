# Tableau des tâches

Qui travaille sur quoi, en ce moment. Inscris ta tâche avant de commencer. Ne prends pas une tâche
dont les fichiers recoupent une ligne « en cours » de l'autre agent. Le fonctionnement complet est
dans le [plan des agents](plan-agents.md).

| Tâche | Agent | Branche | État | Fichiers touchés |
|---|---|---|---|---|
| Nettoyage après la V0.2 | Claude Code | `apres-v0-2` | en relecture | `docs/tableau.md`, `docs/pannes-enregistrement.md`, `Tests/CaptureTests/` |
| Garder l'écho comme preuve (issue #16, défaut grave n°1) | Dev | `garder-echo` | en relecture | `Sources/Transcription/Nettoyage.swift`, `Sources/Transcription/Transcription.swift`, `Sources/Interface/Modele.swift`, `Sources/Interface/Vues.swift`, `Sources/Analyse/Analyse.swift`, `Sources/Analyse/Mistral.swift`, `Tests/TranscriptionTests/`, `Tests/AnalyseTests/`, `Tests/InterfaceTests/`, `README.md`, `docs/fiche-reunions-2026-11.md` |
| Titres de sujets sans mots inventés (#16) | Luna | `titres-sujets` | en relecture | `Sources/Analyse/Analyse.swift` (DecoupageSujets), `Tests/AnalyseTests/TitresSujetsTests.swift`, `docs/tableau.md` |
| Comptes rendus périmés après une relecture (issue #16, défaut grave n°2) | Dev | `analyse-perimee` | en relecture | `Sources/Analyse/Analyse.swift`, `Sources/Interface/Modele.swift`, `Sources/Interface/Vues.swift`, `Tests/AnalyseTests/`, `Tests/InterfaceTests/` |
