import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';
import 'friends_screen.dart';
import 'group_detail_screen.dart';

/// Centro de novedades: solicitudes de amistad, grupos a los que te añaden...
/// Al abrirlo se marcan como leídas (el contador del inicio se pone a cero).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _apiClient = ApiClient();
  late Future<List<dynamic>> _futuro;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<List<dynamic>> _cargar() async {
    final notificaciones = await _apiClient.getNotifications();
    // marcar todo como leído en segundo plano: al entrar aquí ya las viste
    final hayNoLeidas = notificaciones.any((n) => n['read_at'] == null);
    if (hayNoLeidas) {
      _huboCambios = true;
      unawaited(_apiClient.markAllNotificationsRead().catchError((_) {}));
    }
    return notificaciones;
  }

  Future<void> _refresh() async {
    final futuro = _cargar();
    setState(() {
      _futuro = futuro;
    });
    await futuro;
  }

  Future<void> _abrir(Map<String, dynamic> n) async {
    final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (n['type']) {
      case 'added_to_group':
        if (data['group_id'] != null) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupDetailScreen(
              groupId: data['group_id'],
              groupName: data['group_name'] ?? 'Grupo',
            ),
          ));
          _huboCambios = true;
        }
      case 'friend_request':
      case 'friend_accepted':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FriendsScreen()),
        );
        _huboCambios = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_huboCambios);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Novedades')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<dynamic>>(
            future: _futuro,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(children: [
                  EstadoVacio(
                    titulo: 'No se pudieron cargar tus novedades',
                    detalle: '${snapshot.error}',
                    onRetry: _refresh,
                  ),
                ]);
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return ListView(children: const [
                  EstadoVacio(
                    titulo: 'Sin novedades',
                    detalle:
                        'Aquí verás las solicitudes de amistad y los grupos a '
                        'los que te añadan.',
                  ),
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _NotifTile(n: items[index], onTap: () => _abrir(items[index])),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> n;
  final VoidCallback onTap;

  const _NotifTile({required this.n, required this.onTap});

  ({IconData icono, Color color}) _estilo(BuildContext context) {
    final tonos = DividiTones.of(context);
    return switch (n['type']) {
      'friend_request' => (icono: Icons.person_add_alt_1_rounded, color: tonos.positivo),
      'friend_accepted' => (icono: Icons.how_to_reg_rounded, color: tonos.positivo),
      'added_to_group' => (icono: Icons.group_add_rounded, color: DividiColors.ambar),
      _ => (icono: Icons.notifications_rounded, color: tonos.positivo),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estilo = _estilo(context);
    final noLeida = n['read_at'] == null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: estilo.color.withValues(alpha: 0.16),
                child: Icon(estilo.icono, color: estilo.color, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n['title'] ?? '',
                      style: tema.textTheme.titleSmall?.copyWith(
                        fontWeight: noLeida ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(n['body'] ?? '', style: tema.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      fechaCorta(n['created_at']),
                      style: tema.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (noLeida)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: DividiColors.ambar,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
