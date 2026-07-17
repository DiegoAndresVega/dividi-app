import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';
import 'friends_screen.dart';

/// Pestaña Perfil (M1 + M3): tu cuenta de verdad — nombre y contraseña
/// editables — y tus invitaciones: Dividi es por invitación y cualquier
/// usuario puede generar códigos (cadena de confianza).
class ProfileTab extends StatefulWidget {
  final int numGrupos;
  final Future<void> Function() onLogout;

  const ProfileTab({
    super.key,
    required this.numGrupos,
    required this.onLogout,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _apiClient = ApiClient();
  late Future<(Map<String, dynamic>, List<dynamic>)> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<(Map<String, dynamic>, List<dynamic>)> _cargar() async {
    final resultados = await Future.wait([
      _apiClient.getMe(),
      _apiClient.getInvitations(),
    ]);
    return (
      resultados[0] as Map<String, dynamic>,
      resultados[1] as List<dynamic>,
    );
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

  // ---------------------------------------------------------------- cuenta

  Future<void> _cambiarNombre(String nombreActual) async {
    final controller = TextEditingController(text: nombreActual);
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar nombre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Tu nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty || nombre == nombreActual) return;
    try {
      await _apiClient.updateMe(name: nombre);
      await _refresh();
      if (mounted) _aviso('Nombre actualizado.');
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    }
  }

  Future<void> _cambiarPassword() async {
    final actual = TextEditingController();
    final nueva = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: actual,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nueva,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña nueva',
                helperText: 'Mínimo 8 caracteres',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    if (nueva.text.length < 8) {
      _aviso('La contraseña nueva necesita al menos 8 caracteres.');
      return;
    }
    try {
      await _apiClient.changePassword(
        currentPassword: actual.text,
        newPassword: nueva.text,
      );
      if (mounted) _aviso('Contraseña cambiada.');
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    }
  }

  // ---------------------------------------------------------- invitaciones

  Future<void> _copiar(String codigo) async {
    await Clipboard.setData(ClipboardData(text: codigo));
    if (mounted) _aviso('Código copiado. Pégalo donde quieras.');
  }

  Future<void> _nuevaInvitacion() async {
    final Map<String, dynamic> invitacion;
    try {
      invitacion = await _apiClient.createInvitation();
    } on ApiException catch (e) {
      _aviso(e.message);
      return;
    }
    await _refresh();
    if (!mounted) return;
    final tema = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invitación creada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Comparte este código: vale para un solo registro.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: tema.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                invitacion['code'],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: DividiTheme.familiaTitulares,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: 2,
                  color: tema.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () {
              _copiar(invitacion['code']);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar'),
          ),
        ],
      ),
    );
  }

  Future<void> _revocar(Map<String, dynamic> invitacion) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Revocar esta invitación?'),
        content: Text('El código ${invitacion['code']} dejará de valer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (seguro != true) return;
    try {
      await _apiClient.revokeInvitation(invitacion['id']);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Map<String, dynamic>, List<dynamic>)>(
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
                titulo: 'No se pudo cargar tu perfil',
                detalle: '${snapshot.error}',
                onRetry: _refresh,
              ),
            ]),
          );
        }
        final (me, invitaciones) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: _contenido(me, invitaciones),
        );
      },
    );
  }

  Widget _contenido(Map<String, dynamic> me, List<dynamic> invitaciones) {
    final tema = Theme.of(context);
    final nombre = (me['name'] ?? '') as String;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      children: [
        Center(child: PersonaAvatar(nombre: nombre, size: 88)),
        const SizedBox(height: 16),
        Center(child: Text(nombre, style: tema.textTheme.headlineMedium)),
        const SizedBox(height: 4),
        Center(
          child: Text(me['email'] ?? '', style: tema.textTheme.bodySmall),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            widget.numGrupos == 1
                ? 'En 1 grupo · Dividi v1.1'
                : 'En ${widget.numGrupos} grupos · Dividi v1.1',
            style: tema.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 26),

        // ---- cuenta
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Cambiar nombre'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _cambiarNombre(nombre),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Cambiar contraseña'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _cambiarPassword,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('Amigos'),
                subtitle: const Text('Añade amigos y móntalos en tus grupos'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // ---- invitaciones
        const EtiquetaSeccion('Invitaciones'),
        const SizedBox(height: 6),
        Text(
          'Dividi es por invitación: genera un código y compártelo. '
          'Cada código vale para un solo registro.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _nuevaInvitacion,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text('Nueva invitación'),
        ),
        const SizedBox(height: 8),
        for (final invitacion in invitaciones)
          _InvitacionTile(
            invitacion: invitacion as Map<String, dynamic>,
            onCopiar: () => _copiar(invitacion['code']),
            onRevocar: () => _revocar(invitacion),
          ),
        const SizedBox(height: 32),

        OutlinedButton.icon(
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: const Text('Cerrar sesión'),
        ),
        const SizedBox(height: 40),
        Center(
          child: Text(
            '«Cuentas claras, amistades largas.»',
            style: tema.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fila de una invitación: código, estado y acciones (copiar / revocar).
class _InvitacionTile extends StatelessWidget {
  final Map<String, dynamic> invitacion;
  final VoidCallback onCopiar;
  final VoidCallback onRevocar;

  const _InvitacionTile({
    required this.invitacion,
    required this.onCopiar,
    required this.onRevocar,
  });

  ({String texto, bool pendiente}) get _estado {
    if (invitacion['used_at'] != null) {
      return (texto: 'usada · ${fechaCorta(invitacion['used_at'])}', pendiente: false);
    }
    final caduca = DateTime.tryParse(invitacion['expires_at'] ?? '');
    if (caduca != null && caduca.isBefore(DateTime.now().toUtc())) {
      return (texto: 'caducada', pendiente: false);
    }
    final para = invitacion['email'];
    final partes = [
      'pendiente',
      if (para != null) 'para $para',
      if (caduca != null) 'caduca ${fechaCorta(invitacion['expires_at'])}',
    ];
    return (texto: partes.join(' · '), pendiente: true);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estado = _estado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invitacion['code'],
                    style: TextStyle(
                      fontFamily: DividiTheme.familiaTitulares,
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                      letterSpacing: 1.2,
                      color: estado.pendiente
                          ? tema.colorScheme.onSurface
                          : tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(estado.texto, style: tema.textTheme.bodySmall),
                ],
              ),
            ),
            if (estado.pendiente) ...[
              IconButton(
                onPressed: onCopiar,
                tooltip: 'Copiar código',
                icon: const Icon(Icons.copy_rounded, size: 20),
              ),
              IconButton(
                onPressed: onRevocar,
                tooltip: 'Revocar',
                icon: const Icon(Icons.delete_outline_rounded, size: 21),
              ),
            ] else
              Icon(
                invitacion['used_at'] != null
                    ? Icons.check_circle_rounded
                    : Icons.schedule_rounded,
                size: 20,
                color: tema.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
