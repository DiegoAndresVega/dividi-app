import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dividi/services/jwt.dart';

/// Construye un JWT de mentira (firma basura): estas utilidades solo leen el
/// payload, la firma la comprueba el servidor.
String tokenCon(Map<String, dynamic> claims) {
  String trozo(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${trozo({'alg': 'HS256'})}.${trozo(claims)}.firma-de-mentira';
}

int enSegundos(DateTime fecha) => fecha.millisecondsSinceEpoch ~/ 1000;

void main() {
  group('payloadSinVerificarDeJwt', () {
    test('devuelve los claims de un token bien formado', () {
      // Arrange
      final token = tokenCon({'sub': 'usuario-1', 'type': 'refresh'});

      // Act
      final payload = payloadSinVerificarDeJwt(token);

      // Assert
      expect(payload?['sub'], 'usuario-1');
      expect(payload?['type'], 'refresh');
    });

    test('devuelve null si el token no tiene tres partes', () {
      expect(payloadSinVerificarDeJwt('esto-no-es-un-jwt'), isNull);
    });

    test('devuelve null si el payload no es base64 válido', () {
      expect(payloadSinVerificarDeJwt('cabecera.###.firma'), isNull);
    });
  });

  group('tokenCaducado', () {
    final ahora = DateTime.utc(2026, 8, 27, 12);

    test('es falso mientras quede tiempo por delante', () {
      // Arrange: un año de sesión, como los que emite la API
      final token = tokenCon({
        'exp': enSegundos(ahora.add(const Duration(days: 365))),
      });

      // Act & Assert
      expect(tokenCaducado(token, ahora: ahora), isFalse);
    });

    test('es verdadero cuando la fecha ya pasó', () {
      final token = tokenCon({
        'exp': enSegundos(ahora.subtract(const Duration(minutes: 1))),
      });

      expect(tokenCaducado(token, ahora: ahora), isTrue);
    });

    test('da el token por vivo si no trae fecha de caducidad legible', () {
      expect(tokenCaducado(tokenCon({'sub': 'usuario-1'}), ahora: ahora),
          isFalse);
      expect(tokenCaducado('token-ilegible', ahora: ahora), isFalse);
    });
  });
}
