import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import '../widgets/add_member_dialog.dart';
import '../widgets/dividi_bits.dart';

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
    setState(() => _groupFuture = _apiClient.getGroup(widget.groupId));
  }

  Future<void> _addMember() async {
    if (_saving) return;
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
                ),
              ]);
            }
            final members = (snapshot.data?['members'] as List<dynamic>?) ?? [];
            final tema = Theme.of(context);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final member = members[index];
                final hasAccount = member['user_id'] != null;
                final invitedEmail = member['invited_email'];
                final status = hasAccount
                    ? 'con cuenta'
                    : invitedEmail != null
                        ? 'invitado: $invitedEmail'
                        : 'invitado sin cuenta';
                final esAdmin = member['role'] == 'admin';
                return Card(
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
                          '${member['default_percentage']} %',
                          style: tema.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addMember,
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
