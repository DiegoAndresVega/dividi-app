#!/usr/bin/env bash
# Compila el APK de release y lo deja en la raíz del proyecto como dividi.apk,
# en vez de enterrado en build/app/outputs/flutter-apk/.
#
# Uso:  ./build_apk.sh
#       API_BASE_URL=http://10.0.2.2:8000 ./build_apk.sh
#
# Sin API_BASE_URL sale la de producción, que es el valor por defecto del
# código: olvidarse de la variable no puede dar un APK apuntando a pruebas.
#
# Necesita android/key.properties con la clave de release (ver «Firma de
# release» en el README), y no deja el APK en la raíz si la firma no es esa.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGEN="$RAIZ/build/app/outputs/flutter-apk/app-release.apk"
DESTINO="$RAIZ/dividi.apk"
FIRMA="$RAIZ/android/key.properties"

cd "$RAIZ"

if [[ ! -f "$FIRMA" ]]; then
  echo "ERROR: falta $FIRMA con la clave de release." >&2
  echo "       Sin ella el APK saldría firmado con la de depuración y no se" >&2
  echo "       podría instalar encima de la versión publicada. Ver README." >&2
  exit 1
fi

API_BASE_URL="${API_BASE_URL:-}"

if [[ -n "$API_BASE_URL" ]]; then
  echo "==> Compilando APK de release contra $API_BASE_URL…"
  flutter build apk --release --dart-define=API_BASE_URL="$API_BASE_URL"
else
  echo "==> Compilando APK de release contra producción…"
  flutter build apk --release
fi

if [[ ! -f "$ORIGEN" ]]; then
  echo "ERROR: la compilación terminó pero no se encuentra el APK en:" >&2
  echo "       $ORIGEN" >&2
  exit 1
fi

"$RAIZ/comprobar_firma_apk.sh" "$ORIGEN"

cp "$ORIGEN" "$DESTINO"

echo
echo "==> APK listo: $DESTINO"
echo "    Tamaño: $(du -h "$DESTINO" | cut -f1)"
echo "    Compilado: $(date '+%d/%m/%Y %H:%M')"
echo "    API: ${API_BASE_URL:-https://dividi.finkafest.es (por defecto)}"
