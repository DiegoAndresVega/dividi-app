import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/debt_reminder.dart';
import '../services/notification_center.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'profile_tab.dart';
import 'savings_tab.dart';

/// Pantalla de inicio de Dividi (lámina S1 del manual): saludo, resumen
/// «entre todos tus grupos», tarjetas de grupo con tu saldo, y las pestañas
/// Grupos · Actividad · Perfil.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _apiClient = ApiClient();
  late Future<_DatosInicio> _futuro;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  /// Carga los grupos y, por cada uno, sus balances y gastos (para el chip
  /// de saldo, el contador de gastos y la pestaña de actividad).
  Future<_DatosInicio> _cargar() async {
    final userId = await _apiClient.currentUserId();
    // el nombre real vive en /me; si falla no rompe el inicio (queda el
    // nombre de miembro de algún grupo como respaldo)
    String nombreMe = '';
    try {
      nombreMe = ((await _apiClient.getMe())['name'] ?? '') as String;
    } catch (_) {}
    // novedades: contador para la campana + aviso local si hay algo nuevo
    int noLeidas = 0;
    try {
      final notificaciones = await _apiClient.getNotifications();
      noLeidas = notificaciones.where((n) => n['read_at'] == null).length;
      unawaited(NotificationCenter.revisar(notificaciones));
    } catch (_) {}
    final grupos = await _apiClient.getGroups();
    final fichas = await Future.wait(grupos.map((grupo) async {
      List<dynamic> balances = const [];
      List<dynamic> gastos = const [];
      try {
        final r = await Future.wait([
          _apiClient.getBalances(grupo['id']),
          _apiClient.getExpenses(grupo['id']),
        ]);
        balances = r[0];
        gastos = r[1];
      } catch (_) {
        // un grupo que falla no debe tumbar toda la pantalla de inicio
      }
      return _FichaGrupo(
        grupo: grupo,
        balances: balances,
        gastos: gastos,
        userId: userId,
      );
    }));
    final datos = _DatosInicio(
        userId: userId, nombreMe: nombreMe, fichas: fichas, noLeidas: noLeidas);
    // recordatorio local de deudas (M10): se reprograma en cada carga
    unawaited(DebtReminder.actualizar(datos.saldoTotal));
    return datos;
  }

  Future<void> _refresh() async {
    final futuro = _cargar();
    setState(() {
      _futuro = futuro;
    });
    await futuro;
  }

  Future<void> _logout() async {
    await _apiClient.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _createGroup() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (creado == true && mounted) await _refresh();
  }

  Future<void> _abrirNovedades() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) await _refresh();
  }

  Future<void> _abrirGrupo(_FichaGrupo ficha) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          groupId: ficha.grupo['id'],
          groupName: ficha.grupo['name'],
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_DatosInicio>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(children: [
                  EstadoVacio(
                    titulo: 'No se pudieron cargar tus grupos',
                    detalle: '${snapshot.error}',
                    onRetry: _refresh,
                  ),
                ]),
              );
            }
            final datos = snapshot.data!;
            return switch (_tab) {
              0 => _tabGrupos(datos),
              1 => _tabActividad(datos),
              2 => const SavingsTab(),
              _ => ProfileTab(
                  numGrupos: datos.fichas.length,
                  onLogout: _logout,
                ),
            };
          },
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tema.colorScheme.outline)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              selectedIcon: Icon(Icons.people_alt_rounded),
              label: 'Grupos',
            ),
            NavigationDestination(
              icon: Icon(Icons.show_chart_rounded),
              selectedIcon: Icon(Icons.show_chart_rounded),
              label: 'Actividad',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Mi dinero',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: _createGroup,
              tooltip: 'Nuevo grupo',
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
    );
  }

  // ---------------------------------------------------------- pestaña Grupos

  Widget _tabGrupos(_DatosInicio datos) {
    final tema = Theme.of(context);
    final nombre = datos.nombreUsuario;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          Text(saludoFecha(DateTime.now()), style: tema.textTheme.bodySmall),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  nombre.isEmpty ? 'Hola' : 'Hola, $nombre',
                  style: tema.textTheme.displaySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _abrirNovedades,
                tooltip: 'Novedades',
                icon: Badge(
                  isLabelVisible: datos.noLeidas > 0,
                  label: Text('${datos.noLeidas}'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
              if (nombre.isNotEmpty) PersonaAvatar(nombre: nombre, size: 42),
            ],
          ),
          const SizedBox(height: 18),
          _ResumenCard(datos: datos),
          const SizedBox(height: 18),
          if (datos.fichas.isEmpty)
            const EstadoVacio(
              titulo: 'Todavía no tienes ningún grupo.',
              detalle:
                  'Crea el primero — un piso, una pareja, una familia — y '
                  'reparte los gastos según los ingresos de cada uno.',
            )
          else
            for (final ficha in datos.fichas) ...[
              _GrupoCard(ficha: ficha, onTap: () => _abrirGrupo(ficha)),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  // ------------------------------------------------------- pestaña Actividad

  Widget _tabActividad(_DatosInicio datos) {
    final tema = Theme.of(context);
    final eventos = <(_FichaGrupo, Map<String, dynamic>)>[
      for (final ficha in datos.fichas)
        for (final gasto in ficha.gastos) (ficha, gasto as Map<String, dynamic>),
    ]..sort((a, b) =>
        (b.$2['created_at'] ?? '').toString().compareTo((a.$2['created_at'] ?? '').toString()));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: eventos.isEmpty
          ? ListView(children: const [
              EstadoVacio(
                titulo: 'Sin actividad todavía.',
                detalle: 'Aquí verás los últimos gastos de todos tus grupos.',
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              itemCount: eventos.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('Actividad', style: tema.textTheme.displaySmall),
                  );
                }
                final (ficha, gasto) = eventos[index - 1];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        CategoriaInsignia(
                            categoria: gasto['category'],
                            emoji: gasto['category_icon'],
                            size: 42),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gasto['description'],
                                style: tema.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ficha.grupo['name']} · Pagó ${ficha.nombreMiembro(gasto['paid_by_id'])} · ${fechaCorta(gasto['created_at'])}',
                                style: tema.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatearImporte(gasto['amount'],
                              divisa: gasto['currency']),
                          style: tema.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

}

/// Tarjeta-resumen sobre Tinta: el saldo global del usuario. Colores fijos
/// (es una superficie de marca, igual en modo día y noche).
class _ResumenCard extends StatelessWidget {
  final _DatosInicio datos;

  const _ResumenCard({required this.datos});

  @override
  Widget build(BuildContext context) {
    final total = datos.saldoTotal;
    final enPaz = total.abs() < 0.005;
    final color = enPaz
        ? DividiColors.porcelana
        : total > 0
            ? const Color(0xFF7DD3A8)
            : const Color(0xFFE9857A);
    final grupos = datos.fichas.length;
    final cuantos = grupos == 1 ? '1 grupo activo' : '$grupos grupos activos';
    final detalle = enPaz
        ? 'todo en paz · $cuantos'
        : total > 0
            ? 'te deben en total · $cuantos'
            : 'debes en total · $cuantos';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: DividiColors.tinta,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ENTRE TODOS TUS GRUPOS',
            style: TextStyle(
              fontFamily: DividiTheme.familiaCuerpo,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: DividiColors.porcelana.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            enPaz ? 'En paz' : formatearImporte(total, conSigno: true),
            style: TextStyle(
              fontFamily: DividiTheme.familiaTitulares,
              fontWeight: FontWeight.w800,
              fontSize: 34,
              height: 1.15,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detalle,
            style: TextStyle(
              fontFamily: DividiTheme.familiaCuerpo,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: DividiColors.porcelana.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de grupo (S1): pila de avatares, nombre, «N miembros · M gastos»
/// y el chip con TU saldo en ese grupo.
class _GrupoCard extends StatelessWidget {
  final _FichaGrupo ficha;
  final VoidCallback onTap;

  const _GrupoCard({required this.ficha, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final miembros = ficha.nombresMiembros;
    final gastos = ficha.gastos.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              PilaAvatares(nombres: miembros, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ficha.grupo['name'],
                      style: tema.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${miembros.length == 1 ? '1 miembro' : '${miembros.length} miembros'} · ${gastos == 1 ? '1 gasto' : '$gastos gastos'}',
                      style: tema.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SaldoChip(importe: ficha.miSaldo),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo de vista de la pantalla de inicio (solo presentación).
// ---------------------------------------------------------------------------

class _DatosInicio {
  final String? userId;
  final String nombreMe;
  final List<_FichaGrupo> fichas;
  final int noLeidas;

  const _DatosInicio({
    required this.userId,
    required this.nombreMe,
    required this.fichas,
    required this.noLeidas,
  });

  String get nombreUsuario {
    if (nombreMe.isNotEmpty) return nombreMe;
    for (final ficha in fichas) {
      final nombre = ficha.miNombre;
      if (nombre != null && nombre.isNotEmpty) return nombre;
    }
    return '';
  }

  double get saldoTotal =>
      fichas.fold(0.0, (suma, ficha) => suma + ficha.miSaldo);
}

class _FichaGrupo {
  final Map<String, dynamic> grupo;
  final List<dynamic> balances;
  final List<dynamic> gastos;
  final String? userId;

  const _FichaGrupo({
    required this.grupo,
    required this.balances,
    required this.gastos,
    required this.userId,
  });

  List<dynamic> get miembros => (grupo['members'] as List<dynamic>?) ?? const [];

  List<String> get nombresMiembros =>
      miembros.map((m) => m['display_name'] as String).toList();

  Map<String, dynamic>? get _miMiembro {
    if (userId == null) return null;
    for (final m in miembros) {
      if (m['user_id'] == userId) return m as Map<String, dynamic>;
    }
    return null;
  }

  String? get miNombre => _miMiembro?['display_name'] as String?;

  /// Mi balance neto en este grupo (0 si no aparezco o aún no hay datos).
  double get miSaldo {
    final miembroId = _miMiembro?['id'];
    if (miembroId == null) return 0;
    for (final b in balances) {
      if (b['member_id'] == miembroId) {
        return double.tryParse(b['balance'].toString()) ?? 0;
      }
    }
    return 0;
  }

  String nombreMiembro(String? miembroId) {
    for (final m in miembros) {
      if (m['id'] == miembroId) return m['display_name'] as String;
    }
    return '—';
  }
}
