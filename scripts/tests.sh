#!/bin/bash
# Commande de référence pour la suite de tests d'Aparté.
# Les variables APARTE_AUDIO_REFERENCE / APARTE_MESURE / APARTE_RENDUS pointent vers des fichiers
# propres à la machine de Steven : sans elles, les tests qui en dépendent se sautent eux-mêmes.
exec env -u APARTE_AUDIO_REFERENCE -u APARTE_MESURE -u APARTE_RENDUS swift test
