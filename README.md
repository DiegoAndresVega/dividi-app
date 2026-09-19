# dividi

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Dependencias

### El lockfile manda

`pubspec.lock` está en el repositorio y se respeta. No es un detalle de estilo: sin él,
dos compilaciones del mismo commit pueden traer versiones distintas de todo, y la release
que se sube a Play Store deja de ser la que se probó.

- El CI instala con `flutter pub get --enforce-lockfile`, que falla si lo resuelto no
  coincide con el lockfile. Un `pubspec.lock` desactualizado se ve ahí y no en la release.
- Por eso mismo el CI fija la **versión de Flutter** (`3.44.4`) en vez de usar el canal
  `stable`. Los paquetes atados al SDK —`intl`, `meta`, `matcher`, `test_api`,
  `vector_math`— cambian con cada Flutter, así que con un stable móvil el lockfile deja de
  cuadrar solo y el CI se pone en rojo sin que nadie haya tocado nada. Al subir de Flutter
  se sube esa línea de `.github/workflows/ci.yml` y se regenera el lockfile en el mismo
  commit.
- No se regenera a la ligera. Se toca cuando se actualiza una dependencia a propósito, y
  el commit que lo cambia lo dice.
- Las actualizaciones llegan por Dependabot (`pub`, `gradle` y `github-actions`, semanal).
  Se lee el aviso de cada una antes de fusionarla: el CI dice si la suite pasa, no si el
  cambio es buena idea.

### Cuidado con `flutter_secure_storage`

Ahí viven los tokens de sesión. Un salto de major puede cambiar cómo se guardan en
Android, y si los que ya están en los dispositivos dejan de poder leerse, **todos los
usuarios acaban en la pantalla de login** sin que nadie lo haya pedido. Un pull request de
Dependabot que suba su major no se fusiona sin comprobar antes la ruta de migración.

Los tokens quedan además fuera de la copia de seguridad de Android y de la transferencia
entre dispositivos (`android/app/src/main/res/xml/backup_rules.xml` y
`data_extraction_rules.xml`): la clave que los cifra vive en el Keystore y no sale del
móvil, así que restaurar la copia en otro dispositivo solo dejaría una sesión ilegible.

### Origen de lo que se instala

Las ocho dependencias directas de `pubspec.yaml` tienen editor verificado en pub.dev:
`flutter.dev` (`cupertino_icons`, `path_provider`, `image_picker`), `dart.dev` (`http`),
`labs.dart.dev` (`timezone`), `fluttercommunity.dev` (`share_plus`), `steenbakker.dev`
(`flutter_secure_storage`) y `dexterx.dev` (`flutter_local_notifications`).

La parte de Gradle va con versiones exactas, sin rangos dinámicos: Android Gradle Plugin
`9.0.1` y Kotlin `2.3.20` en `android/settings.gradle.kts`, Gradle `9.1.0` en el wrapper,
y los repositorios son `google()`, `mavenCentral()` y `gradlePluginPortal()`. El wrapper
lleva `distributionSha256Sum`, así que Gradle comprueba lo que se descarga en vez de
ejecutar lo que le devuelva la URL. Al cambiar de versión hay que traer también su
checksum.

## Contra qué servidor habla la app

Por defecto, contra producción: `https://dividi.finkafest.es`. La URL sale de
`lib/services/api_base_url.dart`, que la lee de `--dart-define=API_BASE_URL` y cae en la de
producción cuando no se pasa nada. Compilar contra otro servidor no exige tocar el código:

```bash
# desarrollo, con la API levantada en el mismo ordenador
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# un APK de release apuntando a otro sitio (para probar, no para publicar)
API_BASE_URL=https://pruebas.ejemplo.test ./build_apk.sh
```

`10.0.2.2` es la dirección con la que el emulador de Android ve el ordenador que lo aloja;
`localhost` dentro del emulador es el propio emulador. En un móvil de verdad hay que usar la IP
del ordenador en la red local.

