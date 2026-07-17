import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../theme/dividi_format.dart';

/// Recordatorio suave de deudas (M10).
///
/// Sin servidor de push: la propia app programa una notificación local
/// cuando sales debiendo dinero entre tus grupos, y la cancela en cuanto
/// vuelves a estar en paz. Firme con las cuentas, nunca con las personas.
class DebtReminder {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _idRecordatorio = 1;
  static const _diasDeMargen = 3;
  static bool _listo = false;

  static Future<void> _init() async {
    if (_listo) return;
    tzdata.initializeTimeZones();
    const ajustes = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: ajustes);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _listo = true;
  }

  /// Se llama en cada carga del inicio con el saldo global del usuario.
  /// Con deuda: (re)programa el aviso para dentro de unos días — si para
  /// entonces sigue igual y no ha abierto la app, sonará. En paz: lo cancela.
  static Future<void> actualizar(double saldoTotal) async {
    try {
      await _init();
      await _plugin.cancel(id: _idRecordatorio);
      if (saldoTotal >= -0.004) return;

      await _plugin.zonedSchedule(
        id: _idRecordatorio,
        title: 'Cuentas pendientes',
        body: 'Sigues debiendo ${formatearImporte(-saldoTotal)} entre tus '
            'grupos. Un settle-up y en paz.',
        scheduledDate:
            tz.TZDateTime.now(tz.local).add(const Duration(days: _diasDeMargen)),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'deudas',
            'Recordatorios de deudas',
            channelDescription:
                'Aviso suave cuando llevas días debiendo dinero',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // un recordatorio jamás debe tumbar la pantalla de inicio
    }
  }
}
