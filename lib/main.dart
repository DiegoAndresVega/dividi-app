// Dividi — app de gastos compartidos.
// Autor: Diego Andres Vega Silva.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'theme/dividi_theme.dart';
import 'widgets/dividi_logo.dart';

/// Claves globales: permiten llevar al usuario al login y avisarle desde
/// fuera del árbol de widgets, cuando el aviso llega de la capa de red.
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ApiClient.onSessionExpired = _volverAlLogin;
  runApp(const MyApp());
}

/// La sesión caducó (un año entero sin abrir la app): sacar al usuario al
/// login desde donde esté, sin dejar pantallas viejas detrás, y explicar por
/// qué en vez de mostrar errores sueltos.
void _volverAlLogin() {
  navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
  scaffoldMessengerKey.currentState
    ?..clearSnackBars()
    ..showSnackBar(
      const SnackBar(
        content: Text('Tu sesión ha caducado. Vuelve a iniciar sesión.'),
      ),
    );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dividi',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: DividiTheme.claro(),
      darkTheme: DividiTheme.oscuro(),
      themeMode: ThemeMode.system,
      // selectores de fecha y textos del sistema en español
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const StartupScreen(),
    );
  }
}

/// Comprueba si ya hay una sesión guardada para saltar directamente a
/// la pantalla de grupos, en vez de pedir login cada vez que se abre la app.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    _decideStartScreen();
  }

  Future<void> _decideStartScreen() async {
    final loggedIn = await _apiClient.isLoggedIn();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => loggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DividiLogo(size: 96),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
