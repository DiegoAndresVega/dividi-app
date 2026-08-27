#!/usr/bin/env bash
# Compila el APK de release y lo deja en la raíz del proyecto como dividi.apk,
# en vez de enterrado en build/app/outputs/flutter-apk/.
#
# Uso:  ./build_apk.sh
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGEN="$RAIZ/build/app/outputs/flutter-apk/app-release.apk"
DESTINO="$RAIZ/dividi.apk"

cd "$RAIZ"

echo "==> Compilando APK de release…"
flutter build apk --release

if [[ ! -f "$ORIGEN" ]]; then
  echo "ERROR: la compilación terminó pero no se encuentra el APK en:" >&2
  echo "       $ORIGEN" >&2
  exit 1
fi

cp "$ORIGEN" "$DESTINO"

echo
echo "==> APK listo: $DESTINO"
echo "    Tamaño: $(du -h "$DESTINO" | cut -f1)"
echo "    Compilado: $(date '+%d/%m/%Y %H:%M')"
