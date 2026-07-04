import 'package:flutter/material.dart';

import '../services/api_client.dart';

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

  /// Reparto proporcional: el nuevo miembro recibe su %, y el resto escala
  /// para que todo siga sumando 100 (manteniendo sus proporciones relativas).
  Map<String, String> _proportionalRebalance(
      List<dynamic> members, double newPercentage) {
    final factor = (100 - newPercentage) / 100;
    final rebalance = <String, String>{};
    var assigned = 0.0;
    for (var i = 0; i < members.length; i++) {
      final old = double.tryParse(members[i]['default_percentage'].toString()) ?? 0;
      double value;
      if (i == members.length - 1) {
        value = 100 - newPercentage - assigned;
      } else {
        value = double.parse((old * factor).toStringAsFixed(2));
        assigned += value;
      }
      rebalance[members[i]['id']] = value.toStringAsFixed(2);
    }
    return rebalance;
  }

  Future<void> _addMember() async {
    if (_saving) return;
    final group = await _groupFuture;
    if (!mounted) return;
    final members = group['members'] as List<dynamic>;

    final nameController = TextEditingController();
    final emailController = TextEditingController();
    // sugerencia: parte igualitaria para el nuevo (100 / n+1)
    final suggested = 100 / (members.length + 1);
    final percentController =
        TextEditingController(text: suggested.toStringAsFixed(2));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir miembro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                helperText: 'Basta con un nombre: "Persona 1", "Compi"...',
              ),
              autofocus: true,
            ),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (opcional)',
                helperText: 'Si algún día se registra, se vincula solo',
              ),
            ),
            TextField(
              controller: percentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Porcentaje por defecto (%)',
                helperText: 'El resto del grupo se reajusta solo',
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
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final percentage =
        double.tryParse(percentController.text.replaceAll(',', '.'));
    if (name.isEmpty && email.isEmpty) {
      _showError('Pon al menos un nombre o un email');
      return;
    }
    if (percentage == null || percentage < 0 || percentage > 100) {
      _showError('El porcentaje debe ser un número entre 0 y 100');
      return;
    }

    setState(() => _saving = true);
    try {
      await _apiClient.addMember(
        groupId: widget.groupId,
        displayName: name.isEmpty ? null : name,
        email: email.isEmpty ? null : email,
        defaultPercentage: percentage.toStringAsFixed(2),
        rebalance: _proportionalRebalance(members, percentage),
      );
      await _refresh();
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                const SizedBox(height: 100),
                Center(child: Text('Error: ${snapshot.error}')),
              ]);
            }
            final members = (snapshot.data?['members'] as List<dynamic>?) ?? [];
            return ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                final hasAccount = member['user_id'] != null;
                final invitedEmail = member['invited_email'];
                final status = hasAccount
                    ? 'con cuenta'
                    : invitedEmail != null
                        ? 'invitado: $invitedEmail'
                        : 'invitado sin cuenta';
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(member['display_name'][0].toUpperCase()),
                  ),
                  title: Text(member['display_name']),
                  subtitle: Text('${member['role']} · $status'),
                  trailing: Text(
                    '${member['default_percentage']}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saving ? null : _addMember,
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.person_add),
      ),
    );
  }
}
