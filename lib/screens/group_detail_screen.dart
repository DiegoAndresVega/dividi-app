import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';
import '../widgets/donut_categorias.dart';
import '../widgets/tique_sheet.dart';
import 'expense_form_screen.dart';
import 'members_screen.dart';
import 'recurring_screen.dart';
import 'settle_up_screen.dart';

/// Detalle de grupo (lámina S2 del manual): balances con barras centradas
/// en cero, botón «Saldar cuentas» y los gastos recientes con tu parte.
class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _apiClient = ApiClient();
  late Future<_DatosGrupo> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosGrupo> _cargar() async {
    final resultados = await Future.wait<dynamic>([
      _apiClient.getGroup(widget.groupId),
      _apiClient.getBalances(widget.groupId),
      _apiClient.getExpenses(widget.groupId),
      _apiClient.getPayments(widget.groupId),
      _apiClient.currentUserId(),
    ]);
    return _DatosGrupo(
      grupo: resultados[0] as Map<String, dynamic>,
      balances: resultados[1] as List<dynamic>,
      gastos: resultados[2] as List<dynamic>,
      pagos: resultados[3] as List<dynamic>,
      userId: resultados[4] as String?,
    );
  }

  Future<void> _refresh() async {
    final futuro = _cargar();
    setState(() {
      _futuro = futuro;
    });
    await futuro;
  }

  /// Abre el formulario de gasto: para crear (expense == null) o editar.
  Future<void> _openExpenseForm({Map<String, dynamic>? expense}) async {
    final datos = await _futuro;
    if (!mounted) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          groupId: widget.groupId,
          members: datos.miembros,
          expense: expense,
        ),
      ),
    );
    // refrescar siempre: aunque el gasto se cancele, pudo añadirse un
    // participante nuevo al grupo desde el formulario
    if (mounted) await _refresh();
  }

  Future<void> _abrirMiembros() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MembersScreen(
          groupId: widget.groupId,
          groupName: widget.groupName,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _abrirSaldar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettleUpScreen(
          groupId: widget.groupId,
          groupName: widget.groupName,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _abrirRecurrentes() async {
    final datos = await _futuro;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecurringScreen(
          groupId: widget.groupId,
          groupName: widget.groupName,
          miembros: datos.miembros,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  /// Exporta el resumen del grupo en CSV y abre la hoja de compartir (M9).
  Future<void> _exportarCsv() async {
    try {
      final csv = await _apiClient.exportGroupCsv(widget.groupId);
      final carpeta = await getTemporaryDirectory();
      final nombre = widget.groupName
          .replaceAll(RegExp(r'[^\w\- ]'), '')
          .trim()
          .replaceAll(' ', '-');
      final archivo = File(
          '${carpeta.path}/dividi-${nombre.isEmpty ? 'grupo' : nombre}.csv');
      await archivo.writeAsString(csv);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(archivo.path, mimeType: 'text/csv')],
        subject: 'Resumen de ${widget.groupName} · Dividi',
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Borra el grupo entero. Si queda deuda viva el aviso es más serio y hay
  /// que confirmar dos veces: un grupo con cuentas abiertas no se borra sin
  /// querer, pero uno creado por error tampoco te deja atrapado.
  Future<void> _borrarGrupo() async {
    final datos = await _futuro;
    if (!mounted) return;

    if (!datos.soyAdmin) {
      _aviso('Solo un administrador del grupo puede borrarlo');
      return;
    }

    final divisa = datos.grupo['default_currency'] as String? ?? 'EUR';
    final saldado = datos.estaSaldado;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(saldado ? 'Borrar el grupo' : 'Este grupo tiene cuentas abiertas'),
        content: Text(
          saldado
              ? 'Se borrarán «${widget.groupName}» y todo su historial de '
                  'gastos y pagos. Esto no se puede deshacer.'
              : 'Quedan ${formatearImporte(datos.deudaPendiente, divisa: divisa)} '
                  'por saldar. Si lo borras, se perderán los gastos, los pagos '
                  'y quién debe qué a quién. Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: DividiColors.rojo),
            child: Text(saldado ? 'Borrar' : 'Borrar de todas formas'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    // segunda confirmación solo cuando hay dinero en juego
    if (!saldado) {
      final seguro = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Seguro?'),
          content: Text(
            'Última oportunidad: se borra «${widget.groupName}» con sus cuentas '
            'sin saldar. Si solo quieres dejarlo, sal del grupo desde '
            'Participantes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Mejor no'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: DividiColors.rojo),
              child: const Text('Sí, borrar'),
            ),
          ],
        ),
      );
      if (seguro != true || !mounted) return;
    }

    try {
      await _apiClient.deleteGroup(widget.groupId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    }
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _abrirTique(Map<String, dynamic> gasto) async {
    final cambio = await mostrarTiqueSheet(
      context,
      apiClient: _apiClient,
      groupId: widget.groupId,
      gasto: gasto,
    );
    if (cambio && mounted) await _refresh();
  }

  Future<void> _abrirTodosLosGastos(_DatosGrupo datos) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TodosLosGastosScreen(
          groupId: widget.groupId,
          groupName: widget.groupName,
          miembros: datos.miembros,
          miMiembroId: datos.miMiembroId,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (accion) => switch (accion) {
              'recurrentes' => _abrirRecurrentes(),
              'borrar' => _borrarGrupo(),
              _ => _exportarCsv(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'recurrentes',
                child: Text('Gastos recurrentes'),
              ),
              const PopupMenuItem(value: 'exportar', child: Text('Exportar CSV')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'borrar',
                child: Text(
                  'Borrar grupo',
                  style: TextStyle(color: DividiColors.rojo),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_DatosGrupo>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                EstadoVacio(
                  titulo: 'No se pudo cargar el grupo',
                  detalle: '${snapshot.error}',
                  onRetry: _refresh,
                ),
              ]);
            }
            final datos = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
              children: [
                // cabecera: cuántos son + pila de avatares (toca para gestionar)
                InkWell(
                  onTap: _abrirMiembros,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(datos.subtitulo,
                              style: tema.textTheme.bodySmall),
                        ),
                        PilaAvatares(nombres: datos.nombresMiembros, size: 28),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // balances del grupo
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EtiquetaSeccion('Balances del grupo'),
                        const SizedBox(height: 8),
                        if (datos.balances.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('Sin balances todavía.',
                                style: tema.textTheme.bodySmall),
                          )
                        else
                          for (final balance in datos.balances)
                            _FilaBalance(
                              nombre: balance['display_name'],
                              importe: double.tryParse(
                                      balance['balance'].toString()) ??
                                  0,
                              maximo: datos.balanceMaximo,
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // saldar cuentas
                FilledButton.icon(
                  onPressed: _abrirSaldar,
                  icon: const _IconoObelo(),
                  label: const Text('Saldar cuentas'),
                ),
                const SizedBox(height: 14),

                // ¿en qué se nos va? — dónut por categorías (M5)
                if (datos.gastosDelDonut.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EtiquetaSeccion(
                              '¿En qué se nos va? · ${datos.etiquetaDonut}'),
                          const SizedBox(height: 12),
                          DonutCategorias(gastos: datos.gastosDelDonut),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // gastos recientes
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                                child: EtiquetaSeccion('Gastos recientes')),
                            if (datos.gastos.length > _cuantosRecientes)
                              TextButton(
                                onPressed: () => _abrirTodosLosGastos(datos),
                                child: const Text('Ver todos'),
                              ),
                          ],
                        ),
                        if (datos.gastos.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            child: Text(
                              'Todavía no hay gastos. Apunta el primero con «Nuevo gasto».',
                              style: tema.textTheme.bodySmall,
                            ),
                          )
                        else
                          for (final (indice, gasto)
                              in datos.gastos.take(_cuantosRecientes).indexed) ...[
                            if (indice > 0) const Divider(),
                            FilaGasto(
                              gasto: gasto,
                              nombrePagador:
                                  datos.nombreMiembro(gasto['paid_by_id']),
                              miMiembroId: datos.miMiembroId,
                              onTap: () => _openExpenseForm(
                                  expense: gasto as Map<String, dynamic>),
                              onLongPress: () =>
                                  _abrirTique(gasto as Map<String, dynamic>),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),

                // pagos entre miembros (M6): «te lo pagué el martes», con recibo
                if (datos.pagos.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const EtiquetaSeccion('Pagos entre miembros'),
                          const SizedBox(height: 4),
                          for (final pago in datos.pagos)
                            _FilaPago(
                              de: datos.nombreMiembro(pago['from_member_id']),
                              a: datos.nombreMiembro(pago['to_member_id']),
                              fecha: pago['paid_at'],
                              importe: double.tryParse(
                                      pago['amount'].toString()) ??
                                  0,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExpenseForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo gasto'),
      ),
    );
  }

  static const _cuantosRecientes = 5;
}

/// El óbelo de la marca como icono del botón «Saldar cuentas».
class _IconoObelo extends StatelessWidget {
  const _IconoObelo();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    Widget punto() => Container(
          width: 4.5,
          height: 4.5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        punto(),
        Container(
          width: 16,
          height: 3.5,
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        punto(),
      ],
    );
  }
}

/// Fila de balance: nombre, barra centrada en cero y el importe con signo.
class _FilaBalance extends StatelessWidget {
  final String nombre;
  final double importe;
  final double maximo;

  const _FilaBalance({
    required this.nombre,
    required this.importe,
    required this.maximo,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    final positivo = importe > 0.004;
    final negativo = importe < -0.004;
    final fraccion = maximo <= 0 ? 0.0 : (importe.abs() / maximo).clamp(0.0, 1.0);
    final colorImporte = positivo
        ? tonos.positivo
        : negativo
            ? tonos.negativo
            : tonos.neutro;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: tonos.colorPersona(nombre),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    nombre,
                    style: tema.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 22,
              child: CustomPaint(
                painter: _PintorBarra(
                  fraccion: positivo || negativo ? fraccion : 0,
                  positivo: positivo,
                  eje: tema.colorScheme.outline,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              formatearImporte(importe, conSigno: true).replaceAll(' €', ''),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: DividiTheme.familiaTitulares,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: colorImporte,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PintorBarra extends CustomPainter {
  final double fraccion;
  final bool positivo;
  final Color eje;

  // verde/rojo de barra fijos, como en el manual: funcionan en día y noche
  static const _verde = Color(0xFF2E9E6B);
  static const _rojo = Color(0xFFD4685D);

  const _PintorBarra({
    required this.fraccion,
    required this.positivo,
    required this.eje,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.width / 2;
    canvas.drawLine(
      Offset(centro, -2),
      Offset(centro, size.height + 2),
      Paint()
        ..color = eje
        ..strokeWidth = 1.5,
    );
    if (fraccion <= 0) return;

    final ancho = ((size.width / 2) - 2) * fraccion;
    final rect = positivo
        ? Rect.fromLTRB(centro, 2, centro + ancho.clamp(4, size.width / 2), size.height - 2)
        : Rect.fromLTRB(centro - ancho.clamp(4, size.width / 2), 2, centro, size.height - 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()..color = positivo ? _verde : _rojo,
    );
  }

  @override
  bool shouldRepaint(_PintorBarra anterior) =>
      anterior.fraccion != fraccion ||
      anterior.positivo != positivo ||
      anterior.eje != eje;
}

/// Fila de gasto: insignia de categoría, quién pagó y tu parte.
/// Compartida entre «Gastos recientes» y la lista completa.
class FilaGasto extends StatelessWidget {
  final dynamic gasto;
  final String nombrePagador;
  final String? miMiembroId;
  final VoidCallback onTap;

  /// Mantener pulsado abre la hoja del tique (M8).
  final VoidCallback? onLongPress;

  const FilaGasto({
    super.key,
    required this.gasto,
    required this.nombrePagador,
    required this.miMiembroId,
    required this.onTap,
    this.onLongPress,
  });

  double get _miParte {
    if (miMiembroId == null) return 0;
    for (final split in (gasto['splits'] as List<dynamic>? ?? const [])) {
      if (split['group_member_id'] == miMiembroId) {
        return double.tryParse(split['computed_amount'].toString()) ?? 0;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CategoriaInsignia(
                categoria: gasto['category'],
                emoji: gasto['category_icon'],
                size: 42),
            const SizedBox(width: 13),
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
                    'Pagó $nombrePagador · ${fechaCorta(gasto['created_at'])} · ${etiquetaMetodoCorto(gasto['split_method'])}',
                    style: tema.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (gasto['receipt_image_url'] != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.receipt_long_rounded,
                size: 17,
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ],
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatearImporte(gasto['amount'], divisa: gasto['currency']),
                  style: tema.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (miMiembroId != null)
                  Text(
                    'tu parte: ${formatearImporte(_miParte).replaceAll(' €', '')}',
                    style: tema.textTheme.labelSmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de un pago entre miembros: quién pagó a quién, cuándo y cuánto.
class _FilaPago extends StatelessWidget {
  final String de;
  final String a;
  final String? fecha;
  final double importe;

  const _FilaPago({
    required this.de,
    required this.a,
    required this.fecha,
    required this.importe,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PersonaAvatar(nombre: de, size: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.arrow_right_alt_rounded,
              size: 20,
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
          PersonaAvatar(nombre: a, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$de pagó a $a',
                  style: tema.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(fechaCorta(fecha), style: tema.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatearImporte(importe),
            style: tema.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista completa de gastos del grupo («Ver todos»).
class _TodosLosGastosScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<dynamic> miembros;
  final String? miMiembroId;

  const _TodosLosGastosScreen({
    required this.groupId,
    required this.groupName,
    required this.miembros,
    required this.miMiembroId,
  });

  @override
  State<_TodosLosGastosScreen> createState() => _TodosLosGastosScreenState();
}

class _TodosLosGastosScreenState extends State<_TodosLosGastosScreen> {
  final _apiClient = ApiClient();
  late Future<List<dynamic>> _futuro;

  // filtros (M4): la API filtra en servidor, la app solo los pide
  static const _categorias = DividiTones.predefinidas;
  String? _categoria;
  DateTimeRange? _rango;

  @override
  void initState() {
    super.initState();
    _futuro = _pedirGastos();
  }

  Future<List<dynamic>> _pedirGastos() => _apiClient.getExpenses(
        widget.groupId,
        category: _categoria,
        dateFrom: _rango?.start,
        dateTo: _rango == null
            ? null
            : DateTime(_rango!.end.year, _rango!.end.month, _rango!.end.day,
                23, 59, 59),
      );

  Future<void> _refresh() async {
    final futuro = _pedirGastos();
    setState(() {
      _futuro = futuro;
    });
    await futuro;
  }

  Future<void> _elegirFechas() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 3),
      lastDate: ahora,
      initialDateRange: _rango,
      helpText: 'Filtrar por fechas',
      saveText: 'Aplicar',
    );
    if (rango == null) return;
    setState(() => _rango = rango);
    await _refresh();
  }

  String get _etiquetaRango {
    if (_rango == null) return 'Fechas';
    String dia(DateTime d) => '${d.day}/${d.month}';
    return '${dia(_rango!.start)} – ${dia(_rango!.end)}';
  }

  Widget _barraFiltros() {
    final tonos = DividiTones.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          FilterChip(
            label: Text(_etiquetaRango),
            avatar: _rango == null
                ? const Icon(Icons.calendar_month_rounded, size: 17)
                : null,
            selected: _rango != null,
            onSelected: (_) => _elegirFechas(),
            onDeleted: _rango == null
                ? null
                : () {
                    setState(() => _rango = null);
                    _refresh();
                  },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Todo'),
            selected: _categoria == null,
            onSelected: (_) {
              setState(() => _categoria = null);
              _refresh();
            },
          ),
          for (final categoria in _categorias) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(tonos.categoria(categoria).etiqueta),
              selected: _categoria == categoria,
              onSelected: (_) {
                setState(
                    () => _categoria = _categoria == categoria ? null : categoria);
                _refresh();
              },
            ),
          ],
        ],
      ),
    );
  }

  String _nombreMiembro(String? miembroId) {
    for (final m in widget.miembros) {
      if (m['id'] == miembroId) return m['display_name'] as String;
    }
    return '—';
  }

  Future<void> _editar(Map<String, dynamic> gasto) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          groupId: widget.groupId,
          members: widget.miembros,
          expense: gasto,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _tique(Map<String, dynamic> gasto) async {
    final cambio = await mostrarTiqueSheet(
      context,
      apiClient: _apiClient,
      groupId: widget.groupId,
      gasto: gasto,
    );
    if (cambio && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Gastos de ${widget.groupName}')),
      body: Column(
        children: [
          const SizedBox(height: 8),
          _barraFiltros(),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<dynamic>>(
                future: _futuro,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(children: [
                      EstadoVacio(
                        titulo: 'No se pudo cargar',
                        detalle: '${snapshot.error}',
                        onRetry: _refresh,
                      ),
                    ]);
                  }
                  final gastos = snapshot.data ?? [];
                  if (gastos.isEmpty) {
                    return ListView(children: const [
                      EstadoVacio(
                        titulo: 'Nada por aquí.',
                        detalle:
                            'Con esos filtros no aparece ningún gasto. '
                            'Prueba a quitar alguno.',
                      ),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    itemCount: gastos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final gasto = gastos[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: FilaGasto(
                            gasto: gasto,
                            nombrePagador: _nombreMiembro(gasto['paid_by_id']),
                            miMiembroId: widget.miMiembroId,
                            onTap: () => _editar(gasto as Map<String, dynamic>),
                            onLongPress: () =>
                                _tique(gasto as Map<String, dynamic>),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo de vista del detalle (solo presentación).
// ---------------------------------------------------------------------------

class _DatosGrupo {
  final Map<String, dynamic> grupo;
  final List<dynamic> balances;
  final List<dynamic> gastos;
  final List<dynamic> pagos;
  final String? userId;

  const _DatosGrupo({
    required this.grupo,
    required this.balances,
    required this.gastos,
    required this.pagos,
    required this.userId,
  });

  /// Gastos que alimentan el dónut: los del mes en curso, o todo el
  /// histórico si este mes aún no tiene ninguno.
  List<dynamic> get gastosDelDonut {
    final delMes = _gastosDelMes;
    return delMes.isNotEmpty ? delMes : gastos;
  }

  String get etiquetaDonut {
    if (_gastosDelMes.isNotEmpty) {
      final ahora = DateTime.now();
      final periodo =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';
      return mesDePeriodo(periodo).split(' de ').first;
    }
    return 'todo el histórico';
  }

  List<dynamic> get _gastosDelMes {
    final ahora = DateTime.now();
    return gastos.where((g) {
      final fecha = DateTime.tryParse(g['created_at'] ?? '')?.toLocal();
      return fecha != null &&
          fecha.year == ahora.year &&
          fecha.month == ahora.month;
    }).toList();
  }

  List<dynamic> get miembros => (grupo['members'] as List<dynamic>?) ?? const [];

  List<String> get nombresMiembros =>
      miembros.map((m) => m['display_name'] as String).toList();

  Map<String, dynamic>? get _miMiembro {
    if (userId == null) return null;
    for (final m in miembros) {
      if (m['user_id'] == userId) return m as Map<String, dynamic>;
    }
    return null;
  }

  String? get miMiembroId => _miMiembro?['id'] as String?;

  bool get soyAdmin => _miMiembro?['role'] == 'admin';

  /// Lo que queda por saldar: la suma de los balances positivos. Es 0 cuando
  /// el grupo está a cero (saldado o sin gastos) y sirve para avisar antes de
  /// borrarlo.
  double get deudaPendiente {
    var pendiente = 0.0;
    for (final b in balances) {
      final valor = double.tryParse(b['balance'].toString()) ?? 0;
      if (valor > 0) pendiente += valor;
    }
    return pendiente;
  }

  bool get estaSaldado => deudaPendiente < 0.01;

  String get subtitulo {
    final n = miembros.length;
    final cuantos = n == 1 ? '1 miembro' : '$n miembros';
    final divisa = grupo['default_currency'] ?? 'EUR';
    final rol = _miMiembro?['role'] == 'admin' ? 'eres admin' : 'eres miembro';
    return '$cuantos · $divisa · $rol';
  }

  double get balanceMaximo {
    var maximo = 0.0;
    for (final b in balances) {
      final valor = (double.tryParse(b['balance'].toString()) ?? 0).abs();
      if (valor > maximo) maximo = valor;
    }
    return maximo;
  }

  String nombreMiembro(String? miembroId) {
    for (final m in miembros) {
      if (m['id'] == miembroId) return m['display_name'] as String;
    }
    return '—';
  }
}