**El valor viaja dentro del binario.** `String.fromEnvironment` se resuelve al compilar, así que
un APK ya construido no se puede reapuntar: hay que volver a compilarlo.

**Aviso: la app tiene prohibido el tráfico sin cifrar.**
`android/app/src/main/res/xml/network_security_config.xml` pone `cleartextTrafficPermitted`
a `false` para todos los destinos, así que una API local en `http://` no responderá aunque la
URL sea correcta: el fallo sale como error de red, no como error de configuración. Para
desarrollo hay dos caminos: servir la API local por HTTPS, o añadir una excepción **solo para
la variante de depuración**. Lo segundo es material del punto 24 de la revisión de seguridad,
que sigue abierto.

## Antes de publicar una release

### Firma de release

Android solo instala una actualización encima de la app si viene firmada con **la misma
clave** que la versión instalada. Esa clave es la identidad de la app: quien la tenga puede
publicar actualizaciones que el móvil aceptará como legítimas, y quien la pierda no podrá
publicar ninguna más. Por eso vive **fuera del repositorio**, y Gradle la lee de
`android/key.properties`, que Git ignora:

```properties
storeFile=/ruta/absoluta/a/dividi-release.jks
storePassword=...
keyAlias=dividi
keyPassword=...
```

Sin ese fichero, `flutter build apk --release` sigue funcionando en cualquier clon, pero firma
con la clave de depuración del ordenador. `build_apk.sh` no lo permite: se niega a compilar
sin `key.properties` y, al terminar, comprueba con `comprobar_firma_apk.sh` que el APK lleva
**exactamente** el certificado de release antes de dejarlo en la raíz. El mismo script sirve
para revisar cualquier APK suelto:

```bash
./comprobar_firma_apk.sh dividi.apk
```

Compara la huella SHA-256 del certificado, que es pública (cualquiera la lee del APK):

```
3b8d4d0eb4a170940e49bdf22174f08b5c13934f3d20a8bf04f7583287db1b8c   CN=Dividi, O=DiegoAndresVega, C=ES
```

**Del keystore tiene que haber copia fuera de este ordenador**, y la contraseña guardada
aparte. Si se pierde no hay forma de recuperarlo.

**Las versiones anteriores a este cambio iban firmadas con la clave de depuración.** No se
pueden actualizar a una firmada con la de release: hay que desinstalar la app e instalar la
nueva una vez. Los datos viven en el servidor, así que solo se pierde la sesión.

R8 (reducción y ofuscación del código Java y Kotlin) lo activa en release el plugin de
Flutter. La ofuscación del código Dart (`--obfuscate`) no se usa: el código fuente es
público, así que no esconde nada y solo complicaría leer las trazas de error.

### Que el APK no lleve secretos

Lo que va dentro del APK lo puede leer cualquiera que lo descargue: basta con
descomprimirlo. La app no necesita ninguna credencial propia —solo conoce la URL pública de
la API, y los tokens de sesión los recibe al entrar—, y hay que comprobar que siga así:

```bash
./build_apk.sh
./comprobar_secretos_apk.sh
```

El script descomprime el APK de release y busca cualquier cosa con **forma de credencial**:
un JWT, una clave privada, claves de Google, AWS, GitHub, Stripe o Slack, o una URL con
usuario y contraseña. Mira el código Dart compilado, el de Android y los assets, y también el
manifiesto y los recursos, que van compilados y en parte en UTF-16, así que un `grep` sobre
el APK descomprimido no los ve: los decodifica con `aapt2` (Android SDK, build-tools). Sale
con `0` si no encuentra nada, con `1` si encuentra algo y con `2` si no ha podido revisarlo
entero.

Además lista, para mirarlos a ojo, los textos que contienen `password`, `token`, `secret`,
`api_key` o `bearer`, y las direcciones web del código Dart. Tienen que ser nombres de campo
(`access_token`, `new_password`…) y la URL de la API, nunca un valor.

Si algún día hace falta una clave de un servicio externo, no va en el código ni en un
`--dart-define`: va en la API, que es la que habla con ese servicio.
