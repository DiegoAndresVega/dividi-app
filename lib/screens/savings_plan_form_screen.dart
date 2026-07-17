import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';

/// Crear o editar un plan de ahorro: meta, ritmo mensual y, al crear,
/// lo que ya hubiera apartado. Enseña en vivo cuándo se llegaría.
class SavingsPlanFormScreen extends StatefulWidget {
  /// Si llega un plan, la pantalla edita; si no, crea.
  final Map<String, dynamic>? plan;

  const SavingsPlanFormScreen({super.key, this.plan});

  @override
  State<SavingsPlanFormScreen> createState() => _SavingsPlanFormScreenState();
}

class _SavingsPlanFormScreenState extends State<SavingsPlanFormScreen> {
  final _apiClient = ApiClient();
  late final TextEditingController _nombre;
  late final TextEditingController _meta;
  late final TextEditingController _ritmo;
  final _apartado = TextEditingController();
  bool _enviando = false;

  bool get _esEdicion => widget.plan != null;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.plan?['name'] ?? '');
    _meta = TextEditingController(
        text: _cantidadEditable(widget.plan?['target_amount']));
    _ritmo = TextEditingController(
        text: _cantidadEditable(widget.plan?['monthly_amount']));
  }

  @override
  void dispose() {
    _nombre.dispose();
    _meta.dispose();
    _ritmo.dispose();
    _apartado.dispose();
    super.dispose();
  }

  double? _numero(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  /// Meses hasta la meta con lo escrito ahora mismo (null si aún no cuadra).
  int? get _mesesPrevistos {
    final meta = _numero(_meta);
    final ritmo = _numero(_ritmo);
    if (meta == null || ritmo == null || meta <= 0 || ritmo <= 0) return null;
    final apartado = _esEdicion
        ? (double.tryParse(widget.plan!['saved_amount'].toString()) ?? 0)
        : (_numero(_apartado) ?? 0);
    final restante = meta - apartado;
    if (restante <= 0) return 0;
    return (restante / ritmo).ceil();
  }

  String _periodoEnMeses(int meses) {
    final ahora = DateTime.now();
    final total = ahora.year * 12 + (ahora.month - 1) + meses;
    return '${total ~/ 12}-${(total % 12 + 1).toString().padLeft(2, '0')}';
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final meta = _numero(_meta);
    final ritmo = _numero(_ritmo);
    final apartado = _apartado.text.trim().isEmpty ? null : _numero(_apartado);

    String? error;
    if (nombre.isEmpty) {
      error = 'Ponle nombre al plan: un viaje, un colchón, lo que sea.';
    } else if (meta == null || meta <= 0) {
      error = 'La meta tiene que ser una cantidad mayor que cero.';
    } else if (ritmo == null || ritmo <= 0) {
      error = 'El ritmo mensual tiene que ser mayor que cero.';
    } else if (_apartado.text.trim().isNotEmpty &&
        (apartado == null || apartado < 0)) {
      error = 'Lo ya apartado no puede ser negativo.';
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _enviando = true);
    try {
      if (_esEdicion) {
        await _apiClient.updateSavingsPlan(
          planId: widget.plan!['id'],
          name: nombre,
          targetAmount: meta!.toStringAsFixed(2),
          monthlyAmount: ritmo!.toStringAsFixed(2),
        );
      } else {
        await _apiClient.createSavingsPlan(
          name: nombre,
          targetAmount: meta!.toStringAsFixed(2),
          monthlyAmount: ritmo!.toStringAsFixed(2),
          savedAmount:
              apartado == null || apartado == 0 ? null : apartado.toStringAsFixed(2),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final meses = _mesesPrevistos;
    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar plan' : 'Nuevo plan de ahorro'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Viaje a Japón, colchón, moto…',
              ),
              autofocus: !_esEdicion,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _meta,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Meta (€)',
                hintText: '2400',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ritmo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Ritmo mensual (€/mes)',
                hintText: '250',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!_esEdicion) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _apartado,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Ya tengo apartado (opcional)',
                  hintText: '0',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 22),
            if (meses != null)
              Text(
                meses == 0
                    ? 'Con eso la meta ya estaría cubierta.'
                    : meses == 1
                        ? 'A ese ritmo llegas en 1 mes — ${mesDePeriodo(_periodoEnMeses(1))}.'
                        : 'A ese ritmo llegas en $meses meses — ${mesDePeriodo(_periodoEnMeses(meses))}.',
                style: tema.textTheme.bodyMedium,
              ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _enviando ? null : _guardar,
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_esEdicion ? 'Guardar cambios' : 'Crear plan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// «300.00» de la API → «300» editable; «187.50» → «187,50».
String _cantidadEditable(Object? valor) {
  if (valor == null) return '';
  final numero = double.tryParse(valor.toString());
  if (numero == null) return '';
  final fijo = numero.toStringAsFixed(2);
  return fijo.endsWith('.00')
      ? numero.toStringAsFixed(0)
      : fijo.replaceAll('.', ',');
}
