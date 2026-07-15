import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';

/// Saldar cuentas (lámina S4 del manual): la maraña de deudas frente a los
/// pagos mínimos que sugiere el settle-up, con botón para registrar cada uno.
class SettleUpScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const SettleUpScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends State<SettleUpScreen> {
  final _apiClient = ApiClient();
  late Future<_DatosSaldar> _futuro;
  String? _registrando; // id del pago (from-to) en curso, para el spinner

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosSaldar> _cargar() async {
    final resultados = await Future.wait([
      _apiClient.getSettleUp(widget.groupId),
      _apiClient.getBalances(widget.groupId),
    ]);
    return _DatosSaldar(pagos: resultados[0], balances: resultados[1]);
  }

  Future<void> _refresh() async {
    final futuro = _cargar();
    setState(() => _futuro = futuro);
    await futuro;
  }

  Future<void> _registrar(Map<String, dynamic> pago) async {
    final de = pago['from_display_name'];
    final para = pago['to_display_name'];
    final importe = formatearImporte(pago['amount']);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar pago'),
        content: Text('$de le paga $importe a $para. ¿Lo apuntamos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final clave = '${pago['from_member_id']}-${pago['to_member_id']}';
    setState(() => _registrando = clave);
    try {
      await _apiClient.createPayment(
        groupId: widget.groupId,
        fromMemberId: pago['from_member_id'],
        toMemberId: pago['to_member_id'],
        amount: pago['amount'].toString(),
        note: 'Saldado desde la app',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pago registrado: $de → $para, $importe')),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _registrando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Saldar cuentas'),
            Text(widget.groupName, style: tema.textTheme.bodySmall),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_DatosSaldar>(
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
                ),
              ]);
            }
            final datos = snapshot.data!;
            final pagos = datos.pagos;

