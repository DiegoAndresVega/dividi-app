import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Error de la API con el mensaje ya extraído de la respuesta de FastAPI
/// (que viene en el campo `detail`, string o lista de errores de validación).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiClient {
  // VPS de Hostinger. HTTP plano hasta tener dominio con TLS; Android lo
  // permite solo para este host vía network_security_config.xml.
  static const String baseUrl = 'http://31.97.152.142:8000';

  final _storage = const FlutterSecureStorage();

  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: 'access_token');

  Future<bool> isLoggedIn() async => (await getAccessToken()) != null;

  /// Id del usuario con la sesión iniciada, leído del claim `sub` del JWT.
  /// Solo se decodifica el payload para mostrar datos propios en la interfaz;
  /// la verificación real del token la hace siempre el servidor.
  Future<String?> currentUserId() async {
    final token = await getAccessToken();
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List) {
        return detail.map((e) => e['msg']).join(', ');
      }
    } catch (_) {
      // el cuerpo no era JSON (p.ej. error 502 de la infraestructura)
    }
    return 'Error inesperado (código ${response.statusCode})';
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? inviteCode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'name': name,
        if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
      }),
    );
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> login({required String email, required String password}) async {
    // FastAPI expone /auth/login con OAuth2PasswordRequestForm: espera
    // application/x-www-form-urlencoded, no JSON.
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveTokens(body['access_token'], body['refresh_token']);
  }

  /// Envía una petición autenticada. Si el access token caducó (401),
  /// lo renueva con el refresh token y reintenta la petición una vez.
  Future<http.Response> _sendAuthorized(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    var response = await _rawRequest(method, path, body: body);
    if (response.statusCode == 401 && await _tryRefreshTokens()) {
      response = await _rawRequest(method, path, body: body);
    }
    return response;
  }

  Future<http.Response> _rawRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await getAccessToken();
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: jsonEncode(body));
      case 'PATCH':
        return http.patch(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        throw ArgumentError('Método no soportado: $method');
    }
  }

  Future<bool> _tryRefreshTokens() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;
    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await _saveTokens(body['access_token'], body['refresh_token']);
      return true;
    }
    if (response.statusCode == 401) {
      // el refresh token caducó de verdad: cerrar sesión local
      await logout();
    }
    // errores transitorios (5xx, timeouts del despertar del servidor...)
    // no tocan la sesión: el siguiente intento volverá a probar
    return false;
  }

  Future<http.Response> _authorizedGet(String path) => _sendAuthorized('GET', path);

  Future<http.Response> _authorizedPost(String path, Map<String, dynamic> body) =>
      _sendAuthorized('POST', path, body: body);

  Future<http.Response> _authorizedPatch(String path, Map<String, dynamic> body) =>
      _sendAuthorized('PATCH', path, body: body);

  Future<http.Response> _authorizedDelete(String path) =>
      _sendAuthorized('DELETE', path);

  Future<List<dynamic>> getGroups() async {
    final response = await _authorizedGet('/groups');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    String defaultCurrency = 'EUR',
  }) async {
    final response = await _authorizedPost('/groups', {
      'name': name,
      'default_currency': defaultCurrency,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Añade un miembro al grupo: invitado sin cuenta (solo displayName) o por
  /// email. `rebalance` reajusta los % del resto para que todo sume 100.
  Future<Map<String, dynamic>> addMember({
    required String groupId,
    String? displayName,
    String? email,
    required String defaultPercentage,
    Map<String, String>? rebalance,
  }) async {
    final response = await _authorizedPost('/groups/$groupId/members', {
      'display_name': ?displayName,
      'email': ?email,
      'default_percentage': defaultPercentage,
      'rebalance': ?rebalance,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getGroup(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getExpenses(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId/expenses');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Crea un gasto. `splits` define quién participa y cómo:
  /// - equal: [{'group_member_id': id}, ...] (o null = todo el grupo)
  /// - percentage: [{'group_member_id': id, 'percentage': '50'}, ...] (suma 100)
  Future<Map<String, dynamic>> createExpense({
    required String groupId,
    required String description,
    required String amount,
    required String paidBy,
    required String splitMethod,
    List<Map<String, dynamic>>? splits,
    String category = 'otros',
  }) async {
    final response = await _authorizedPost('/groups/$groupId/expenses', {
      'description': description,
      'amount': amount,
      'paid_by': paidBy,
      'split_method': splitMethod,
      'category': category,
      'splits': ?splits,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Edita un gasto existente; el backend recalcula el reparto.
  Future<Map<String, dynamic>> updateExpense({
    required String groupId,
    required String expenseId,
    required String description,
    required String amount,
    required String paidBy,
    required String splitMethod,
    List<Map<String, dynamic>>? splits,
    String category = 'otros',
  }) async {
    final response = await _authorizedPatch('/groups/$groupId/expenses/$expenseId', {
      'description': description,
      'amount': amount,
      'paid_by': paidBy,
      'split_method': splitMethod,
      'category': category,
      'splits': ?splits,
    });
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteExpense({required String groupId, required String expenseId}) async {
    final response = await _authorizedDelete('/groups/$groupId/expenses/$expenseId');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  Future<List<dynamic>> getBalances(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId/balances');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<List<dynamic>> getSettleUp(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId/settle-up');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Registra un pago entre dos miembros (p. ej. al saldar una sugerencia
  /// del settle-up). El backend lo refleja en los balances del grupo.
  Future<Map<String, dynamic>> createPayment({
    required String groupId,
    required String fromMemberId,
    required String toMemberId,
    required String amount,
    String? note,
  }) async {
    final response = await _authorizedPost('/groups/$groupId/payments', {
      'from_member_id': fromMemberId,
      'to_member_id': toMemberId,
      'amount': amount,
      'note': ?note,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
