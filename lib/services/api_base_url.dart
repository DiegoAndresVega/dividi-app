/// De dónde sale la dirección de la API.
///
/// Está en un fichero propio y en una sola constante para que apuntar la app a
/// otro servidor sea cosa de la línea de compilación y no de editar código:
///
/// ```bash
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// ```
///
/// Sin esa variable queda la de producción, que es el valor que tiene que
/// salir cuando alguien compila una release y se olvida de pasar nada.
library;

/// API en la VPS de Hostinger, tras el proxy Caddy con certificado de
/// Let's Encrypt.
const String urlDeProduccion = 'https://dividi.finkafest.es';

/// Lo que se haya pasado al compilar. `String.fromEnvironment` es constante:
/// el valor se resuelve al compilar y viaja dentro del binario, así que no hay
/// forma de cambiarlo después sin volver a compilar.
const String _urlDeCompilacion = String.fromEnvironment('API_BASE_URL');

/// La dirección contra la que habla la app.
final String apiBaseUrl = normalizarBaseUrl(_urlDeCompilacion);

/// Deja la URL como la esperan las peticiones: sin espacios y sin barra final.
///
/// Las rutas se pegan detrás (`'$apiBaseUrl/auth/login'`), así que una barra de
/// más se convierte en `//auth/login`. Y un valor vacío —la variable sin
/// definir, o definida pero sin nada— cae en producción antes que dejar la app
/// hablando con ninguna parte.
String normalizarBaseUrl(String valor) {
  final limpia = valor.trim().replaceAll(RegExp(r'/+$'), '');
  if (limpia.isEmpty) return urlDeProduccion;
  assert(
    limpia.startsWith('https://') || limpia.startsWith('http://'),
    'API_BASE_URL tiene que empezar por http:// o https://, y llegó: $valor',
  );
  return limpia;
}
