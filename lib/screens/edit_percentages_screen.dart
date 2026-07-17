import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';

/// Editor del reparto del grupo: pones el porcentaje de cada miembro a mano y
/// nada se ajusta solo mientras escribes. Si no suman 100, avisa al guardar.
///
/// Con «Completar automáticamente» el último miembro se calcula solo (lo que
/// falte hasta 100), para no tener que cuadrarlo tú.
class EditPercentagesScreen extends StatefulWidget {
  final String groupId;
  final List<dynamic> members;

  const EditPercentagesScreen({
    super.key,
    required this.groupId,
    required this.members,
  });

  @override
  State<EditPercentagesScreen> createState() => _EditPercentagesScreenState();
}

class _EditPercentagesScreenState extends State<EditPercentagesScreen> {
  final _apiClient = ApiClient();
  final Map<String, TextEditingController> _controllers = {};
  bool _autoCompletar = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final m in widget.members) {
      final peso = double.tryParse('${m['default_percentage']}') ?? 0;
      _controllers[m['id']] = TextEditingController(text: _fmt(peso));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(double v) {
    final t = v.toStringAsFixed(2);
    return t.endsWith('.00') ? v.toStringAsFixed(0) : t;
  }

  double _num(String id) =>
      double.tryParse(_controllers[id]!.text.replaceAll(',', '.')) ?? 0;

  /// Solo hay un campo «automático» si el modo está activo y hay más de uno.
  bool get _hayAuto => _autoCompletar && widget.members.length > 1;
  String? get _autoId => _hayAuto ? widget.members.last['id'] as String : null;

  double _sumaEditables() {
    var s = 0.0;
    for (final m in widget.members) {
      if (m['id'] == _autoId) continue;
      s += _num(m['id'] as String);
    }
    return s;
  }

  double get _restanteAuto => 100 - _sumaEditables();

  double get _suma {
    if (_hayAuto) {
      final r = _restanteAuto;
      return r < 0 ? _sumaEditables() : 100.0;
    }
    var s = 0.0;
    for (final m in widget.members) {
      s += _num(m['id'] as String);
    }
    return s;
  }

  bool get _cuadra => (_suma - 100).abs() < 0.001;

  ({Map<String, String>? valores, String? error}) _construir() {
    final valores = <String, String>{};
    if (_hayAuto) {
      final restante = _restanteAuto;
      if (restante < -0.001) {
        return (valores: null, error: 'Los porcentajes de los demás superan 100');
      }
      for (final m in widget.members) {
        final id = m['id'] as String;
        final v = id == _autoId ? restante : _num(id);
        valores[id] = v.toStringAsFixed(2);
      }
    } else {
      var suma = 0.0;
      for (final m in widget.members) {
        final id = m['id'] as String;
        final v = _num(id);
        if (v < 0 || v > 100) {
          return (valores: null, error: 'Cada porcentaje debe estar entre 0 y 100');
        }
        valores[id] = v.toStringAsFixed(2);
        suma += v;
      }
      if ((suma - 100).abs() > 0.001) {
        return (
          valores: null,
          error: 'Los porcentajes deben sumar 100 (ahora: ${suma.toStringAsFixed(2)})'
        );
      }
    }
    return (valores: valores, error: null);
  }

  Future<void> _guardar() async {
    final r = _construir();
    if (r.error != null) {
      _aviso(r.error!);
      return;
    }
    final valores = r.valores!;
    final primaryId = widget.members.first['id'] as String;
    final rebalance = <String, String>{
      for (final e in valores.entries)
        if (e.key != primaryId) e.key: e.value,
    };

    setState(() => _saving = true);
    try {
      await _apiClient.updateMember(
        groupId: widget.groupId,
        memberId: primaryId,
        defaultPercentage: valores[primaryId],
        rebalance: rebalance.isEmpty ? null : rebalance,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Editar porcentajes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          Text(
            'El peso de cada miembro es su parte de los ingresos. Ponlos a mano '
            '— nada cambia solo mientras escribes — y deben sumar 100.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final m in widget.members) ...[
            _FilaPorcentaje(
              nombre: m['display_name'] as String,
              controller: _controllers[m['id']]!,
              esAuto: m['id'] == _autoId,
              valorAuto: _restanteAuto,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          CheckboxListTile(
            value: _autoCompletar,
            onChanged: widget.members.length > 1
                ? (v) => setState(() => _autoCompletar = v ?? false)
                : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Completar automáticamente'),
            subtitle: const Text(
                'El último miembro se ajusta solo con lo que falte hasta 100'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _cuadra ? tonos.positivoFondo : tonos.negativoFondo,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'Suma: ${_suma.toStringAsFixed(2)} / 100',
                style: TextStyle(
                  fontFamily: DividiTheme.familiaTitulares,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: _cuadra ? tonos.positivo : tonos.negativo,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _saving ? null : _guardar,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Guardar reparto'),
          ),
        ],
      ),
    );
  }
}

class _FilaPorcentaje extends StatelessWidget {
  final String nombre;
  final TextEditingController controller;
  final bool esAuto;
  final double valorAuto;
  final VoidCallback onChanged;

  const _FilaPorcentaje({
    required this.nombre,
    required this.controller,
    required this.esAuto,
    required this.valorAuto,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      children: [
        PersonaAvatar(nombre: nombre, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tema.textTheme.bodyLarge,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: esAuto
              ? InputDecorator(
                  decoration: const InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    helperText: 'auto',
                  ),
                  child: Text(
                    valorAuto.clamp(0, 100).toStringAsFixed(
                        valorAuto == valorAuto.roundToDouble() ? 0 : 2),
                    textAlign: TextAlign.end,
                    style: tema.textTheme.bodyLarge?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              : TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.end,
                  onChanged: (_) => onChanged(),
                  decoration:
                      const InputDecoration(suffixText: '%', isDense: true),
                ),
        ),
      ],
    );
  }
}
