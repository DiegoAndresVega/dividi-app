import 'dart:convert';

import 'package:dividi/services/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Token con `exp` en el año 2100: `isLoggedIn` mira si caducó, así que no
/// puede ser una cadena cualquiera.
String jwtQueNoCaduca() {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${b64({'sub': 'u1', 'exp': 4102444800})}.firma';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': jwtQueNoCaduca(),
      'refresh_token': jwtQueNoCaduca(),
    });
    ApiClient.onSessionExpired = null;
  });

  test('cerrar sesión avisa al servidor con el refresh token', () async {
    // Arrange
    final llamadas = <http.Request>[];
    final cliente = ApiClient(
      httpClient: MockClient((request) async {
        llamadas.add(request);
        return http.Response('', 204);
      }),
    );

    // Act
    await cliente.logout();

    // Assert
    expect(llamadas, hasLength(1));
    expect(llamadas.single.url.path, '/auth/logout');
    expect(llamadas.single.method, 'POST');
    expect(
      jsonDecode(llamadas.single.body)['refresh_token'],
      jwtQueNoCaduca(),
    );
  });

  test('cerrar sesión borra los tokens aunque el servidor no conteste',
      () async {
    // Arrange
    final cliente = ApiClient(
      httpClient: MockClient(
        (_) async => throw http.ClientException('sin red'),
      ),
    );

    // Act
    await cliente.logout();

    // Assert
    expect(await cliente.isLoggedIn(), isFalse);
    expect(await cliente.getAccessToken(), isNull);
  });

  test('sin refresh token guardado no se llama al servidor', () async {
    // Arrange
    FlutterSecureStorage.setMockInitialValues({});
    var llamadas = 0;
    final cliente = ApiClient(
      httpClient: MockClient((_) async {
        llamadas++;
        return http.Response('', 204);
      }),
    );

    // Act
    await cliente.logout();

    // Assert
    expect(llamadas, 0);
  });

  test('un refresh rechazado borra los dos tokens sin volver a llamar a logout',
      () async {
    // Arrange
    final rutas = <String>[];
    var expirada = false;
    ApiClient.onSessionExpired = () => expirada = true;
    final cliente = ApiClient(
      httpClient: MockClient((request) async {
        rutas.add(request.url.path);
        if (request.url.path == '/auth/refresh') {
          return http.Response('{"detail":"no vale"}', 401);
        }
        return http.Response('{"detail":"no autorizado"}', 401);
      }),
    );

    // Act
    await expectLater(cliente.getGroups(), throwsA(isA<ApiException>()));

    // Assert
    expect(rutas, isNot(contains('/auth/logout')));
    expect(await cliente.getAccessToken(), isNull);
    expect(await cliente.isLoggedIn(), isFalse);
    expect(expirada, isTrue);
  });

  test('varias peticiones a la vez gastan el refresh token una sola vez',
      () async {
    // Arrange: el access token guardado esta caducado, asi que las tres
    // peticiones se toparan con un 401 antes de que ninguna haya refrescado
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'viejo',
      'refresh_token': jwtQueNoCaduca(),
    });
    var refrescos = 0;
    final cliente = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refrescos++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
            jsonEncode({
              'access_token': 'nuevo',
              'refresh_token': jwtQueNoCaduca(),
            }),
            200,
          );
        }
        final autorizacion = request.headers['Authorization'];
        if (autorizacion == 'Bearer viejo') {
          return http.Response('{"detail":"caducado"}', 401);
        }
        return http.Response('[]', 200);
      }),
    );

    // Act
    await Future.wait<void>([
      cliente.getGroups(),
      cliente.getGroups(),
      cliente.getGroups(),
    ]);

    // Assert
    expect(refrescos, 1);
  });
}
