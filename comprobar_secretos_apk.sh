#!/usr/bin/env bash
# Busca credenciales dentro de un APK ya compilado, antes de publicarlo.
#
# Lo que va dentro del APK lo puede leer cualquiera que lo descargue: basta con
# descomprimirlo. Este script hace esa misma lectura y busca todo lo que tenga
# FORMA de credencial (un JWT, una clave privada, una clave de Google, AWS,
# GitHub, Stripe o Slack, una URL con usuario y contraseña) en el código Dart
# compilado, el de Android, los recursos y el manifiesto.
#
# Uso:  ./comprobar_secretos_apk.sh [ruta/al.apk]
#       Sin argumento revisa build/app/outputs/flutter-apk/app-release.apk.
#
# Sale con 0 si no encuentra nada, 1 si encuentra algo y 2 si no ha podido
# revisarlo entero.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK="${1:-$RAIZ/build/app/outputs/flutter-apk/app-release.apk}"

# Formas de un VALOR secreto. Buscar nombres no sirve para decidir: `password`
# o `access_token` salen siempre, porque son los campos que la app manda a la API.
FORMAS_DE_SECRETO='eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}'
FORMAS_DE_SECRETO+='|-----BEGIN [A-Z ]*PRIVATE KEY'
FORMAS_DE_SECRETO+='|AIza[0-9A-Za-z_-]{35}'
FORMAS_DE_SECRETO+='|AKIA[0-9A-Z]{16}'
FORMAS_DE_SECRETO+='|gh[pousr]_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{40,}'
FORMAS_DE_SECRETO+='|sk_(live|test)_[0-9A-Za-z]{16,}'
FORMAS_DE_SECRETO+='|xox[abprs]-[0-9A-Za-z-]{10,}'
FORMAS_DE_SECRETO+='|[a-z][a-z0-9+.-]*://[^/:@[:space:]"]+:[^/@[:space:]"]+@'

# Nombres que conviene mirar a ojo en cada release: tienen que ser nombres de
# campo o de método, nunca un valor.
NOMBRES_A_REVISAR='secret|api[_-]?key|password|token|bearer'

TEMPORAL=""

fallar() {
  echo "ERROR: $1" >&2
  exit 2
}

localizar_aapt2() {
  if command -v aapt2 >/dev/null; then
    command -v aapt2
    return
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  local version
  version="$(ls "$sdk/build-tools" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"
  [[ -n "$version" && -x "$sdk/build-tools/$version/aapt2" ]] || return 1
  echo "$sdk/build-tools/$version/aapt2"
}

# El manifiesto y resources.arsc van compilados, con parte del texto en UTF-16:
# un grep sobre el APK descomprimido no los ve. aapt2 los devuelve en claro.
decodificar_recursos() {
  local aapt2="$1" destino="$2"
  "$aapt2" dump xmltree --file AndroidManifest.xml "$APK" >"$destino" \
    || fallar "aapt2 no ha podido leer el manifiesto de $APK"
  "$aapt2" dump strings "$APK" >>"$destino" \
    || fallar "aapt2 no ha podido leer los recursos de $APK"
}

listar_para_revisar() {
  local descomprimido="$1" decodificado="$2"
  local codigo_dart="$descomprimido/lib/arm64-v8a/libapp.so"
  [[ -f "$codigo_dart" ]] || fallar "el APK no trae lib/arm64-v8a/libapp.so"

  echo "==> Nombres a revisar a ojo (nombres de campo o de método, nunca valores):"
  # Los símbolos privados de Dart acaban en @<número>: son nombres internos.
  { strings -a -n 4 "$codigo_dart"; cat "$decodificado"; } \
    | grep -iE "$NOMBRES_A_REVISAR" | grep -vE '@[0-9]+$' | sort -u \
    | cut -c1-120 | sed 's/^/    /' || true

  echo
  echo "==> Direcciones web en el código Dart"
  echo "    (flutter.dev, github.com y pub.dev vienen de mensajes de error del framework):"
  strings -a -n 8 "$codigo_dart" | grep -oE 'https?://[A-Za-z0-9.-]+' | sort -u \
    | sed 's/^/    /' || true
}

buscar_formas_de_secreto() {
  local descomprimido="$1" decodificado="$2"
  {
    grep -raoE "$FORMAS_DE_SECRETO" "$descomprimido" || true
    grep -aoE "$FORMAS_DE_SECRETO" "$decodificado" | sed 's/^/manifiesto o recursos:/' || true
  } | sed "s|^$descomprimido/||" | sort -u
}

main() {
  [[ -f "$APK" ]] || fallar "no existe $APK; compílalo antes con ./build_apk.sh"
  local herramienta
  for herramienta in unzip strings grep; do
    command -v "$herramienta" >/dev/null || fallar "falta $herramienta"
  done
  local aapt2
  aapt2="$(localizar_aapt2)" \
    || fallar "no encuentro aapt2 (Android SDK, build-tools): sin él el manifiesto queda sin revisar"

  TEMPORAL="$(mktemp -d)"
  trap 'rm -rf "$TEMPORAL"' EXIT

  echo "==> Revisando $APK"
  echo
  unzip -q "$APK" -d "$TEMPORAL/apk" || fallar "no se puede descomprimir $APK"
  decodificar_recursos "$aapt2" "$TEMPORAL/recursos.txt"
  listar_para_revisar "$TEMPORAL/apk" "$TEMPORAL/recursos.txt"

  local hallazgos
  hallazgos="$(buscar_formas_de_secreto "$TEMPORAL/apk" "$TEMPORAL/recursos.txt")"
  echo
  if [[ -n "$hallazgos" ]]; then
    echo "==> ENCONTRADO algo con forma de credencial:" >&2
    echo "$hallazgos" | cut -c1-160 | sed 's/^/    /' >&2
    exit 1
  fi
  echo "==> Ninguna credencial: ni JWT, ni claves privadas, ni claves de servicios,"
  echo "    ni URLs con contraseña."
}

main "$@"
