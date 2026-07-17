import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';

/// Nómina y presupuestos (M12): declara tu ingreso mensual y pon techo
/// por categoría. Un campo vacío = esa categoría sin techo.
class FinancesFormScreen extends StatefulWidget {
  const FinancesFormScreen({super.key});

  @override
  State<FinancesFormScreen> createState() => _FinancesFormScreenState();
}

class _FinancesFormScreenState extends State<FinancesFormScreen> {
  static const _categorias = [
    'comida', 'transporte', 'alojamiento', 'ocio', 'otros',
  ];

  final _apiClient = ApiClient();
  final _nomina = TextEditingController();
  final _techos = {
    for (final categoria in _categorias) categoria: TextEditingController(),
  };
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nomina.dispose();
    for (final controller in _techos.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _editable(Object? valor) {
    final numero = double.tryParse(valor?.toString() ?? '');
    if (numero == null) return '';
    final fijo = numero.toStringAsFixed(2);
    return fijo.endsWith('.00')
        ? numero.toStringAsFixed(0)
        : fijo.replaceAll('.', ',');
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final finanzas = await _apiClient.getMyFinances();
      if (!mounted) return;
      _nomina.text = _editable(finanzas['monthly_income']);
      for (final budget in (finanzas['budgets'] as List<dynamic>? ?? const [])) {
        _techos[budget['category']]?.text = _editable(budget['limit_amount']);
      }
      setState(() => _cargando = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  double? _numero(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.'));

  Future<void> _guardar() async {
    final nominaTexto = _nomina.text.trim();
    final nomina = nominaTexto.isEmpty ? null : _numero(nominaTexto);
    if (nominaTexto.isNotEmpty && (nomina == null || nomina <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La nómina tiene que ser una cantidad mayor que cero.')));
      return;
    }

    final budgets = <Map<String, String>>[];
    for (final categoria in _categorias) {
      final texto = _techos[categoria]!.text.trim();
      if (texto.isEmpty) continue;
      final techo = _numero(texto);
      if (techo == null || techo <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('El techo de «$categoria» no parece una cantidad.')));
        return;
      }
      budgets.add({
        'category': categoria,
        'limit_amount': techo.toStringAsFixed(2),
      });
    }

    setState(() => _enviando = true);
    try {
      await _apiClient.putMyFinances(
        monthlyIncome: nomina?.toStringAsFixed(2),
        budgets: budgets,
      );
      if (mounted) Navigator.of(context).pop(true);
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
    final tonos = DividiTones.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nómina y presupuestos')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    EstadoVacio(
                      titulo: 'No se pudo cargar',
                      detalle: _error,
                      onRetry: _cargar,
                    ),
                  ])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                    children: [
                      TextField(
                        controller: _nomina,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Nómina mensual (€)',
                          helperText:
                              'Con ella, «Mi dinero» te dice cuánto te queda cada mes.',
                        ),
                      ),
                      const SizedBox(height: 26),
                      const EtiquetaSeccion('Techos por categoría'),
                      const SizedBox(height: 4),
                      Text(
                        'Cuánto quieres gastar como mucho al mes. '
                        'Déjalo vacío y esa categoría va libre.',
                        style: tema.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      for (final categoria in _categorias)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              CategoriaInsignia(categoria: categoria, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  tonos.categoria(categoria).etiqueta,
                                  style: tema.textTheme.titleSmall,
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _techos[categoria],
                                  textAlign: TextAlign.right,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    hintText: '—',
                                    suffixText: '€',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 26),
                      FilledButton(
                        onPressed: _enviando ? null : _guardar,
                        child: _enviando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Text('Guardar'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
