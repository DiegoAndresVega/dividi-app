import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// Ejecuta una petición traduciendo los fallos de red a mensajes de la casa:
  /// nada de «ClientException: software caused connection abort».
  Future<http.Response> _pedir(Future<http.Response> Function() peticion) async {
    try {
      return await peticion().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(
          'El servidor tarda demasiado en responder. Inténtalo de nuevo en un momento.');
    } on SocketException {
      throw ApiException(
          'Sin conexión con el servidor. Revisa tu internet e inténtalo de nuevo.');
    } on http.ClientException {
      throw ApiException(
          'No se pudo conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.');
    }
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? inviteCode,
  }) async {
    final response = await _pedir(() => http.post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'name': name,
            if (inviteCode != null && inviteCode.isNotEmpty)
              'invite_code': inviteCode,
          }),
        ));
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> login({required String email, required String password}) async {
    // FastAPI expone /auth/login con OAuth2PasswordRequestForm: espera
    // application/x-www-form-urlencoded, no JSON.
    final response = await _pedir(() => http.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'username': email, 'password': password},
        ));
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
    return _pedir(() {
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'POST':
          return http.post(uri, headers: headers, body: jsonEncode(body));
        case 'PATCH':
          return http.patch(uri, headers: headers, body: jsonEncode(body));
        case 'PUT':
          return http.put(uri, headers: headers, body: jsonEncode(body));
        case 'DELETE':
          return http.delete(uri,
              headers: headers, body: body == null ? null : jsonEncode(body));
        default:
          throw ArgumentError('Método no soportado: $method');
      }
    });
  }

  Future<bool> _tryRefreshTokens() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;
    final http.Response response;
    try {
      response = await _pedir(() => http.post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          ));
    } on ApiException {
      // fallo de red durante el refresh: no tocar la sesión,
      // el siguiente intento volverá a probar
      return false;
    }
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

  Future<http.Response> _authorizedPut(String path, Map<String, dynamic> body) =>
      _sendAuthorized('PUT', path, body: body);

  Future<http.Response> _authorizedDelete(String path) =>
      _sendAuthorized('DELETE', path);

  Future<List<dynamic>> getGroups() async {
    final response = await _authorizedGet('/groups');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Crea un grupo. Opcionalmente con invitados ya incluidos: `members` es una
  /// lista de {display_name, default_percentage, email?} y `ownerPercentage`
  /// el peso del creador (todo debe sumar 100 si hay invitados).
  Future<Map<String, dynamic>> createGroup({
    required String name,
    String defaultCurrency = 'EUR',
    String? ownerPercentage,
    List<Map<String, dynamic>>? members,
  }) async {
    final response = await _authorizedPost('/groups', {
      'name': name,
      'default_currency': defaultCurrency,
      'owner_percentage': ?ownerPercentage,
      'members': ?members,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Añade un miembro al grupo: invitado sin cuenta (solo displayName), por
  /// email, o un amigo por su cuenta (`friendUserId`). `rebalance` reajusta los
  /// % del resto para que todo sume 100.
  Future<Map<String, dynamic>> addMember({
    required String groupId,
    String? displayName,
    String? email,
    String? friendUserId,
    required String defaultPercentage,
    Map<String, String>? rebalance,
  }) async {
    final response = await _authorizedPost('/groups/$groupId/members', {
      'display_name': ?displayName,
      'email': ?email,
      'user_id': ?friendUserId,
      'default_percentage': defaultPercentage,
      'rebalance': ?rebalance,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Edita un miembro del grupo (nombre, rol o su peso). `rebalance` reajusta
  /// a la vez los % del resto para que todo siga sumando 100.
  Future<Map<String, dynamic>> updateMember({
    required String groupId,
    required String memberId,
    String? displayName,
    String? role,
    String? defaultPercentage,
    Map<String, String>? rebalance,
  }) async {
    final response =
        await _authorizedPatch('/groups/$groupId/members/$memberId', {
      'display_name': ?displayName,
      'role': ?role,
      'default_percentage': ?defaultPercentage,
      'rebalance': ?rebalance,
    });
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Elimina un miembro del grupo. `rebalance` reparte su peso entre el resto.
  Future<void> removeMember({
    required String groupId,
    required String memberId,
    Map<String, String>? rebalance,
  }) async {
    final response = await _sendAuthorized(
      'DELETE',
      '/groups/$groupId/members/$memberId',
      body: rebalance == null ? null : {'rebalance': rebalance},
    );
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  Future<Map<String, dynamic>> getGroup(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Lista los gastos del grupo; la API filtra en servidor por categoría
  /// y rango de fechas (`category`, `date_from`, `date_to`).
  Future<List<dynamic>> getExpenses(
    String groupId, {
    String? category,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final params = <String, String>{
      'category': ?category,
      'date_from': ?dateFrom?.toUtc().toIso8601String(),
      'date_to': ?dateTo?.toUtc().toIso8601String(),
    };
    final query =
        params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    final response = await _authorizedGet('/groups/$groupId/expenses$query');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<List<dynamic>> getPayments(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId/payments');
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
    String? categoryIcon,
  }) async {
    final response = await _authorizedPost('/groups/$groupId/expenses', {
      'description': description,
      'amount': amount,
      'paid_by': paidBy,
      'split_method': splitMethod,
      'category': category,
      'category_icon': ?categoryIcon,
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
    String? categoryIcon,
  }) async {
    final response = await _authorizedPatch('/groups/$groupId/expenses/$expenseId', {
      'description': description,
      'amount': amount,
      'paid_by': paidBy,
      'split_method': splitMethod,
      'category': category,
      // siempre presente: null limpia el emoji al volver a una predefinida
      'category_icon': categoryIcon,
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

  // ---------------------------------------------------------------- perfil

  Future<Map<String, dynamic>> getMe() async {
    final response = await _authorizedGet('/me');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMe({required String name}) async {
    final response = await _authorizedPatch('/me', {'name': name});
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _authorizedPost('/me/password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  // ----------------------------------------------------------- invitaciones

  Future<List<dynamic>> getInvitations() async {
    final response = await _authorizedGet('/invitations');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Genera un código de invitación; opcionalmente atado a un email
  /// o con caducidad en días.
  Future<Map<String, dynamic>> createInvitation({
    String? email,
    int? expiresInDays,
  }) async {
    final response = await _authorizedPost('/invitations', {
      'email': ?email,
      'expires_in_days': ?expiresInDays,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> revokeInvitation(String invitationId) async {
    final response = await _authorizedDelete('/invitations/$invitationId');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  // ------------------------------------------------------- recurrentes (M7)

  Future<List<dynamic>> getRecurring(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId/recurring');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Crea una regla mensual: el gasto se apunta solo el día indicado con
  /// el reparto del grupo vigente ese día.
  Future<Map<String, dynamic>> createRecurring({
    required String groupId,
    required String description,
    required String amount,
    required String category,
    String? categoryIcon,
    required String paidBy,
    required String splitMethod,
    required int dayOfMonth,
  }) async {
    final response = await _authorizedPost('/groups/$groupId/recurring', {
      'description': description,
      'amount': amount,
      'category': category,
      'category_icon': ?categoryIcon,
      'paid_by': paidBy,
      'split_method': splitMethod,
      'day_of_month': dayOfMonth,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateRecurring({
    required String groupId,
    required String ruleId,
    bool? active,
    String? amount,
    int? dayOfMonth,
  }) async {
    final response = await _authorizedPatch('/groups/$groupId/recurring/$ruleId', {
      'active': ?active,
      'amount': ?amount,
      'day_of_month': ?dayOfMonth,
    });
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteRecurring({
    required String groupId,
    required String ruleId,
  }) async {
    final response = await _authorizedDelete('/groups/$groupId/recurring/$ruleId');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  // ------------------------------------------------- exportación y tique

  /// CSV completo del grupo (gastos, pagos, balances y settle-up).
  Future<String> exportGroupCsv(String groupId) async {
    final response = await _authorizedGet('/groups/$groupId/export');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return utf8.decode(response.bodyBytes);
  }

  /// Cabeceras con el token, para cargar imágenes protegidas (Image.network).
  Future<Map<String, String>> authHeaders() async {
    final token = await getAccessToken();
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> uploadReceipt({
    required String groupId,
    required String expenseId,
    required String filePath,
  }) async {
    final uri =
        Uri.parse('$baseUrl/groups/$groupId/expenses/$expenseId/receipt');
    Future<http.Response> enviar() async {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await authHeaders())
        ..files.add(await http.MultipartFile.fromPath('file', filePath));
      return http.Response.fromStream(await request.send());
    }

    var response = await _pedir(enviar);
    if (response.statusCode == 401 && await _tryRefreshTokens()) {
      response = await _pedir(enviar);
    }
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteReceipt({
    required String groupId,
    required String expenseId,
  }) async {
    final response =
        await _authorizedDelete('/groups/$groupId/expenses/$expenseId/receipt');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  // ------------------------------------- Mi dinero: resumen y personales

  /// El mes completo: gastos personales + tu parte de cada grupo, por
  /// categoría, con la nómina y los techos si están declarados.
  Future<Map<String, dynamic>> getMySummary({String? period}) async {
    final query = period == null ? '' : '?period=$period';
    final response = await _authorizedGet('/me/summary$query');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMyFinances() async {
    final response = await _authorizedGet('/me/finances');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Reemplaza la configuración financiera entera (nómina + presupuestos).
  Future<Map<String, dynamic>> putMyFinances({
    String? monthlyIncome,
    required List<Map<String, String>> budgets,
  }) async {
    final response = await _authorizedPut('/me/finances', {
      'monthly_income': monthlyIncome,
      'budgets': budgets,
    });
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getPersonalExpenses() async {
    final response = await _authorizedGet('/me/expenses');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createPersonalExpense({
    required String description,
    required String amount,
    required String category,
    String? categoryIcon,
  }) async {
    final response = await _authorizedPost('/me/expenses', {
      'description': description,
      'amount': amount,
      'category': category,
      'category_icon': ?categoryIcon,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updatePersonalExpense({
    required String expenseId,
    required String description,
    required String amount,
    required String category,
    String? categoryIcon,
  }) async {
    final response = await _authorizedPatch('/me/expenses/$expenseId', {
      'description': description,
      'amount': amount,
      'category': category,
      // siempre presente: null limpia el emoji al volver a una predefinida
      'category_icon': categoryIcon,
    });
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deletePersonalExpense(String expenseId) async {
    final response = await _authorizedDelete('/me/expenses/$expenseId');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  // ------------------------------------------------------------- Mi dinero

  Future<List<dynamic>> getSavingsPlans() async {
    final response = await _authorizedGet('/savings-plans');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getSavingsPlan(String planId) async {
    final response = await _authorizedGet('/savings-plans/$planId');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Crea un plan de ahorro. `savedAmount` es lo ya apartado (opcional).
  Future<Map<String, dynamic>> createSavingsPlan({
    required String name,
    required String targetAmount,
    required String monthlyAmount,
    String? savedAmount,
  }) async {
    final response = await _authorizedPost('/savings-plans', {
      'name': name,
      'target_amount': targetAmount,
      'monthly_amount': monthlyAmount,
      'saved_amount': ?savedAmount,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSavingsPlan({
    required String planId,
    String? name,
    String? targetAmount,
    String? monthlyAmount,
  }) async {
    final response = await _authorizedPatch('/savings-plans/$planId', {
      'name': ?name,
      'target_amount': ?targetAmount,
      'monthly_amount': ?monthlyAmount,
    });
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteSavingsPlan(String planId) async {
    final response = await _authorizedDelete('/savings-plans/$planId');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  /// Movimiento de la hucha de un plan. `kind`:
  /// - `monthly`: cierra un mes con la cantidad realmente lograda (puede ser 0;
  ///   sin `period` se asume el mes en curso).
  /// - `adjustment`: ajuste manual ± en cualquier momento, sin justificar.
  /// Devuelve el plan actualizado con sus movimientos.
  Future<Map<String, dynamic>> addSavingsEntry({
    required String planId,
    required String kind,
    required String amount,
    String? period,
  }) async {
    final response = await _authorizedPost('/savings-plans/$planId/entries', {
      'kind': kind,
      'amount': amount,
      'period': ?period,
    });
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------- amigos

  Future<List<dynamic>> getFriends() async {
    final response = await _authorizedGet('/friends');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Solicitudes de amistad pendientes que has recibido.
  Future<List<dynamic>> getFriendRequests() async {
    final response = await _authorizedGet('/friends/requests');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Envía una solicitud de amistad por email. Devuelve 'pending' o, si esa
  /// persona ya te la había enviado, 'accepted' (se acepta sola).
  Future<String> sendFriendRequest(String email) async {
    final response = await _authorizedPost('/friends/requests', {'email': email});
    if (response.statusCode != 201) {
      throw ApiException(_extractErrorMessage(response));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['status'] as String;
  }

  Future<void> acceptFriendRequest(String requestId) async {
    final response =
        await _sendAuthorized('POST', '/friends/requests/$requestId/accept');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  /// Rechaza (si la recibiste) o cancela (si la enviaste) una solicitud.
  Future<void> declineFriendRequest(String requestId) async {
    final response = await _authorizedDelete('/friends/requests/$requestId');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  Future<void> removeFriend(String friendshipId) async {
    final response = await _authorizedDelete('/friends/$friendshipId');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  // --------------------------------------------------------- notificaciones

  Future<List<dynamic>> getNotifications() async {
    final response = await _authorizedGet('/notifications');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<int> getUnreadCount() async {
    final response = await _authorizedGet('/notifications/unread-count');
    if (response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['unread'] as int;
  }

  Future<void> markAllNotificationsRead() async {
    final response = await _sendAuthorized('POST', '/notifications/read-all');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final response =
        await _sendAuthorized('POST', '/notifications/$notificationId/read');
    if (response.statusCode != 204) {
      throw ApiException(_extractErrorMessage(response));
    }
  }
}
