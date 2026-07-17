import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/add_member_dialog.dart';
import '../widgets/dividi_bits.dart';

/// Formulario de gasto (lámina S3 del manual): sirve para crear
/// (expense == null) y para editar.
///
/// Permite elegir con quién se comparte el gasto y el método de reparto —
/// los cuatro de la API: iguales, porcentajes (suman 100), importes exactos
/// (suman el total) y partes — con previsualización en vivo de lo que paga
/// cada uno.
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

  /// Miembros que participan en el gasto y, según el método, el controlador
  /// con el % / importe exacto / partes de cada uno.
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _percentControllers = {};
  // foco de cada campo de %: mientras se edita uno, no se recalcula solo
  // (así se puede borrar la cifra por defecto sin que se rellene al instante)
  final Map<String, FocusNode> _percentFocus = {};
  final Map<String, TextEditingController> _exactControllers = {};
  final Map<String, TextEditingController> _sharesControllers = {};

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
      final id = member['id'] as String;
      _percentControllers[id] = TextEditingController();
      _percentFocus[id] = FocusNode()..addListener(() => _onPercentFocusChange(id));
      _exactControllers[id] = TextEditingController();
      _sharesControllers[id] = TextEditingController(text: '1');
    }

    final expense = widget.expense;
    if (expense == null) {
      // por defecto: participan todos, paga el primero y el reparto es
      // «según ingresos» — la seña de identidad de Dividi — precargando
      // el peso de cada miembro en el hogar (sus % por defecto del grupo)
      _selected.addAll(_members.map((m) => m['id'] as String));
      _paidById = _members.isNotEmpty ? _members.first['id'] : null;
      _splitMethod = 'percentage';
      var hayPesos = false;
      for (final member in _members) {
        final peso =
            double.tryParse('${member['default_percentage'] ?? ''}') ?? 0;
        if (peso > 0) hayPesos = true;
      }
      if (hayPesos) {
        for (final member in _members) {
          final memberId = member['id'] as String;
          final peso =
              double.tryParse('${member['default_percentage'] ?? ''}') ?? 0;
          _percentControllers[memberId]!.text = _formatPercent(peso);
          _locked.add(memberId);
        }
      }
    } else {
      _descriptionController.text = expense['description'];
      _amountController.text = expense['amount'].toString();
      _category = expense['category'];
      _paidById = expense['paid_by_id'];
      _splitMethod = expense['split_method'];
      for (final split in (expense['splits'] as List<dynamic>)) {
        final memberId = split['group_member_id'] as String;
        _selected.add(memberId);
        if (split['percentage'] != null) {
          _percentControllers[memberId]?.text = split['percentage'].toString();
          // al editar, los % existentes se consideran fijados por el usuario
          _locked.add(memberId);
        }
        if (split['exact_amount'] != null) {
          _exactControllers[memberId]?.text = split['exact_amount'].toString();
        }
        if (split['shares'] != null) {
          _sharesControllers[memberId]?.text = split['shares'].toString();
        }
      }
    }
    _recomputeAutoPercentages();
  }

  /// Id del campo de % que se está editando ahora mismo (con el foco), o null.
  String? get _focusedPercentId {
    for (final entry in _percentFocus.entries) {
      if (entry.value.hasFocus) return entry.key;
    }
    return null;
  }

  /// Al perder el foco un campo vacío vuelve a ser automático (se recalcula);
  /// mientras se edita se deja en paz para poder borrar y teclear a gusto.
  void _onPercentFocusChange(String memberId) {
    final focus = _percentFocus[memberId];
    if (focus == null || focus.hasFocus) return;
    if ((_percentControllers[memberId]?.text.trim() ?? '').isEmpty) {
      setState(() {
        _locked.remove(memberId);
        _recomputeAutoPercentages();
      });
    }
  }

  /// Reparte lo que falte hasta 100 entre los campos no fijados (automáticos).
  /// El último absorbe el resto del redondeo para que siempre sume 100 exacto.
  /// Nunca escribe en el campo que se está editando (el que tiene el foco).
  void _recomputeAutoPercentages() {
    if (_splitMethod != 'percentage') return;
    final focusedId = _focusedPercentId;
    final autoIds = _selected
        .where((id) => !_locked.contains(id) && id != focusedId)
        .toList();
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
    for (final node in _percentFocus.values) {
      node.dispose();
    }
    for (final controller in _exactControllers.values) {
      controller.dispose();
    }
    for (final controller in _sharesControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _amountValue =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  double _numero(TextEditingController? controller) =>
      double.tryParse(controller?.text.replaceAll(',', '.') ?? '') ?? 0;

  double get _percentSum {
    var sum = 0.0;
    for (final id in _selected) {
      sum += _numero(_percentControllers[id]);
    }
    return sum;
  }

  double get _exactSum {
    var sum = 0.0;
    for (final id in _selected) {
      sum += _numero(_exactControllers[id]);
    }
    return sum;
  }

  /// Miembros seleccionados, en el orden estable de la lista del grupo.
  List<dynamic> get _participantes =>
      _members.where((m) => _selected.contains(m['id'])).toList();

  String? _validate() {
    if (_descriptionController.text.trim().isEmpty) return 'Pon un concepto';
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) return 'El importe debe ser un número mayor que 0';
    if (_paidById == null) return 'Elige quién pagó';
    if (_selected.isEmpty) return 'Selecciona al menos un participante';
    if (_splitMethod == 'percentage' && (_percentSum - 100).abs() > 0.001) {
      return 'Los porcentajes deben sumar 100 (ahora: ${_percentSum.toStringAsFixed(2)})';
    }
    if (_splitMethod == 'exact' && (_exactSum - amount).abs() > 0.001) {
      return 'Los importes exactos deben sumar ${amount.toStringAsFixed(2)} (ahora: ${_exactSum.toStringAsFixed(2)})';
    }
    if (_splitMethod == 'shares') {
      for (final id in _selected) {
        final partes = int.tryParse(_sharesControllers[id]?.text.trim() ?? '');
        if (partes == null || partes < 1) {
          return 'Las partes deben ser números enteros mayores que 0';
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _buildSplits() {
    return _participantes.map<Map<String, dynamic>>((member) {
      final memberId = member['id'] as String;
      return switch (_splitMethod) {
        'percentage' => {
            'group_member_id': memberId,
            'percentage':
                _percentControllers[memberId]!.text.replaceAll(',', '.').trim(),
          },
        'exact' => {
            'group_member_id': memberId,
            'exact_amount':
                _exactControllers[memberId]!.text.replaceAll(',', '.').trim(),
          },
        'shares' => {
            'group_member_id': memberId,
            'shares': int.parse(_sharesControllers[memberId]!.text.trim()),
          },
        _ => {'group_member_id': memberId},
      };
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
      final id = created['id'] as String;
      _members.add(created);
      _percentControllers[id] = TextEditingController();
      _percentFocus[id] = FocusNode()..addListener(() => _onPercentFocusChange(id));
      _exactControllers[id] = TextEditingController();
      _sharesControllers[id] = TextEditingController(text: '1');
      _selected.add(id);
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          // el importe es el protagonista de la pantalla
          TextField(
            controller: _amountController,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontFamily: DividiTheme.familiaTitulares,
              fontWeight: FontWeight.w800,
              fontSize: 40,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: '0,00',
              suffixText: '€',
              suffixStyle: TextStyle(
                fontFamily: DividiTheme.familiaTitulares,
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Concepto'),
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
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'percentage', label: Text('Ingresos')),
              ButtonSegment(value: 'equal', label: Text('Iguales')),
              ButtonSegment(value: 'exact', label: Text('Exacto')),
              ButtonSegment(value: 'shares', label: Text('Partes')),
            ],
            selected: {_splitMethod},
            onSelectionChanged: (selection) => setState(() {
              _splitMethod = selection.first;
              _recomputeAutoPercentages();
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              switch (_splitMethod) {
                'percentage' =>
                  'El peso de cada uno en el hogar (su parte de los ingresos): '
                      'quien gana más aporta más y a todos les cuesta el mismo esfuerzo. '
                      'Los campos que no toques se ajustan solos hasta sumar 100.',
                'exact' =>
                  'Importes exactos por persona: deben sumar el total del gasto.',
                'shares' =>
                  'Reparto proporcional por partes: quien tiene 2 partes paga el doble que quien tiene 1.',
                _ =>
                  'A partes iguales entre los participantes. El último de la lista absorbe el céntimo del redondeo.',
              },
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
                      focusNode: _percentFocus[memberId],
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
                if (_splitMethod == 'exact' && isSelected)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, bottom: 8),
                    child: TextField(
                      controller: _exactControllers[memberId],
                      decoration: const InputDecoration(
                        labelText: 'Importe (€)',
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                if (_splitMethod == 'shares' && isSelected)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, bottom: 8),
                    child: TextField(
                      controller: _sharesControllers[memberId],
                      decoration: const InputDecoration(
                        labelText: 'Partes',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
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
            _PildoraSuma(
              texto: 'Suma: ${_percentSum.toStringAsFixed(2)} / 100',
              cuadra: (_percentSum - 100).abs() < 0.001,
            ),
          if (_splitMethod == 'exact' && _amountValue > 0)
            _PildoraSuma(
              texto:
                  'Suma: ${_exactSum.toStringAsFixed(2)} / ${_amountValue.toStringAsFixed(2)}',
              cuadra: (_exactSum - _amountValue).abs() < 0.001,
            ),

          // lo que paga cada uno, calculado en vivo (el importe definitivo
          // siempre lo confirma la API al guardar)
          if (_amountValue > 0 && _selected.isNotEmpty) ...[
            const SizedBox(height: 24),
            const EtiquetaSeccion('Lo que paga cada uno'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Builder(builder: (context) {
                  final participantes = _participantes;
                  final entradas = participantes.map((m) {
                    final id = m['id'] as String;
                    return switch (_splitMethod) {
                      'percentage' => _numero(_percentControllers[id]),
                      'exact' => _numero(_exactControllers[id]),
                      'shares' => _numero(_sharesControllers[id]),
                      _ => 0.0,
                    };
                  }).toList();
                  final partes = previsualizarReparto(
                    metodo: _splitMethod,
                    total: _amountValue,
                    entradas: entradas,
                  );
                  final tema = Theme.of(context);
                  return Column(
                    children: [
                      for (final (indice, member) in participantes.indexed) ...[
                        if (indice > 0) const Divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              PersonaAvatar(
                                  nombre: member['display_name'], size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  member['display_name'],
                                  style: tema.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                formatearImporte(
                                    indice < partes.length ? partes[indice] : 0),
                                style: tema.textTheme.titleSmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                }),
              ),
            ),
          ],
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

/// Píldora de control de suma: verde cuando cuadra, roja cuando no.
class _PildoraSuma extends StatelessWidget {
  final String texto;
  final bool cuadra;

  const _PildoraSuma({required this.texto, required this.cuadra});

  @override
  Widget build(BuildContext context) {
    final tonos = DividiTones.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: cuadra ? tonos.positivoFondo : tonos.negativoFondo,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontFamily: DividiTheme.familiaTitulares,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: cuadra ? tonos.positivo : tonos.negativo,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
