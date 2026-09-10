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