            if (pagos.isEmpty) {
              return ListView(children: const [
                EstadoVacio(
                  titulo: 'Todo saldado. A otra cosa. 🎉',
                  detalle: 'No hay pagos pendientes en este grupo.',
                ),
              ]);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                // cuántos pagos hacen falta
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: tonos.positivoFondo,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    pagos.length == 1
                        ? 'Con 1 solo pago el grupo queda en paz.'
                        : 'Con ${pagos.length} pagos el grupo queda en paz — el mínimo posible.',
                    style: tema.textTheme.bodyMedium?.copyWith(
                      color: tonos.positivo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // maraña → simplificado
                if (datos.nodos.length >= 2) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      child: _VizSimplificacion(datos: datos),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // pagos sugeridos
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        for (final (indice, pago) in pagos.indexed) ...[
                          if (indice > 0) const Divider(),
                          _FilaPago(
                            pago: pago,
                            registrando: _registrando ==
                                '${pago['from_member_id']}-${pago['to_member_id']}',
                            deshabilitado: _registrando != null,
                            onRegistrar: () =>
                                _registrar(pago as Map<String, dynamic>),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Sugerencias del algoritmo de settle-up: como máximo n−1 pagos.',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                Column(
                  children: [
                    Text(
                      pagos.length == 1
                          ? 'Cuando registres el pago…'
                          : 'Cuando registres los ${pagos.length} pagos…',
                      style: tema.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text('Todo saldado. A otra cosa. 🎉',
                        style: tema.textTheme.titleMedium),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fila de pago sugerido: avatar, «De → Para», importe y botón Registrar.
class _FilaPago extends StatelessWidget {
  final dynamic pago;
  final bool registrando;
  final bool deshabilitado;
  final VoidCallback onRegistrar;

  const _FilaPago({
    required this.pago,
    required this.registrando,
    required this.deshabilitado,
    required this.onRegistrar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          PersonaAvatar(nombre: pago['from_display_name'], size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: pago['from_display_name']),
                    TextSpan(
                      text: ' → ',
                      style: TextStyle(
                          color: tema.colorScheme.onSurfaceVariant),
                    ),
                    TextSpan(text: pago['to_display_name']),
                  ]),
                  style: tema.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatearImporte(pago['amount']),
                  style: TextStyle(
                    fontFamily: DividiTheme.familiaTitulares,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: tema.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(
                fontFamily: DividiTheme.familiaTitulares,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            onPressed: deshabilitado ? null : onRegistrar,
            child: registrando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Registrar'),
          ),
        ],
      ),
    );
  }
}

/// Antes/después: la maraña de deudas cruzadas frente a los pagos mínimos.
class _VizSimplificacion extends StatelessWidget {
  final _DatosSaldar datos;

  const _VizSimplificacion({required this.datos});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    final n = datos.nodos.length;
    final cruzadas = n * (n - 1);

    Widget panel({required bool simplificado, required String etiqueta}) {
      return Expanded(
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: CustomPaint(
                size: const Size(double.infinity, 96),
                painter: _PintorGrafo(
                  nodos: datos.nodos,
                  pagos: simplificado ? datos.flechas : const [],
                  simplificado: simplificado,
                  colorPersona: tonos.colorPersona,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: tema.textTheme.labelSmall,
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        panel(
          simplificado: false,
          etiqueta: 'histórico: hasta $cruzadas deudas cruzadas',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '→',
            style: TextStyle(
              fontFamily: DividiTheme.familiaTitulares,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        panel(
          simplificado: true,
          etiqueta: datos.pagos.length == 1
              ? 'con Dividi: 1 pago y en paz'
              : 'con Dividi: ${datos.pagos.length} pagos y en paz',
        ),
      ],
    );
  }
}

class _PintorGrafo extends CustomPainter {
  final List<_Nodo> nodos;
  final List<(String, String)> pagos;
  final bool simplificado;
  final Color Function(String) colorPersona;

  static const _rojo = Color(0xFFD4685D);
  static const _verde = Color(0xFF2E9E6B);
  static const _radio = 13.0;

  const _PintorGrafo({
    required this.nodos,
    required this.pagos,
    required this.simplificado,
    required this.colorPersona,
  });

  List<Offset> _posiciones(Size size) {
    final cx = size.width / 2;
    return switch (nodos.length) {
      2 => [Offset(cx - 34, 48), Offset(cx + 34, 48)],
      3 => [Offset(cx, 22), Offset(cx - 36, 74), Offset(cx + 36, 74)],
      _ => [
          Offset(cx, 16),
          Offset(cx - 40, 48),
          Offset(cx + 40, 48),
          Offset(cx, 80),
        ],
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final posiciones = _posiciones(size);
    final indicePorId = {
      for (final (i, nodo) in nodos.indexed) nodo.id: i,
    };

    if (!simplificado) {
      // la maraña: todas las parejas enredadas
      final pintura = Paint()
        ..color = _rojo.withValues(alpha: 0.5)
        ..strokeWidth = 1.6;
      for (var i = 0; i < posiciones.length; i++) {
        for (var j = i + 1; j < posiciones.length; j++) {
          canvas.drawLine(posiciones[i], posiciones[j], pintura);
        }
      }
    } else {
      // los pagos mínimos, con flecha
      final pintura = Paint()
        ..color = _verde
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      for (final (deId, paraId) in pagos) {
        final de = indicePorId[deId];
        final para = indicePorId[paraId];
        if (de == null || para == null) continue;
        final origen = posiciones[de];
        final destino = posiciones[para];
        final direccion = (destino - origen) / (destino - origen).distance;
        final inicio = origen + direccion * (_radio + 3);
        final fin = destino - direccion * (_radio + 6);
        canvas.drawLine(inicio, fin, pintura);
        // punta de flecha
        final normal = Offset(-direccion.dy, direccion.dx);
        final punta = Path()
          ..moveTo(fin.dx + direccion.dx * 6, fin.dy + direccion.dy * 6)
          ..lineTo(fin.dx + normal.dx * 4, fin.dy + normal.dy * 4)
          ..lineTo(fin.dx - normal.dx * 4, fin.dy - normal.dy * 4)
          ..close();
        canvas.drawPath(punta, Paint()..color = _verde);
      }
    }

    // nodos con inicial
    for (final (i, nodo) in nodos.indexed) {
      canvas.drawCircle(
        posiciones[i],
        _radio,
        Paint()..color = colorPersona(nodo.nombre),
      );
      final texto = TextPainter(
        text: TextSpan(
          text: nodo.nombre.isEmpty ? '?' : nodo.nombre[0].toUpperCase(),
          style: const TextStyle(
            fontFamily: DividiTheme.familiaTitulares,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      texto.paint(
        canvas,
        posiciones[i] - Offset(texto.width / 2, texto.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_PintorGrafo anterior) =>
      anterior.nodos != nodos ||
      anterior.pagos != pagos ||
      anterior.simplificado != simplificado;
}

// ---------------------------------------------------------------------------
// Modelo de vista (solo presentación).
// ---------------------------------------------------------------------------

class _Nodo {
  final String id;
  final String nombre;

  const _Nodo(this.id, this.nombre);
}

class _DatosSaldar {
  final List<dynamic> pagos;
  final List<dynamic> balances;

  const _DatosSaldar({required this.pagos, required this.balances});

  /// Miembros con saldo distinto de cero (máx. 4), para el grafo.
  List<_Nodo> get nodos {
    final lista = <_Nodo>[];
    for (final b in balances) {
      final valor = double.tryParse(b['balance'].toString()) ?? 0;
      if (valor.abs() >= 0.005) {
        lista.add(_Nodo(b['member_id'] as String, b['display_name'] as String));
      }
      if (lista.length == 4) break;
    }
    return lista;
  }

  /// Pagos como pares (de, para) entre nodos visibles del grafo.
  List<(String, String)> get flechas {
    final visibles = nodos.map((n) => n.id).toSet();
    return [
      for (final p in pagos)
        if (visibles.contains(p['from_member_id']) &&
            visibles.contains(p['to_member_id']))
          (p['from_member_id'] as String, p['to_member_id'] as String),
    ];
  }
}
