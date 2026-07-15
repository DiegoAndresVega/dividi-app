import 'package:flutter/material.dart';

import '../services/api_client.dart';

/// Reparto proporcional: el nuevo miembro recibe su %, y el resto escala
/// para que todo siga sumando 100 (manteniendo sus proporciones relativas).
Map<String, String> _proportionalRebalance(List<dynamic> members, double newPercentage) {
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

/// Diálogo compartido para añadir un miembro al grupo, usado desde la pantalla
/// de miembros y desde el formulario de gasto. Basta un nombre ("Persona 1",
/// "Compi"...) para invitados sin cuenta; el email es opcional.
///
/// Devuelve el miembro creado, o null si se cancela o falla.
Future<Map<String, dynamic>?> showAddMemberDialog({
  required BuildContext context,
  required ApiClient apiClient,
  required String groupId,
  required List<dynamic> members,
}) async {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  // sugerencia: parte igualitaria para el nuevo (100 / n+1)
  final suggested = 100 / (members.length + 1);
  final percentController = TextEditingController(text: suggested.toStringAsFixed(2));

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Añadir miembro'),
      content: SingleChildScrollView(
        child: Column(
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
            const SizedBox(height: 14),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (opcional)',
                helperText: 'Si algún día se registra, se vincula solo',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: percentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Peso en el hogar (%)',
                helperText:
                    'Su parte de los ingresos; el resto se reajusta solo',
              ),
            ),
          ],
        ),
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
  if (confirmed != true || !context.mounted) return null;

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  final name = nameController.text.trim();
  final email = emailController.text.trim();
  final percentage = double.tryParse(percentController.text.replaceAll(',', '.'));
  if (name.isEmpty && email.isEmpty) {
    showError('Pon al menos un nombre o un email');
    return null;
  }
  if (percentage == null || percentage < 0 || percentage > 100) {
    showError('El porcentaje debe ser un número entre 0 y 100');
    return null;
  }

  try {
    return await apiClient.addMember(
      groupId: groupId,
      displayName: name.isEmpty ? null : name,
      email: email.isEmpty ? null : email,
      defaultPercentage: percentage.toStringAsFixed(2),
      rebalance: _proportionalRebalance(members, percentage),
    );
  } on ApiException catch (e) {
    if (context.mounted) showError(e.message);
    return null;
  }
}
