# Aparté

Notes et enregistrement de réunions pour Mac, avec une analyse en local. Les règles sont dans
[AGENTS.md](AGENTS.md).

Construire et ouvrir l'app, en attendant le projet Xcode (macOS 27) :

```bash
./build.sh && open "build/Aparté.app"
```

Tester la transcription et l'analyse sur un vrai fichier, en n'affichant que des nombres :

```bash
APARTE_AUDIO_REFERENCE=/chemin/vers/reunion.m4a swift test
```
