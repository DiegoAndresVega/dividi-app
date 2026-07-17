import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import 'member_rebalance.dart';

String _formatearPeso(double value) {
  final texto = value.toStringAsFixed(2);
  return texto.endsWith('.00') ? value.toStringAsFixed(0) : texto;
}

/// Editar un miembro del grupo (nombre y peso) o eliminarlo. Sirve tanto para
/// invitados sin cuenta como para miembros con cuenta: el nombre que se cambia
/// es el que se muestra en este grupo.
///
/// Al cambiar el peso, el resto de miembros se reajusta para seguir sumando
/// 100. Devuelve true si hubo algún cambio (para refrescar la lista).
Future<bool> showEditMemberDialog({
  required BuildContext context,
  required ApiClient apiClient,
  required String groupId,
  required Map<String, dynamic> member,
  required List<dynamic> members,
}) async {
  final nameController =
      TextEditingController(text: member['display_name']?.toString() ?? '');
  final pesoActual = double.tryParse('${member['default_percentage']}') ?? 0;
  final percentController =
      TextEditingController(text: _formatearPeso(pesoActual));

  final accion = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Editar miembro'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              autofocus: true,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: percentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Peso en el hogar (%)',
                helperText: 'El resto se reajusta solo para sumar 100',
              ),
            ),
          ],
        ),
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

  final otros = members.where((m) => m['id'] != member['id']).toList();

  if (accion == 'remove') {
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

  // Guardar cambios
  final nombre = nameController.text.trim();
  final nuevoPeso = double.tryParse(percentController.text.replaceAll(',', '.'));
  if (nombre.isEmpty) {
    showError('Pon un nombre');
    return false;
  }
  if (nuevoPeso == null || nuevoPeso < 0 || nuevoPeso > 100) {
    showError('El porcentaje debe ser un número entre 0 y 100');
    return false;
  }

  final pesoCambio = (nuevoPeso - pesoActual).abs() > 0.001;
  try {
    await apiClient.updateMember(
      groupId: groupId,
      memberId: member['id'],
      displayName: nombre,
      defaultPercentage: pesoCambio ? nuevoPeso.toStringAsFixed(2) : null,
      rebalance: pesoCambio && otros.isNotEmpty
          ? proportionalRebalance(otros, nuevoPeso)
          : null,
    );
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showError(e.message);
    return false;
  }
}
