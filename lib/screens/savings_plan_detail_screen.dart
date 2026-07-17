import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';
import 'savings_plan_form_screen.dart';
import 'savings_tab.dart' show BarraHucha;

/// Detalle de un plan de ahorro.
///
/// La hucha se lleva a mano, porque la app no conoce tus cuentas reales:
/// - «Logrado este mes» confirma el mes con la cantidad que TÚ digas
///   (por defecto la planeada; quizá este mes pudiste más).
/// - «Este mes no pude…» cierra el mes con lo que fuera, aunque sea 0.
/// - «Ajustar la hucha» suma o resta en cualquier momento, sin justificar.
class SavingsPlanDetailScreen extends StatefulWidget {
  final String planId;

  const SavingsPlanDetailScreen({super.key, required this.planId});

  @override
  State<SavingsPlanDetailScreen> createState() =>
      _SavingsPlanDetailScreenState();
}

class _SavingsPlanDetailScreenState extends State<SavingsPlanDetailScreen> {
  final _apiClient = ApiClient();
  Map<String, dynamic>? _plan;
  String? _error;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final plan = await _apiClient.getSavingsPlan(widget.planId);
      if (mounted) setState(() => _plan = plan);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  double _num(Object? valor) => double.tryParse(valor?.toString() ?? '') ?? 0;

  // ------------------------------------------------------------ movimientos

