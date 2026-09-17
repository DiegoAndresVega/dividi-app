import 'dart:io';

import 'package:dividi/services/api_base_url.dart';
import 'package:dividi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// La URL de producción, escrita aquí a mano a propósito: si alguien la cambia
/// en el código sin querer, este test lo dice.
const _produccion = 'https://dividi.finkafest.es';

void main() {
  test('sin --dart-define, la app apunta a producción', () {
    // el olvido más probable es compilar la release sin pasar la variable, y
    // ese caso tiene que dar la URL buena, no una de pruebas
    expect(apiBaseUrl, _produccion);
  });

  test('el cliente de la API usa esa URL y no otra', () {
    expect(ApiClient.baseUrl, apiBaseUrl);
  });

  test('una URL con barra final se queda sin ella', () {
    // si no, las peticiones salen como http://…:8000//auth/login
    expect(normalizarBaseUrl('http://10.0.2.2:8000/'), 'http://10.0.2.2:8000');
    expect(normalizarBaseUrl('http://10.0.2.2:8000///'), 'http://10.0.2.2:8000');
  });

  test('los espacios sobrantes no cuentan', () {
    expect(normalizarBaseUrl('  https://ejemplo.test  '), 'https://ejemplo.test');
  });

  test('un valor vacío cae en producción', () {
    // --dart-define=API_BASE_URL= (o sin definir) no puede dejar la app sin API
    expect(normalizarBaseUrl(''), _produccion);
    expect(normalizarBaseUrl('   '), _produccion);
  });

  test('ningún otro fichero de lib/ escribe la URL de la API', () {
    // el objetivo del punto: cambiar de servidor no puede exigir editar código,
    // y para eso la URL tiene que estar en un solo sitio
    const permitidos = {'lib/services/api_base_url.dart'};
    final infractores = <String>[];

    for (final fichero in Directory('lib').listSync(recursive: true)) {
      if (fichero is! File || !fichero.path.endsWith('.dart')) continue;
      final ruta = fichero.path.replaceAll(r'\', '/');
      if (permitidos.contains(ruta)) continue;
      if (fichero.readAsStringSync().contains(_produccion)) {
        infractores.add(ruta);
      }
    }

    expect(
      infractores,
      isEmpty,
      reason: 'la URL de la API se lee de api_base_url.dart, que la saca de '
          '--dart-define=API_BASE_URL',
    );
  });
}
