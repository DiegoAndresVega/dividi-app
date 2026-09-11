import 'dart:convert';

import 'package:dividi/services/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// De quién es la sesión, según quién lo dice (punto 10).
///
/// El payload de un JWT se lee sin verificar la firma: cualquiera con el
/// teléfono en la mano puede reescribir el `sub` y la app se lo creería. Por
/// eso la identidad sale de `/me`, que responde el servidor después de
/// verificar el token de verdad. El JWT solo sirve para saber si la sesión
/// sigue viva, que es una cuestión de interfaz, no un permiso.
///
/// El caso que mide esto: un token cuyo `sub` dice una cosa y un servidor que
/// dice otra. Manda el servidor.
String _jwtCon(String sub) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${b64({'sub': sub, 'exp': 4102444800})}.firma';
}

const _idDelServidor = 'id-de-verdad';
const _idDelToken = 'id-inventado';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': _jwtCon(_idDelToken),
      'refresh_token': _jwtCon(_idDelToken),
    });
    ApiClient.onSessionExpired = null;
  });

  http.Client servidorQueDice(String id, {List<http.Request>? llamadas}) {
    return MockClient((request) async {
      llamadas?.add(request);
      if (request.url.path == '/me') {
        return http.Response(
          jsonEncode({'id': id, 'email': 'ana@example.com', 'name': 'Ana'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 404);
    });
  }

  test('la identidad la da el servidor, no el payload del token', () async {
    // Arrange
    final cliente = ApiClient(httpClient: servidorQueDice(_idDelServidor));

    // Act
    final id = await cliente.currentUserId();

    // Assert
    expect(id, _idDelServidor);
    expect(id, isNot(_idDelToken));
  });

  test('pregunta a /me una sola vez y recuerda la respuesta', () async {
    // Arrange
    final llamadas = <http.Request>[];
    final cliente = ApiClient(
      httpClient: servidorQueDice(_idDelServidor, llamadas: llamadas),
    );

    // Act
    await cliente.currentUserId();
    await cliente.currentUserId();

    // Assert
    expect(llamadas.where((r) => r.url.path == '/me'), hasLength(1));
  });

  test('sin sesión no pregunta a nadie y devuelve null', () async {
    // Arrange
    FlutterSecureStorage.setMockInitialValues({});
    final llamadas = <http.Request>[];
    final cliente = ApiClient(
      httpClient: servidorQueDice(_idDelServidor, llamadas: llamadas),
    );

    // Act
    final id = await cliente.currentUserId();

    // Assert
    expect(id, isNull);
    expect(llamadas, isEmpty);
  });

  test('si el servidor rechaza la sesión, la identidad es null', () async {
    // Arrange
    final cliente = ApiClient(
      httpClient: MockClient((_) async => http.Response('', 401)),
    );

    // Act
    final id = await cliente.currentUserId();

    // Assert
    expect(id, isNull);
  });

  test('al cerrar sesión se olvida quién era', () async {
    // Arrange
    final cliente = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/me') {
          return http.Response(
            jsonEncode({'id': _idDelServidor}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 204);
      }),
    );
    expect(await cliente.currentUserId(), _idDelServidor);

    // Act
    await cliente.logout();

    // Assert
    expect(await cliente.currentUserId(), isNull);
  });

  test('un login nuevo no arrastra la identidad del usuario anterior',
      () async {
    // Arrange: el primer usuario queda recordado
    var idQueResponde = _idDelServidor;
    final cliente = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/me') {
          return http.Response(
            jsonEncode({'id': idQueResponde}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'access_token': _jwtCon('otro'),
            'refresh_token': _jwtCon('otro'),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    expect(await cliente.currentUserId(), _idDelServidor);

    // Act: entra otra persona en el mismo teléfono
    idQueResponde = 'otro-usuario';
    await cliente.login(email: 'bea@example.com', password: 'password123');

    // Assert
    expect(await cliente.currentUserId(), 'otro-usuario');
  });
}
