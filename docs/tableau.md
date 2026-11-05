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
