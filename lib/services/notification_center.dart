import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Avisos locales del centro de novedades (M-social).
///
/// Sin push: al abrir la app se comprueba si hay notificaciones sin leer más
/// recientes que la última que ya avisamos y, si las hay, se muestra un aviso
/// local del sistema. Guardamos la fecha de la última avisada para no repetir.
class NotificationCenter {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _storage = FlutterSecureStorage();
  static const _idNovedades = 2; // el 1 lo usa DebtReminder
  static const _claveUltima = 'notif_ultima_avisada';
  static bool _listo = false;

  static Future<void> _init() async {
    if (_listo) return;
    const ajustes = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: ajustes);
    _listo = true;
  }

  /// Revisa la lista de notificaciones (tal como llega de la API) y muestra un
  /// aviso local si hay novedades sin leer que aún no habíamos avisado.
  static Future<void> revisar(List<dynamic> notificaciones) async {
    try {
      final sinLeer = notificaciones
          .where((n) => n['read_at'] == null && n['created_at'] != null)
          .toList();
      if (sinLeer.isEmpty) return;

      sinLeer.sort((a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String));
      final masReciente = sinLeer.first['created_at'] as String;

      final ultima = await _storage.read(key: _claveUltima);
      if (ultima != null && ultima.compareTo(masReciente) >= 0) return;

      await _init();
      final nuevas =
          ultima == null ? sinLeer : sinLeer.where((n) => (n['created_at'] as String).compareTo(ultima) > 0).toList();
      final cuantas = nuevas.isEmpty ? sinLeer.length : nuevas.length;

      final title =
          cuantas == 1 ? (nuevas.isNotEmpty ? nuevas.first['title'] : sinLeer.first['title']) as String : 'Tienes $cuantas novedades';
      final body = cuantas == 1
          ? (nuevas.isNotEmpty ? nuevas.first['body'] : sinLeer.first['body']) as String
          : 'Ábrelas en Dividi para verlas.';

      await _plugin.show(
        id: _idNovedades,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'novedades',
            'Novedades',
            channelDescription:
                'Solicitudes de amistad y grupos a los que te añaden',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
      await _storage.write(key: _claveUltima, value: masReciente);
    } catch (_) {
      // un aviso jamás debe tumbar la pantalla de inicio
    }
  }
}
