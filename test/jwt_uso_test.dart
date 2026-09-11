import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardián del criterio del punto 10: ninguna decisión de permisos puede
/// apoyarse en `lib/services/jwt.dart`.
///
/// El payload de un JWT se lee sin verificar la firma, así que vale para la
/// interfaz —¿sigo con sesión?— y para nada más. Esto no se puede comprobar
/// leyendo un valor en tiempo de ejecución: lo que hay que vigilar es que
/// nadie vuelva a usarlo en otro sitio dentro de seis meses. Por eso el test
/// mira el código fuente.
/// Cualquier nombre que tenga hoy la función que abre el payload: el guardián
/// no puede depender de cómo se llame mañana.
final _leePayload = RegExp(r'payload\w*DeJwt');

/// El id del usuario sacado del token, escrito de cualquiera de las formas.
final _identidadDelToken = RegExp(r"payload\w*DeJwt\(token\)\?\['sub'\]");

void main() {
  const permitidos = {
    'lib/services/jwt.dart',
    // lee `exp` para saber si la sesión sigue viva; no decide permisos
    'lib/services/api_client.dart',
  };

  test('solo el propio jwt.dart y el cliente de la API leen el payload', () {
    final infractores = <String>[];

    for (final fichero in Directory('lib').listSync(recursive: true)) {
      if (fichero is! File || !fichero.path.endsWith('.dart')) continue;
      final ruta = fichero.path.replaceAll(r'\', '/');
      if (permitidos.contains(ruta)) continue;
      if (_leePayload.hasMatch(fichero.readAsStringSync())) {
        infractores.add(ruta);
      }
    }

    expect(
      infractores,
      isEmpty,
      reason: 'el payload del token no está verificado: si hace falta saber '
          'quién es el usuario, pregúntaselo al servidor con currentUserId()',
    );
  });

  test('el cliente de la API no saca la identidad del token', () {
    final fuente = File('lib/services/api_client.dart').readAsStringSync();

    expect(
      _identidadDelToken.hasMatch(fuente),
      isFalse,
      reason: 'el id del usuario tiene que venir de /me, no del JWT',
    );
  });
}
