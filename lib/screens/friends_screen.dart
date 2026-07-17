import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';

/// Amigos: solicitudes recibidas (aceptar / rechazar) y tu lista de amigos.
/// Con un amigo puedes crear un grupo y añadirlo por su cuenta; le llega un
/// aviso. Conectar es por solicitud: tú la envías, la otra persona acepta.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _apiClient = ApiClient();
  late Future<(List<dynamic>, List<dynamic>)> _futuro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<(List<dynamic>, List<dynamic>)> _cargar() async {
    final r = await Future.wait([
      _apiClient.getFriends(),
      _apiClient.getFriendRequests(),
    ]);
    return (r[0], r[1]);
  }

  Future<void> _refresh() async {
    final futuro = _cargar();
    setState(() {
      _futuro = futuro;
    });
    await futuro;
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _enviarSolicitud() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir amigo'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email de tu amigo',
            helperText: 'Debe tener cuenta en Dividi',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    setState(() => _ocupado = true);
    try {
      final estado = await _apiClient.sendFriendRequest(email);
      if (!mounted) return;
      _aviso(estado == 'accepted'
          ? '¡Ya sois amigos!'
          : 'Solicitud enviada. Te avisaremos cuando la acepte.');
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _aceptar(Map<String, dynamic> solicitud) async {
    setState(() => _ocupado = true);
    try {
      await _apiClient.acceptFriendRequest(solicitud['id']);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _rechazar(Map<String, dynamic> solicitud) async {
    setState(() => _ocupado = true);
    try {
      await _apiClient.declineFriendRequest(solicitud['id']);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> amigo) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar amigo'),
        content: Text('¿Quitar a ${amigo['name']} de tus amigos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DividiColors.rojo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (seguro != true) return;
    try {
      await _apiClient.removeFriend(amigo['friendship_id']);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Amigos')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<(List<dynamic>, List<dynamic>)>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                EstadoVacio(
                  titulo: 'No se pudieron cargar tus amigos',
                  detalle: '${snapshot.error}',
                  onRetry: _refresh,
                ),
              ]);
            }
            final (amigos, solicitudes) = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              children: [
                if (solicitudes.isNotEmpty) ...[
                  const EtiquetaSeccion('Solicitudes'),
                  const SizedBox(height: 8),
                  for (final s in solicitudes)
                    _SolicitudTile(
                      solicitud: s as Map<String, dynamic>,
                      ocupado: _ocupado,
                      onAceptar: () => _aceptar(s),
                      onRechazar: () => _rechazar(s),
                    ),
                  const SizedBox(height: 22),
                ],
                const EtiquetaSeccion('Tus amigos'),
                const SizedBox(height: 8),
                if (amigos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Aún no tienes amigos. Añade a alguien por su email: '
                      'cuando acepte, podrás crear grupos y añadirlo directamente.',
                      style: tema.textTheme.bodySmall,
                    ),
                  )
                else
                  for (final a in amigos)
                    Card(
                      child: ListTile(
                        leading: PersonaAvatar(nombre: a['name'], size: 40),
                        title: Text(a['name']),
                        subtitle: Text(a['email']),
                        trailing: IconButton(
                          icon: const Icon(Icons.person_remove_outlined),
                          tooltip: 'Eliminar amigo',
                          onPressed: () => _eliminar(a as Map<String, dynamic>),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ocupado ? null : _enviarSolicitud,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Añadir amigo'),
      ),
    );
  }
}

class _SolicitudTile extends StatelessWidget {
  final Map<String, dynamic> solicitud;
  final bool ocupado;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;

  const _SolicitudTile({
    required this.solicitud,
    required this.ocupado,
    required this.onAceptar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            PersonaAvatar(nombre: solicitud['from_name'], size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(solicitud['from_name'], style: tema.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text('quiere ser tu amigo', style: tema.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              onPressed: ocupado ? null : onRechazar,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Rechazar',
            ),
            IconButton.filled(
              onPressed: ocupado ? null : onAceptar,
              icon: const Icon(Icons.check_rounded),
              tooltip: 'Aceptar',
            ),
          ],
        ),
      ),
    );
  }
}
