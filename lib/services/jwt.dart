import 'dart:convert';

/// Utilidades para mirar dentro de un JWT **sin verificar la firma**.
///
/// El token vive en el propio teléfono, así que su contenido es un dato que
/// pone el usuario: reescribir el `sub` y volver a montar el JWT no cuesta
/// nada, porque aquí nadie comprueba la firma. Vale para decidir cosas de
/// interfaz —¿sigo con sesión?— y para nada más.
///
/// **Nunca decidas permisos con esto.** Quién es el usuario y qué puede hacer
/// lo responde el servidor, que sí verifica el token: `ApiClient.currentUserId()`
/// y el `role` que viene con cada grupo. Hay un test que lo vigila
/// (`test/jwt_uso_test.dart`).

/// Payload del token **sin verificar**, o null si no es un JWT legible.
Map<String, dynamic>? payloadSinVerificarDeJwt(String token) {
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
  final exp = payloadSinVerificarDeJwt(token)?['exp'];
  if (exp is! int) return false;
  final caduca = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  return (ahora ?? DateTime.now()).toUtc().isAfter(caduca);
}