  /// Diálogo de cantidad. Devuelve la cantidad normalizada («250.00») o null.
  Future<String?> _pedirCantidad({
    required String titulo,
    required String ayuda,
    String inicial = '',
    bool permitirCero = false,
  }) async {
    final controller = TextEditingController(text: inicial);
    final resultado = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ayuda, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cantidad (€)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (resultado == null) return null;
    final numero = double.tryParse(resultado.trim().replaceAll(',', '.'));
    if (numero == null || numero < 0 || (!permitirCero && numero == 0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eso no parece una cantidad válida.')),
        );
      }
      return null;
    }
    return numero.toStringAsFixed(2);
  }

  Future<void> _registrarMovimiento({
    required String kind,
    required String amount,
  }) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      final plan = await _apiClient.addSavingsEntry(
        planId: widget.planId,
        kind: kind,
        amount: amount,
      );
      if (mounted) setState(() => _plan = plan);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _logrado() async {
    final plan = _plan!;
    final cantidad = await _pedirCantidad(
      titulo: '¡Logrado!',
      ayuda: 'Confirma cuánto apartaste en '
          '${mesDePeriodo(plan['current_period'])}. Lo planeado eran '
          '${formatearImporte(plan['monthly_amount'])}, pero quizá este mes '
          'pudiste incluso más.',
      inicial: _cantidadPlaneada(plan),
      permitirCero: true,
    );
    if (cantidad != null) {
      await _registrarMovimiento(kind: 'monthly', amount: cantidad);
    }
  }

  Future<void> _noLogrado() async {
    final plan = _plan!;
    final cantidad = await _pedirCantidad(
      titulo: 'Este mes no pude',
      ayuda: 'Sin drama: apunta lo que sí lograste en '
          '${mesDePeriodo(plan['current_period'])}, aunque sea 0, '
          'y el mes queda cerrado.',
      inicial: '0',
      permitirCero: true,
    );
    if (cantidad != null) {
      await _registrarMovimiento(kind: 'monthly', amount: cantidad);
    }
  }

  Future<void> _ajustar() async {
    final anadir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajustar la hucha'),
        content: Text(
          'Es tu hucha y no hay que justificar nada: un imprevisto resta, '
          'dinero con el que no contabas suma.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Sacar dinero'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Añadir dinero'),
          ),
        ],
      ),
    );
    if (anadir == null) return;

    final cantidad = await _pedirCantidad(
      titulo: anadir ? 'Añadir a la hucha' : 'Sacar de la hucha',
      ayuda: anadir
          ? '¿Cuánto entra?'
          : '¿Cuánto sale? La hucha no puede quedar en negativo.',
    );
    if (cantidad != null) {
      await _registrarMovimiento(
        kind: 'adjustment',
        amount: anadir ? cantidad : '-$cantidad',
      );
    }
  }

  // ------------------------------------------------------------ editar/borrar

  Future<void> _editar() async {
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SavingsPlanFormScreen(plan: _plan)),
    );
    if (cambiado == true) await _cargar();
  }

  Future<void> _borrar() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar este plan?'),
        content: const Text(
            'Se pierde también su historial de movimientos. Esto no toca '
            'ningún grupo ni ningún gasto.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (seguro != true) return;
    try {
      await _apiClient.deleteSavingsPlan(widget.planId);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: Text(plan?['name'] ?? 'Plan de ahorro'),
        actions: [
          if (plan != null)
            PopupMenuButton<String>(
              onSelected: (accion) =>
                  accion == 'editar' ? _editar() : _borrar(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'editar', child: Text('Editar plan')),
                PopupMenuItem(value: 'borrar', child: Text('Borrar plan')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: plan == null
            ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: [
                    EstadoVacio(
                      titulo: 'No se pudo cargar el plan',
                      detalle: _error,
                      onRetry: _cargar,
                    ),
                  ])
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                  children: _contenido(tema, plan),
                ),
              ),
      ),
    );
  }

  List<Widget> _contenido(ThemeData tema, Map<String, dynamic> plan) {
    final tonos = DividiTones.of(context);
    final ahorrado = _num(plan['saved_amount']);
    final meta = _num(plan['target_amount']);
    final restante = _num(plan['remaining_amount']);
    final logrado = plan['is_completed'] == true;
    final confirmado = plan['is_current_period_confirmed'] == true;
    final meses = plan['months_to_goal'] as int? ?? 0;
    final entradas =
        List<Map<String, dynamic>>.from(plan['entries'] as List? ?? const [])
            .reversed
            .toList();

    return [
      // ---- hucha (superficie de marca: colores fijos día y noche)
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: DividiColors.tinta,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EN LA HUCHA',
              style: TextStyle(
                fontFamily: DividiTheme.familiaCuerpo,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: DividiColors.porcelana.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatearImporte(ahorrado),
              style: TextStyle(
                fontFamily: DividiTheme.familiaTitulares,
                fontWeight: FontWeight.w800,
                fontSize: 34,
                height: 1.15,
                color: logrado
                    ? const Color(0xFF7DD3A8)
                    : DividiColors.porcelana,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              logrado
                  ? 'meta de ${formatearImporte(meta)} conseguida'
                  : 'de ${formatearImporte(meta)} · quedan ${formatearImporte(restante)}',
              style: TextStyle(
                fontFamily: DividiTheme.familiaCuerpo,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: DividiColors.porcelana.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
            BarraHucha(progreso: meta <= 0 ? 0 : ahorrado / meta, alto: 13),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // ---- proyección
      if (!logrado)
        Text(
          meses == 1
              ? 'A ${formatearImporte(_num(plan['monthly_amount']))} al mes llegas en 1 mes — ${mesDePeriodo(plan['projected_period'])}.'
              : 'A ${formatearImporte(_num(plan['monthly_amount']))} al mes llegas en $meses meses — ${mesDePeriodo(plan['projected_period'])}.',
          style: tema.textTheme.bodyMedium,
        )
      else
        Text(
          '¡Conseguido! Puedes borrar el plan o subir la meta desde «Editar».',
          style: tema.textTheme.bodyMedium,
        ),
      const SizedBox(height: 20),

      // ---- el mes en curso
      if (confirmado)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: tonos.positivoFondo,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: tonos.positivo),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_capitalizar(mesDePeriodo(plan['current_period']))} ya está confirmado.',
                  style: TextStyle(
                    fontFamily: DividiTheme.familiaTitulares,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: tonos.positivo,
                  ),
                ),
              ),
            ],
          ),
        )
      else ...[
        FilledButton.icon(
          onPressed: _enviando ? null : _logrado,
          icon: const Icon(Icons.check_rounded, size: 22),
          label: Text('Logrado — ${mesDePeriodo(plan['current_period'])}'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _enviando ? null : _noLogrado,
          child: const Text('Este mes no pude…'),
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _enviando ? null : _ajustar,
        icon: const Icon(Icons.tune_rounded, size: 20),
        label: const Text('Ajustar la hucha (±)'),
      ),
      const SizedBox(height: 28),

      // ---- historial
      const EtiquetaSeccion('Movimientos'),
      const SizedBox(height: 6),
      if (entradas.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Todavía no hay movimientos. El primer «Logrado» estrena la hucha.',
            style: tema.textTheme.bodySmall,
          ),
        )
      else
        for (final entrada in entradas) _MovimientoTile(entrada: entrada),
    ];
  }

  String _cantidadPlaneada(Map<String, dynamic> plan) {
    final numero = _num(plan['monthly_amount']);
    final fijo = numero.toStringAsFixed(2);
    return fijo.endsWith('.00')
        ? numero.toStringAsFixed(0)
        : fijo.replaceAll('.', ',');
  }
}

String _capitalizar(String texto) =>
    texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

/// Fila del historial: cierre de mes o ajuste manual, con su importe firmado.
class _MovimientoTile extends StatelessWidget {
  final Map<String, dynamic> entrada;

  const _MovimientoTile({required this.entrada});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    final esMes = entrada['kind'] == 'monthly';
    final importe = double.tryParse(entrada['amount'].toString()) ?? 0;

    final titulo = esMes
        ? _capitalizar(mesDePeriodo(entrada['period']))
        : importe >= 0
            ? 'Ajuste — entró dinero'
            : 'Ajuste — salió dinero';
    final color = importe > 0.004
        ? tonos.positivo
        : importe < -0.004
            ? tonos.negativo
            : tonos.neutro;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tonos.neutroFondo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              esMes ? Icons.event_available_rounded : Icons.tune_rounded,
              size: 20,
              color: tonos.neutro,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: tema.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  fechaCorta(entrada['created_at']),
                  style: tema.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatearImporte(importe, conSigno: true),
            style: tema.textTheme.titleMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
