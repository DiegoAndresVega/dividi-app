#!/usr/bin/env bash
# Comprueba que un APK va firmado con la clave de release de Dividi.
#
# Android solo acepta una actualización si viene firmada con la misma clave que
# la versión instalada. Un APK firmado con otra (la de depuración, o una clave
# nueva por error) no se puede instalar encima: el usuario tendría que borrar
# la app. Por eso se compara con la huella del certificado, no basta con que
# "esté firmado".
#
# Uso:  ./comprobar_firma_apk.sh [ruta/al.apk]
#       Sin argumento revisa build/app/outputs/flutter-apk/app-release.apk.
#
# Sale con 0 si la firma es la de release, 1 si es otra y 2 si no ha podido
# comprobarla.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK="${1:-$RAIZ/build/app/outputs/flutter-apk/app-release.apk}"

# SHA-256 del certificado de release. Es público: cualquiera lo lee del APK.
HUELLA_DE_RELEASE='3b8d4d0eb4a170940e49bdf22174f08b5c13934f3d20a8bf04f7583287db1b8c'

# Así se llama el certificado que genera el SDK para depurar.
DN_DE_DEPURACION='CN=Android Debug'

# JDK que trae Android Studio en macOS, el mismo con el que compila Flutter.
JDK_DE_ANDROID_STUDIO='/Applications/Android Studio.app/Contents/jbr/Contents/Home'

fallar() {
  echo "ERROR: $1" >&2
  exit 2
}

localizar_apksigner() {
  if command -v apksigner >/dev/null; then
    command -v apksigner
    return
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  local version
  version="$(ls "$sdk/build-tools" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"
  [[ -n "$version" && -x "$sdk/build-tools/$version/apksigner" ]] || return 1
  echo "$sdk/build-tools/$version/apksigner"
}

# apksigner es Java. En macOS /usr/bin/java es un aviso, no un JDK.
preparar_java() {
  if [[ -z "${JAVA_HOME:-}" && -x "$JDK_DE_ANDROID_STUDIO/bin/java" ]]; then
    export JAVA_HOME="$JDK_DE_ANDROID_STUDIO"
  fi
  if [[ -n "${JAVA_HOME:-}" ]]; then
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
  java -version >/dev/null 2>&1 \
    || fallar "no hay un JDK utilizable. Define JAVA_HOME o instala Android Studio"
}

[[ -f "$APK" ]] || fallar "no existe el APK: $APK"
APKSIGNER="$(localizar_apksigner)" \
  || fallar "no encuentro apksigner. Instala las build-tools del Android SDK"
preparar_java

CERTIFICADOS="$("$APKSIGNER" verify --print-certs "$APK" 2>&1)" \
  || fallar "la firma de $APK no es válida:
$CERTIFICADOS"

# Cada esquema de firma (v1, v2, v3…) repite el certificado con su prefijo:
# «Signer #1 certificate …» o «V2 Signer: certificate …». Se quitan repetidos.
extraer() {
  sed -n "s/^.*[Ss]igner.* certificate $1: //p" <<<"$CERTIFICADOS" | sort -u
}
HUELLAS="$(extraer 'SHA-256 digest')"
NOMBRES="$(extraer 'DN')"

[[ -n "$HUELLAS" ]] || fallar "apksigner no ha devuelto ningún certificado para $APK"

if [[ "$(wc -l <<<"$HUELLAS" | tr -d ' ')" != 1 ]]; then
  echo "MAL: $APK lleva más de un firmante:" >&2
  echo "$NOMBRES" >&2
  exit 1
fi

if [[ "$HUELLAS" == "$HUELLA_DE_RELEASE" ]]; then
  echo "OK: $APK va firmado con la clave de release de Dividi"
  echo "    $NOMBRES"
  exit 0
fi

if [[ "$NOMBRES" == *"$DN_DE_DEPURACION"* ]]; then
  echo "MAL: $APK va firmado con la clave de DEPURACIÓN, no con la de release." >&2
  echo "     Falta android/key.properties (ver README, «Firma de release»)." >&2
else
  echo "MAL: $APK va firmado con una clave que no es la de release de Dividi." >&2
  echo "     Certificado: $NOMBRES" >&2
  echo "     Huella:      $HUELLAS" >&2
  echo "     Esperada:    $HUELLA_DE_RELEASE" >&2
fi
exit 1
