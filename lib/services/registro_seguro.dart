import 'package:flutter/foundation.dart';

/// Trazas que no dejan el token escrito en ningún sitio.
///
/// Un `print(response.body)` puesto durante una depuración deja el JWT en
/// logcat, que en Android leen otras aplicaciones en dispositivos rooteados y
/// que acaba entero en cualquier informe de fallo. Por eso `avoid_print` está
/// como error en `analysis_options.yaml`: para que ese atajo no compile.
///
/// Esto es lo que se usa en su lugar. Solo escribe en depuración, y antes de
/// escribir tapa lo que no debe salir.

const String _mascara = '***';

/// Cada patrón conserva la parte que sirve para depurar —qué cabecera, qué
/// campo— y tapa solo el valor.
final List<RegExp> _patrones = [
  // Authorization: Bearer <token>
  RegExp(r'(authorization"?\s*[:=]\s*"?\s*(?:bearer|basic)\s+)\S+',
      caseSensitive: false),
  // password, token, access_token... en JSON o en formulario
  RegExp(
    r'("?(?:password|contrasena|secret|token|access_token|refresh_token|api_key)"?'
    r'\s*[:=]\s*)"?[^\s,;&}"]+',
    caseSensitive: false,
  ),
  // Cualquier cosa con forma de JWT
  RegExp(r'\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
];

/// Devuelve el texto con los valores sensibles sustituidos por `***`.
///
/// Se usa tanto para las trazas como para los mensajes de error que van a la
/// pantalla: el servidor no debería devolver nunca un token dentro de un
/// `detail`, pero el que decide qué se enseña al usuario es esta aplicación.
String enmascararSecretos(String texto) {
  var limpio = texto;
  for (final patron in _patrones) {
    limpio = limpio.replaceAllMapped(patron, _sustituir);
  }
  return limpio;
}

String _sustituir(Match coincidencia) {
  final conservado = coincidencia.groupCount >= 1 ? coincidencia.group(1) : null;
  return conservado == null ? _mascara : '$conservado$_mascara';
}

/// Escribe una traza, solo en depuración y siempre enmascarada.
///
/// En release no hace nada: `kDebugMode` es constante, así que el compilador
/// se lleva por delante tanto la llamada como el texto que la acompaña.
void trazarEnDepuracion(String mensaje) {
  if (!kDebugMode) return;
  debugPrint(enmascararSecretos(mensaje));
}
