import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import 'member_rebalance.dart';

/// Editar un miembro del grupo (su nombre) o eliminarlo. Sirve tanto para
/// invitados sin cuenta como para miembros con cuenta: el nombre que se cambia
/// es el que se muestra en este grupo.
///
/// Los porcentajes se editan todos juntos en «Editar porcentajes», no aquí, para
/// que cambiar uno no descuadre a los demás. Devuelve true si hubo cambios.
Future<bool> showEditMemberDialog({
  required BuildContext context,
  required ApiClient apiClient,
  required String groupId,
  required Map<String, dynamic> member,
  required List<dynamic> members,
}) async {
  final nameController =
      TextEditingController(text: member['display_name']?.toString() ?? '');

  final accion = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Editar miembro'),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(labelText: 'Nombre'),
        textCapitalization: TextCapitalization.words,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('remove'),
          style: TextButton.styleFrom(foregroundColor: DividiColors.rojo),
          child: const Text('Eliminar'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('save'),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (accion == null || !context.mounted) return false;

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  if (accion == 'remove') {
    final otros = members.where((m) => m['id'] != member['id']).toList();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar miembro'),
        content: Text(
            '¿Seguro que quieres quitar a ${member['display_name']} del grupo?'),
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
    if (confirmado != true || !context.mounted) return false;
    try {
      await apiClient.removeMember(
        groupId: groupId,
        memberId: member['id'],
        rebalance: otros.isEmpty ? null : proportionalRebalance(otros, 0),
      );
      return true;
    } on ApiException catch (e) {
      if (context.mounted) showError(e.message);
      return false;
    }
  }

  // Guardar el nombre
  final nombre = nameController.text.trim();
  if (nombre.isEmpty) {
    showError('Pon un nombre');
    return false;
  }
  if (nombre == member['display_name']) return false;
  try {
    await apiClient.updateMember(
      groupId: groupId,
      memberId: member['id'],
      displayName: nombre,
    );
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showError(e.message);
    return false;
  }
}
