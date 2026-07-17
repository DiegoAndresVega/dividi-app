import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/add_member_dialog.dart';
import '../widgets/dividi_bits.dart';
import '../widgets/edit_member_dialog.dart';
import '../widgets/member_rebalance.dart';

/// Miembros del grupo: lista con porcentajes por defecto y añadir nuevos.
///
/// Se puede añadir a alguien por email (si tiene o tendrá cuenta) o como
/// invitado sin cuenta, solo con un nombre ("Persona 1", "Piso 2"...) — útil
/// para llevar cuentas sin que todos estén registrados.
class MembersScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const MembersScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _apiClient = ApiClient();
  late Future<Map<String, dynamic>> _groupFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groupFuture = _apiClient.getGroup(widget.groupId);
  }

  Future<void> _refresh() async {
    setState(() {
      _groupFuture = _apiClient.getGroup(widget.groupId);
    });
  }

  /// Menú de añadir: un invitado sin cuenta, o un amigo por su cuenta.
  Future<void> _showAddSheet() async {
    if (_saving) return;
    final opcion = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('Añadir invitado'),
              subtitle: const Text('Sin cuenta, solo un nombre: "Compi", "Piso 2"...'),
              onTap: () => Navigator.of(context).pop('guest'),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_rounded),
              title: const Text('Añadir un amigo'),
              subtitle: const Text('Con su cuenta; le llega un aviso al añadirlo'),
              onTap: () => Navigator.of(context).pop('friend'),
            ),
          ],
        ),
      ),
    );
    if (opcion == 'guest') await _addGuest();
    if (opcion == 'friend') await _addFriend();
  }

  Future<void> _addGuest() async {
    final group = await _groupFuture;
    if (!mounted) return;
    final members = group['members'] as List<dynamic>;

    setState(() => _saving = true);
    try {
      final created = await showAddMemberDialog(
        context: context,
        apiClient: _apiClient,
        groupId: widget.groupId,
        members: members,
      );
      if (created != null) await _refresh();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addFriend() async {
    final group = await _groupFuture;
    if (!mounted) return;
    final members = group['members'] as List<dynamic>;
    final yaEstan = members
        .map((m) => m['user_id'])
        .where((id) => id != null)
        .toSet();

    setState(() => _saving = true);
    try {
      final amigos = await _apiClient.getFriends();
      final disponibles =
          amigos.where((a) => !yaEstan.contains(a['user_id'])).toList();
      if (!mounted) return;
      if (disponibles.isEmpty) {
        _aviso(amigos.isEmpty
            ? 'Aún no tienes amigos. Añádelos desde tu perfil.'
            : 'Todos tus amigos ya están en el grupo.');
        return;
      }

      final elegido = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Añadir un amigo'),
          children: [
            for (final amigo in disponibles)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(amigo),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      PersonaAvatar(nombre: amigo['name'], size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: Text(amigo['name'])),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      if (elegido == null || !mounted) return;

      final sugerido = 100 / (members.length + 1);
      await _apiClient.addMember(
        groupId: widget.groupId,
        friendUserId: elegido['user_id'] as String,
        defaultPercentage: sugerido.toStringAsFixed(2),
        rebalance: proportionalRebalance(members, sugerido),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editMember(Map<String, dynamic> member) async {
    if (_saving) return;
    final group = await _groupFuture;
    if (!mounted) return;
    final members = group['members'] as List<dynamic>;

    setState(() => _saving = true);
    try {
      final cambiado = await showEditMemberDialog(
        context: context,
        apiClient: _apiClient,
        groupId: widget.groupId,
        member: member,
        members: members,
      );
      if (cambiado) await _refresh();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Miembros de ${widget.groupName}')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _groupFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                EstadoVacio(
                  titulo: 'No se pudieron cargar los miembros',
                  detalle: '${snapshot.error}',
                  onRetry: _refresh,
                ),
              ]);
            }
            final members = (snapshot.data?['members'] as List<dynamic>?) ?? [];
            final tema = Theme.of(context);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              itemCount: members.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  // la idea central de Dividi, explicada donde se configura
                  final tonos = DividiTones.of(context);
                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: tonos.neutroFondo,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('El reparto del hogar',
                            style: tema.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'El porcentaje de cada persona es su peso en los '
                          'gastos comunes — por ejemplo, su parte de los '
                          'ingresos de la casa. Siempre suma 100, y los gastos '
                          '«según ingresos» lo usan de serie: quien gana más '
                          'aporta más, y a todos les cuesta el mismo esfuerzo.',
                          style: tema.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }
                final member = members[index - 1];
                final hasAccount = member['user_id'] != null;
                final invitedEmail = member['invited_email'];
                final status = hasAccount
                    ? 'con cuenta'
                    : invitedEmail != null
                        ? 'invitado: $invitedEmail'
                        : 'invitado sin cuenta';
                final esAdmin = member['role'] == 'admin';
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _editMember(member as Map<String, dynamic>),
                    child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        PersonaAvatar(
                            nombre: member['display_name'], size: 42),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      member['display_name'],
                                      style: tema.textTheme.titleSmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (esAdmin) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: DividiTones.of(context)
                                            .neutroFondo,
                                        borderRadius:
                                            BorderRadius.circular(99),
                                      ),
                                      child: Text('Admin',
                                          style: tema.textTheme.labelSmall),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                status,
                                style: tema.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatearPorcentaje(member['default_percentage']),
                          style: tema.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            color: tema.colorScheme.outline),
                      ],
                    ),
                  ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _showAddSheet,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Añadir miembro'),
      ),
    );
  }
}
