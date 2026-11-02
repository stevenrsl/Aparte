# Aparté

Notes et enregistrement de réunions pour Mac, avec une analyse en local. Version de test : V0.1. Les
règles du projet sont dans [AGENTS.md](AGENTS.md).

## Ce qu'il faut

- Un Mac Apple Silicon en **macOS 27**, avec **Xcode 27** et Swift 6.4 pour construire depuis les sources.
- **Apple Intelligence activé**, pour l'analyse. Sans lui, tout le reste marche et l'app dit pourquoi
  l'analyse n'est pas disponible.
- Au premier lancement, le système peut télécharger son modèle de français. C'est le seul accès réseau.

## Installer

Depuis les sources, le plus simple pour un développeur :

```bash
git clone --branch v0.1 https://github.com/stevenrsl/Aparte.git
cd Aparte
./build.sh && open "build/Aparté.app"
```

Ou avec `Aparte-0.1.zip`, joint à la [publication V0.1](https://github.com/stevenrsl/Aparte/releases/tag/v0.1).
L'app n'est pas notarisée : macOS la bloque tant qu'on ne retire pas la quarantaine.

```bash
xattr -dr com.apple.quarantine "/Applications/Aparté.app"
```

## Essayer

1. Choisis un dossier pour les réunions, puis lance une courte réunion. Accepte le micro, et en visio le
   son du Mac. **Préviens les personnes que tu enregistres.**
2. Note quelques lignes, parle, termine, puis clique sur « Analyser sur ce Mac ».
3. Clique sur une décision : l'app affiche et relit le passage source.

En visio, mets un casque. Sinon le micro capte aussi les haut-parleurs et les phrases sortent en double.

Chaque réunion est un dossier lisible sans l'app : `meta.json`, `micro.m4a`, `systeme.m4a`,
`transcription.json`, `notes.md`, `analyse.json`, `analyse.md`.

## Gérer une réunion

Depuis son compte rendu, « // gérer » renomme la réunion, la déplace ou la met à la Corbeille. Le dossier sur le
disque suit. Une réunion en cours d'enregistrement ne peut pas être modifiée.

## Ce qui est connu

- L'analyse locale peut manquer des éléments, en retenir de trop ou mal les ranger : voir `docs/mesure-analyse.md`.
  Les éléments cités sont toujours exacts, leur classement reste à relire.
- Le résumé est construit depuis les éléments validés. Il est sec, c'est voulu.
- Chaque élément est la phrase exacte de la transcription, sans reformulation : elle garde ses hésitations et ses erreurs de transcription.
- PCC et les fournisseurs externes ne sont pas branchés : rien ne quitte le Mac.
- Si le son s'arrête, Aparté le signale en réunion, repart sur l'entrée disponible et note le blanc dans le compte
  rendu. Ce chemin n'a jamais été essayé en débranchant vraiment un micro.
- Pas encore testé : le rendu du mode sombre, un micro externe, un changement de micro en pleine réunion,
  VoiceOver, une longue réunion.

## Faire un retour

Ouvre une issue sur ce repo avec ce que tu faisais, ce que tu attendais et ce qui s'est passé. **N'y colle
jamais de transcription ni d'audio d'une vraie réunion.**

## Développer

```bash
swift test
```

Pour tester la transcription et l'analyse sur un vrai fichier, en n'affichant que des nombres :

```bash
APARTE_AUDIO_REFERENCE=/chemin/vers/reunion.m4a swift test
```
