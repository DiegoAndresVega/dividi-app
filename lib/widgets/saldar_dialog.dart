import 'package:flutter/material.dart';

import '../theme/dividi_format.dart';

/// Tolerancia de céntimo para comparar importes escritos a mano.
const _epsilon = 0.005;

/// Diálogo de «Registrar pago» con las dos formas de saldar una deuda:
/// la deuda entera o solo una parte (35 pendientes de los que se pagan 30 y
/// quedan 5). Devuelve el importe con dos decimales y punto decimal, tal como
/// lo espera la API, o `null` si se cancela.
Future<String?> mostrarDialogoSaldar(
  BuildContext context, {
  required String de,
  required String para,
  required double pendiente,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => DialogoSaldar(de: de, para: para, pendiente: pendiente),
  );
}

class DialogoSaldar extends StatefulWidget {
  final String de;
  final String para;
  final double pendiente;

  const DialogoSaldar({
    super.key,
    required this.de,
    required this.para,
    required this.pendiente,
  });

  @override
  State<DialogoSaldar> createState() => _DialogoSaldarState();
}

class _DialogoSaldarState extends State<DialogoSaldar> {
  final _controlador = TextEditingController();
  bool _parcial = false;
  String? _error;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  /// Importe escrito, admitiendo coma decimal; `null` si no es un número.
  double? get _importeEscrito =>
      double.tryParse(_controlador.text.replaceAll(',', '.').trim());

  String? _errorDeImporte() {
    final importe = _importeEscrito;
    if (importe == null || importe <= 0) {
      return 'Escribe un importe mayor que 0';
    }
    if (importe > widget.pendiente + _epsilon) {
      return 'Como mucho ${formatearImporte(widget.pendiente)}';
    }
    return null;
  }

  void _registrar() {
    if (!_parcial) {
      Navigator.of(context).pop(widget.pendiente.toStringAsFixed(2));
      return;
    }
    final error = _errorDeImporte();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_importeEscrito!.toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return AlertDialog(
      title: const Text('Registrar pago'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.de} → ${widget.para}',
              style: tema.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'Pendiente: ${formatearImporte(widget.pendiente)}',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Deuda completa')),
                ButtonSegment(value: true, label: Text('Saldar parte')),
              ],
              selected: {_parcial},
              onSelectionChanged: (seleccion) => setState(() {
                _parcial = seleccion.first;
                _error = null;
              }),
            ),
            if (_parcial) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _controlador,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Importe (€)',
                  helperText: 'El resto sigue pendiente',
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _registrar(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _registrar,
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
