#!/usr/bin/env bash
# Construit Aparté.app : SwiftPM ne produit qu'un exécutable nu, et macOS demande
# un bundle pour accorder le micro et le son du Mac. En attendant le projet Xcode.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Aparte
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Aparte"

APP="build/Aparté.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Aparte"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Le certificat de développement garde les autorisations d'une version à l'autre.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
xattr -cr "$APP"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "$(pwd)/$APP"
