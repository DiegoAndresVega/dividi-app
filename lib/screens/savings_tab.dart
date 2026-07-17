import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';
import 'finances_form_screen.dart';
import 'personal_expense_form_screen.dart';
import 'savings_plan_detail_screen.dart';
import 'savings_plan_form_screen.dart';

/// Pestaña «Mi dinero» (M11–M13): tu mes completo de puertas adentro.
///
/// El resumen junta tus gastos personales con tu parte de cada grupo;
/// los presupuestos avisan de los techos; y los planes de ahorro se
/// confirman a mano cada mes (la app no conoce tus cuentas reales).
class SavingsTab extends StatefulWidget {
  const SavingsTab({super.key});

  @override
  State<SavingsTab> createState() => _SavingsTabState();
}

/// Datos de la pestaña: resumen mensual, gastos personales y planes.
typedef _DatosMiDinero = (
  Map<String, dynamic> resumen,
  List<dynamic> personales,
  List<dynamic> planes,
);

class _SavingsTabState extends State<SavingsTab> {
  final _apiClient = ApiClient();
  late Future<_DatosMiDinero> _futuro;

  static const _cuantosPersonales = 5;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosMiDinero> _cargar() async {
    final resultados = await Future.wait<dynamic>([
      _apiClient.getMySummary(),
      _apiClient.getPersonalExpenses(),
      _apiClient.getSavingsPlans(),
    ]);
    return (
      resultados[0] as Map<String, dynamic>,
      resultados[1] as List<dynamic>,
      resultados[2] as List<dynamic>,
    );
  }

  Future<void> _refresh() async {
    final futuro = _cargar();
    setState(() => _futuro = futuro);
    await futuro;
  }

  Future<void> _abrirYRefrescar(Widget pantalla) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DatosMiDinero>(
      future: _futuro,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(children: [
              EstadoVacio(
                titulo: 'No se pudo cargar Mi dinero',
                detalle: '${snapshot.error}',
                onRetry: _refresh,
              ),
            ]),
          );
        }
        final (resumen, personales, planes) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            children: _contenido(resumen, personales, planes),
          ),
        );
      },
    );
  }

  List<Widget> _contenido(
    Map<String, dynamic> resumen,
    List<dynamic> personales,
    List<dynamic> planes,
  ) {
    final tema = Theme.of(context);
    final mes = mesDePeriodo(resumen['period']).split(' de ').first;
    return [
      Text('Mi dinero', style: tema.textTheme.displaySmall),
      const SizedBox(height: 2),
      Text(
        'Tu mes de puertas adentro — con tu parte de los grupos incluida.',
        style: tema.textTheme.bodySmall,
      ),
      const SizedBox(height: 18),

      // ---- resumen del mes (M11 + M12)
      _ResumenMesCard(resumen: resumen, mes: mes),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _abrirYRefrescar(const FinancesFormScreen()),
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: Text(
            resumen['monthly_income'] == null
                ? 'Añadir nómina y presupuestos'
                : 'Nómina y presupuestos',
          ),
        ),
      ),

      // ---- presupuestos (M12)
      if (_conPresupuesto(resumen).isNotEmpty) ...[
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EtiquetaSeccion('Presupuestos · $mes'),
                const SizedBox(height: 10),
                for (final fila in _conPresupuesto(resumen))
                  _BarraPresupuesto(fila: fila),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 18),

      // ---- gastos personales (M11)
      const EtiquetaSeccion('Gastos personales'),
      const SizedBox(height: 6),
      if (personales.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Lo que no se comparte con nadie: el gimnasio, el café, '
            'tus caprichos. Solo lo ves tú.',
            style: tema.textTheme.bodySmall,
          ),
        )
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (final (indice, gasto)
                    in personales.take(_cuantosPersonales).indexed) ...[
                  if (indice > 0) const Divider(height: 1),
                  _FilaPersonal(
                    gasto: gasto as Map<String, dynamic>,
                    onTap: () => _abrirYRefrescar(
                      PersonalExpenseFormScreen(gasto: gasto),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () =>
            _abrirYRefrescar(const PersonalExpenseFormScreen()),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Apuntar gasto personal'),
      ),
      const SizedBox(height: 26),

      // ---- planes de ahorro (M13)
      const EtiquetaSeccion('Planes de ahorro'),
      const SizedBox(height: 10),
      if (planes.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Un viaje, un colchón, un capricho grande — dime la meta y el '
            'ritmo mensual, y te digo cuándo llegas.',
            style: tema.textTheme.bodySmall,
          ),
        )
      else
        for (final plan in planes) ...[
          _PlanCard(
            plan: plan as Map<String, dynamic>,
            onTap: () => _abrirYRefrescar(
              SavingsPlanDetailScreen(planId: plan['id']),
            ),
          ),
          const SizedBox(height: 12),
        ],
      const SizedBox(height: 4),
      FilledButton.icon(
        onPressed: () async {
          final creado = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const SavingsPlanFormScreen()),
          );
          if (creado == true && mounted) await _refresh();
        },
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('Nuevo plan de ahorro'),
      ),
    ];
  }

  List<Map<String, dynamic>> _conPresupuesto(Map<String, dynamic> resumen) => [
        for (final fila in (resumen['by_category'] as List<dynamic>? ?? const []))
          if (fila['budget_limit'] != null) fila as Map<String, dynamic>,
      ];
}

