import 'dart:convert';

/// Utilidades para mirar dentro de un JWT sin verificar la firma.
///
/// Solo se usan para decidir cosas de interfaz (¿sigo con sesión?, ¿quién
/// soy?). La validación de verdad la hace siempre el servidor.

/// Payload del token, o null si no es un JWT legible.
Map<String, dynamic>? payloadDeJwt(String token) {
  try {
    final partes = token.split('.');
    if (partes.length != 3) return null;
    final json = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
    final payload = jsonDecode(json);
    return payload is Map<String, dynamic> ? payload : null;
  } catch (_) {
    return null;
  }
}

/// ¿Caducó el token según su claim `exp`?
///
/// Un token sin `exp` legible se da por vivo: si de verdad no vale, el
/// servidor responderá 401 y la app cerrará sesión entonces.
bool tokenCaducado(String token, {DateTime? ahora}) {
  final exp = payloadDeJwt(token)?['exp'];
  if (exp is! int) return false;
  final caduca = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  return (ahora ?? DateTime.now()).toUtc().isAfter(caduca);
}
