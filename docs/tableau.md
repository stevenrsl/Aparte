# Tableau des tâches

Qui travaille sur quoi, en ce moment. Inscris ta tâche avant de commencer. Ne prends pas une tâche
dont les fichiers recoupent une ligne « en cours » de l'autre agent. Le fonctionnement complet est
dans le [plan des agents](plan-agents.md).

| Tâche | Agent | Branche | État | Fichiers touchés |
|---|---|---|---|---|
| Mise en place du projet | Claude Code | `mise-en-place` | en relecture | `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.github/`, `docs/`, `Package.swift`, `Sources/`, `Tests/` |
| Première version utilisable | Claude Code | `v1-utilisable` | en relecture | `Package.swift`, `build.sh`, `Support/`, `Sources/`, `Tests/`, `docs/rapport-cairn.md` |
| Tester les pannes d'enregistrement | Codex | `tests-pannes` | en relecture | `Tests/`, `docs/pannes-enregistrement.md` |
| Mesurer les oublis de l'analyse | Claude Code | `mesure-oublis` | en relecture | `Sources/Analyse/`, `Tests/AnalyseTests/`, `docs/mesure-analyse.md`, `README.md` |
| Vérifier le mode sombre et l'accessibilité | Claude Code | `accessibilite` | en relecture | `Sources/Interface/Vues.swift`, `docs/accessibilite.md` |
| Embarquer les polices du brief | Claude Code | `polices` | en relecture | `Sources/DA/`, `Package.swift`, `build.sh` |
| Fiabiliser l'enregistrement | Claude Code | `fiabilite-audio` | en relecture | `Sources/Capture/`, `Sources/Interface/`, `Sources/Stockage/`, `Tests/` |
| Protéger la réunion en cours | Claude Code | `reunion-protegee` | en relecture | `Sources/AparteApp/`, `Sources/Interface/`, `Sources/Analyse/`, `Tests/` |
| Renommer, déplacer et supprimer une réunion | Claude Code | `gerer-reunions` | en relecture | `Sources/Stockage/`, `Sources/Interface/`, `Tests/`, `docs/fiche-reunions-2026-11.md`, `README.md` |
| Reprendre les voix, l'écho et les noms de Cairn | Claude Code | `voix-et-vocabulaire` | en relecture | `Package.swift`, `build.sh`, `Sources/`, `Tests/`, `docs/` |
| Analyse automatique et PCC | Claude Code | `analyse-auto-pcc` | en relecture | `Sources/Analyse/`, `Sources/Interface/`, `Sources/Stockage/`, `Tests/` |
| Sujets et répartition d'une réunion | Claude Code | `sujets-repartir` | en cours | `Sources/Analyse/`, `Sources/Interface/`, `Sources/Stockage/`, `Tests/` |