/// Tarjeta-resumen del mes sobre Tinta: disponible (si hay nómina) o el
/// total gastado, con el desglose personal/grupos en la línea pequeña.
class _ResumenMesCard extends StatelessWidget {
  final Map<String, dynamic> resumen;
  final String mes;

  const _ResumenMesCard({required this.resumen, required this.mes});

  double _num(Object? valor) => double.tryParse(valor?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final disponible =
        resumen['available'] == null ? null : _num(resumen['available']);
    final gastado = _num(resumen['total_spent']);
    final parteGrupos = _num(resumen['groups_share_total']);

    final titulo = disponible == null ? 'Gastado en $mes' : 'Disponible en $mes';
    final cifra = disponible ?? gastado;
    final colorCifra = disponible == null
        ? DividiColors.porcelana
        : disponible < 0
            ? const Color(0xFFE9857A)
            : const Color(0xFF7DD3A8);
    final detalle = disponible == null
        ? 'de ellos, tu parte de los grupos: ${formatearImporte(parteGrupos)}'
        : 'Nómina ${formatearImporte(_num(resumen['monthly_income']))} · '
            'gastado ${formatearImporte(gastado)} — parte de grupos: '
            '${formatearImporte(parteGrupos)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: DividiColors.tinta,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo.toUpperCase(),
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
            formatearImporte(cifra),
            style: TextStyle(
              fontFamily: DividiTheme.familiaTitulares,
              fontWeight: FontWeight.w800,
              fontSize: 34,
              height: 1.15,
              color: colorCifra,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detalle,
            style: TextStyle(
              fontFamily: DividiTheme.familiaCuerpo,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: DividiColors.porcelana.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de presupuesto (M12): gastado sobre el techo de la categoría.
class _BarraPresupuesto extends StatelessWidget {
  final Map<String, dynamic> fila;

  const _BarraPresupuesto({required this.fila});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    final gastado = double.tryParse(fila['total'].toString()) ?? 0;
    final techo = double.tryParse(fila['budget_limit'].toString()) ?? 1;
    final pasado = gastado > techo;
    final estilo = tonos.categoria(fila['category']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(estilo.etiqueta, style: tema.textTheme.titleSmall),
              ),
              Text(
                '${formatearImporte(gastado).replaceAll(' €', '')} / '
                '${formatearImporte(techo)}',
                style: TextStyle(
                  fontFamily: DividiTheme.familiaTitulares,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: pasado ? tonos.negativo : tema.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 9,
              color: tonos.neutroFondo,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (gastado / techo).clamp(0.0, 1.0),
                child: Container(
                  color: pasado ? tonos.negativo : DividiColors.ambar,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de gasto personal: insignia de categoría, descripción y fecha.
class _FilaPersonal extends StatelessWidget {
  final Map<String, dynamic> gasto;
  final VoidCallback onTap;

  const _FilaPersonal({required this.gasto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CategoriaInsignia(categoria: gasto['category'], size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gasto['description'],
                    style: tema.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Solo tú · ${fechaCorta(gasto['created_at'])}',
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatearImporte(gasto['amount']),
              style: tema.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de un plan: nombre, barra de progreso, «ahorrado de meta» y
/// cuántos meses quedan al ritmo actual.
class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onTap;

  const _PlanCard({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    final ahorrado = double.tryParse(plan['saved_amount'].toString()) ?? 0;
    final meta = double.tryParse(plan['target_amount'].toString()) ?? 1;
    final logrado = plan['is_completed'] == true;
    final meses = plan['months_to_goal'] as int? ?? 0;
    final confirmado = plan['is_current_period_confirmed'] == true;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan['name'],
                      style: tema.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: logrado ? tonos.positivoFondo : tonos.neutroFondo,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      logrado
                          ? '¡Conseguido!'
                          : meses == 1
                              ? 'queda 1 mes'
                              : 'quedan $meses meses',
                      style: TextStyle(
                        fontFamily: DividiTheme.familiaTitulares,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: logrado ? tonos.positivo : tonos.neutro,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BarraHucha(progreso: meta <= 0 ? 0 : ahorrado / meta),
              const SizedBox(height: 8),
              Text(
                '${formatearImporte(ahorrado)} de ${formatearImporte(meta)}'
                '${confirmado ? ' · este mes ✓' : ''}',
                style: tema.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de progreso de la hucha: ámbar mientras se ahorra, verde al llegar.
class BarraHucha extends StatelessWidget {
  final double progreso;
  final double alto;

  const BarraHucha({super.key, required this.progreso, this.alto = 12});

  @override
  Widget build(BuildContext context) {
    final tonos = DividiTones.of(context);
    final completo = progreso >= 0.999;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: alto,
        color: tonos.neutroFondo,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progreso.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: completo ? tonos.positivo : DividiColors.ambar,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}
