import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import '../widgets/add_member_dialog.dart';
import '../widgets/dividi_bits.dart';

/// Formulario de gasto: sirve para crear (expense == null) y para editar.
///
/// Permite elegir con quién se comparte el gasto y el método de reparto:
/// a partes iguales entre los seleccionados, o por porcentajes por persona
/// (validando que sumen 100).
class ExpenseFormScreen extends StatefulWidget {
  final String groupId;
  final List<dynamic> members;
  final Map<String, dynamic>? expense;

  const ExpenseFormScreen({
    super.key,
    required this.groupId,
    required this.members,
    this.expense,
  });

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _apiClient = ApiClient();

  /// Copia local de los miembros: puede crecer si se añade un participante
  /// nuevo al grupo desde este mismo formulario.
  late final List<dynamic> _members = List.of(widget.members);

  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String _category = 'otros';
  String? _paidById;
  String _splitMethod = 'equal';

  /// Miembros que participan en el gasto y, si es por porcentajes,
  /// el controlador con el % de cada uno.
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _percentControllers = {};

  /// Campos de % fijados a mano por el usuario. El resto se rellenan
  /// automáticamente a partes iguales con lo que falte hasta 100.
  final Set<String> _locked = {};

  bool _saving = false;

  static const _categories = ['comida', 'transporte', 'alojamiento', 'ocio', 'otros'];

  bool get _isEditing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    for (final member in _members) {
      _percentControllers[member['id']] = TextEditingController();
    }

