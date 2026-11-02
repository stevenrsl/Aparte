# Tableau des tâches

Qui travaille sur quoi, en ce moment. Inscris ta tâche avant de commencer. Ne prends pas une tâche
dont les fichiers recoupent une ligne « en cours » de l'autre agent. Le fonctionnement complet est
dans le [plan des agents](plan-agents.md).

| Tâche | Agent | Branche | État | Fichiers touchés |
|---|---|---|---|---|
| Mise en place du projet | Claude Code | `mise-en-place` | en relecture | `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.github/`, `docs/`, `Package.swift`, `Sources/`, `Tests/` |
| Première version utilisable | Claude Code | `v1-utilisable` | en relecture | `Package.swift`, `build.sh`, `Support/`, `Sources/`, `Tests/`, `docs/rapport-cairn.md` |
| Tester les pannes d'enregistrement | Codex | `tests-pannes` | en relecture | `Tests/`, `docs/pannes-enregistrement.md` |
| Mesurer les oublis de l'analyse | Claude Code | `mesure-oublis` | à faire | `Tests/AnalyseTests/`, `docs/mesure-analyse.md` |
| Vérifier le mode sombre et l'accessibilité | Claude Code | `accessibilite` | à faire | `Sources/DA/`, `docs/accessibilite.md` |
| Embarquer les polices du brief | Claude Code | `polices` | à faire | `Sources/DA/`, `Package.swift`, `build.sh` |
| Fiabiliser l'enregistrement | Claude Code | `fiabilite-audio` | en cours | `Sources/Capture/`, `Sources/Interface/`, `Sources/Stockage/`, `Tests/` |
