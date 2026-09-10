import 'dart:convert';

import 'package:dividi/services/api_client.dart';
import 'package:dividi/services/registro_seguro.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jwt =
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSIsImV4cCI6NDEwMjQ0NDgwMH0.firma-secreta';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('enmascararSecretos', () {
    test('tapa el valor de la cabecera Authorization y deja el nombre', () {
      // Arrange
      final linea = 'GET /groups con Authorization: Bearer $_jwt';

      // Act
      final limpio = enmascararSecretos(linea);

      // Assert
      expect(limpio, contains('Authorization'));
      expect(limpio, isNot(contains(_jwt)));
    });

    test('tapa cualquier cosa con forma de JWT, venga de donde venga', () {
      expect(enmascararSecretos('el token es $_jwt y ya'), isNot(contains(_jwt)));
    });

    test('tapa los campos de token del cuerpo de una respuesta', () {
      // Arrange
      final cuerpo = jsonEncode({
        'access_token': 'abc123',
        'refresh_token': 'def456',
      });

      // Act
      final limpio = enmascararSecretos(cuerpo);

      // Assert
      expect(limpio, isNot(contains('abc123')));
      expect(limpio, isNot(contains('def456')));
      expect(limpio, contains('access_token'));
    });

    test('tapa la contraseña de un formulario de login', () {
      expect(
        enmascararSecretos('username=a@b.com&password=hunter2'),
        isNot(contains('hunter2')),
      );
    });

    test('no estropea un mensaje normal', () {
      const mensaje = 'No se pudo conectar con el servidor';
      expect(enmascararSecretos(mensaje), mensaje);
    });
  });

  group('ApiException', () {
    test('nunca muestra un token, aunque el servidor lo devuelva', () async {
      // Arrange: un servidor que se equivoca y mete el token en el detalle
      FlutterSecureStorage.setMockInitialValues({'access_token': _jwt});
      final cliente = ApiClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'detail': 'token invalido: $_jwt'}),
              400,
            )),
      );

      // Act
      final error = await cliente
          .getGroups()
          .then<Object?>((_) => null)
          .catchError((Object e) => e);

      // Assert
      expect(error, isA<ApiException>());
      expect(error.toString(), isNot(contains(_jwt)));
    });
  });
}