    final expense = widget.expense;
    if (expense == null) {
      // por defecto: participan todos y paga el primero
      _selected.addAll(_members.map((m) => m['id'] as String));
      _paidById = _members.isNotEmpty ? _members.first['id'] : null;
    } else {
      _descriptionController.text = expense['description'];
      _amountController.text = expense['amount'].toString();
      _category = expense['category'];
      _paidById = expense['paid_by_id'];
      _splitMethod = expense['split_method'];
      // solo equal/percentage se editan desde la app por ahora
      if (_splitMethod != 'percentage') _splitMethod = _splitMethod == 'equal' ? 'equal' : _splitMethod;
      for (final split in (expense['splits'] as List<dynamic>)) {
        final memberId = split['group_member_id'] as String;
        _selected.add(memberId);
        if (split['percentage'] != null) {
          _percentControllers[memberId]?.text = split['percentage'].toString();
          // al editar, los % existentes se consideran fijados por el usuario
          _locked.add(memberId);
        }
      }
    }
    _recomputeAutoPercentages();
  }

  /// Reparte lo que falte hasta 100 entre los campos no fijados (automáticos).
  /// El último absorbe el resto del redondeo para que siempre sume 100 exacto.
  void _recomputeAutoPercentages() {
    if (_splitMethod != 'percentage') return;
    final autoIds = _selected.where((id) => !_locked.contains(id)).toList();
    if (autoIds.isEmpty) return;

    var lockedSum = 0.0;
    for (final id in _selected) {
      if (_locked.contains(id)) {
        final text = _percentControllers[id]?.text.replaceAll(',', '.') ?? '';
        lockedSum += double.tryParse(text) ?? 0;
      }
    }

    final remaining = 100 - lockedSum;
    if (remaining <= 0) {
      // los fijados ya llegan (o pasan) de 100: los automáticos quedan a 0
      for (final id in autoIds) {
        _percentControllers[id]!.text = '0';
      }
      return;
    }

    final share = remaining / autoIds.length;
    var assigned = 0.0;
    for (var i = 0; i < autoIds.length; i++) {
      double value;
      if (i == autoIds.length - 1) {
        value = remaining - assigned;
      } else {
        value = double.parse(share.toStringAsFixed(2));
        assigned += value;
      }
      _percentControllers[autoIds[i]]!.text = _formatPercent(value);
    }
  }

  String _formatPercent(double value) {
    final text = value.toStringAsFixed(2);
    return text.endsWith('.00') ? value.toStringAsFixed(0) : text;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    for (final controller in _percentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _percentSum {
    var sum = 0.0;
    for (final id in _selected) {
      final text = _percentControllers[id]?.text.replaceAll(',', '.') ?? '';
      sum += double.tryParse(text) ?? 0;
    }
    return sum;
  }

  String? _validate() {
    if (_descriptionController.text.trim().isEmpty) return 'Pon una descripción';
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) return 'El importe debe ser un número mayor que 0';
    if (_paidById == null) return 'Elige quién pagó';
    if (_selected.isEmpty) return 'Selecciona al menos un participante';
    if (_splitMethod == 'percentage' && (_percentSum - 100).abs() > 0.001) {
      return 'Los porcentajes deben sumar 100 (ahora: ${_percentSum.toStringAsFixed(2)})';
    }
    return null;
  }

  List<Map<String, dynamic>> _buildSplits() {
    return _selected.map((memberId) {
      if (_splitMethod == 'percentage') {
        return {
          'group_member_id': memberId,
          'percentage': _percentControllers[memberId]!.text.replaceAll(',', '.').trim(),
        };
      }
      return {'group_member_id': memberId};
    }).toList();
  }

  /// Añade un miembro nuevo al grupo sin salir del formulario y lo deja
  /// ya seleccionado como participante del gasto.
  Future<void> _addParticipant() async {
    final created = await showAddMemberDialog(
      context: context,
      apiClient: _apiClient,
      groupId: widget.groupId,
      members: _members,
    );
    if (created == null || !mounted) return;
    setState(() {
      _members.add(created);
      _percentControllers[created['id']] = TextEditingController();
      _selected.add(created['id'] as String);
      _recomputeAutoPercentages();
    });
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _saving = true);
    try {
      final amount = _amountController.text.replaceAll(',', '.').trim();
      if (_isEditing) {
        await _apiClient.updateExpense(
          groupId: widget.groupId,
          expenseId: widget.expense!['id'],
          description: _descriptionController.text.trim(),
          amount: amount,
          paidBy: _paidById!,
          splitMethod: _splitMethod,
          splits: _buildSplits(),
          category: _category,
        );
      } else {
        await _apiClient.createExpense(
          groupId: widget.groupId,
          description: _descriptionController.text.trim(),
          amount: amount,
          paidBy: _paidById!,
          splitMethod: _splitMethod,
          splits: _buildSplits(),
          category: _category,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: Text('¿Seguro que quieres eliminar "${widget.expense!['description']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DividiColors.rojo,
              foregroundColor: Colors.white,
              minimumSize: const Size(64, 48),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _apiClient.deleteExpense(
        groupId: widget.groupId,
        expenseId: widget.expense!['id'],
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar gasto' : 'Nuevo gasto'),
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar gasto',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Descripción'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(labelText: 'Importe (€)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontFamily: DividiTheme.familiaTitulares,
              fontWeight: FontWeight.w800,
              fontSize: 26,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 20),
          const EtiquetaSeccion('Categoría'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((c) {
              final estilo = DividiTones.of(context).categoria(c);
              final seleccionada = _category == c;
              return ChoiceChip(
                avatar: Icon(
                  estilo.icono,
                  size: 18,
                  color: seleccionada
                      ? Theme.of(context).colorScheme.onPrimary
                      : estilo.color,
                ),
                label: Text(estilo.etiqueta),
                selected: seleccionada,
                showCheckmark: false,
                onSelected: (_) => setState(() => _category = c),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _paidById,
            decoration: const InputDecoration(labelText: 'Pagado por'),
            borderRadius: BorderRadius.circular(14),
            items: _members
                .map<DropdownMenuItem<String>>((m) => DropdownMenuItem(
                      value: m['id'] as String,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PersonaAvatar(nombre: m['display_name'], size: 26),
                          const SizedBox(width: 10),
                          Text(m['display_name']),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _paidById = value),
          ),
          const SizedBox(height: 24),
          const EtiquetaSeccion('¿Cómo se divide?'),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'equal', label: Text('Partes iguales')),
              ButtonSegment(value: 'percentage', label: Text('Porcentajes')),
            ],
            selected: {_splitMethod},
            onSelectionChanged: (selection) => setState(() {
              _splitMethod = selection.first;
              _recomputeAutoPercentages();
            }),
          ),
          if (_splitMethod == 'percentage')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Los campos que no toques se rellenan solos hasta sumar 100. '
                'Borra un campo para que vuelva a calcularse automáticamente.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
          const EtiquetaSeccion('¿Quiénes participan?'),
          const SizedBox(height: 6),
          ..._members.map((member) {
            final memberId = member['id'] as String;
            final isSelected = _selected.contains(memberId);
            return Column(
              children: [
                CheckboxListTile(
                  value: isSelected,
                  title: Row(
                    children: [
                      PersonaAvatar(nombre: member['display_name'], size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          member['display_name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(memberId);
                    } else {
                      _selected.remove(memberId);
                      _locked.remove(memberId);
                      _percentControllers[memberId]?.clear();
                    }
                    _recomputeAutoPercentages();
                  }),
                ),
                if (_splitMethod == 'percentage' && isSelected)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, bottom: 8),
                    child: TextField(
                      controller: _percentControllers[memberId],
                      decoration: InputDecoration(
                        labelText: 'Porcentaje (%)',
                        isDense: true,
                        // candado visual: fijado a mano vs calculado solo
                        suffixIcon: _locked.contains(memberId)
                            ? const Icon(Icons.lock_outline, size: 18)
                            : const Icon(Icons.autorenew, size: 18),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (text) => setState(() {
                        if (text.trim().isEmpty) {
                          _locked.remove(memberId);
                        } else {
                          _locked.add(memberId);
                        }
                        _recomputeAutoPercentages();
                      }),
                    ),
                  ),
              ],
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving ? null : _addParticipant,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Añadir participante nuevo al grupo'),
            ),
          ),
          if (_splitMethod == 'percentage')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Builder(builder: (context) {
                final tonos = DividiTones.of(context);
                final cuadra = (_percentSum - 100).abs() < 0.001;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: cuadra ? tonos.positivoFondo : tonos.negativoFondo,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'Suma: ${_percentSum.toStringAsFixed(2)} / 100',
                      style: TextStyle(
                        fontFamily: DividiTheme.familiaTitulares,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: cuadra ? tonos.positivo : tonos.negativo,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                );
              }),
            ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_isEditing ? 'Guardar cambios' : 'Guardar gasto'),
          ),
        ],
      ),
    );
  }
}
