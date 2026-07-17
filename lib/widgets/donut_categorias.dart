import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';

/// Dónut de gasto por categorías (M5): responde «¿en qué se nos va?».
/// Se calcula en cliente con los gastos que ya vuelven de la API.
class DonutCategorias extends StatelessWidget {
  final List<dynamic> gastos;

  const DonutCategorias({super.key, required this.gastos});

  Map<String, double> get _totales {
    final totales = <String, double>{};
    for (final gasto in gastos) {
      final categoria = (gasto['category'] ?? 'otros') as String;
      final importe = double.tryParse(gasto['amount'].toString()) ?? 0;
      totales[categoria] = (totales[categoria] ?? 0) + importe;
    }
    return totales;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    final totales = _totales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = totales.fold(0.0, (suma, e) => suma + e.value);
    if (total <= 0) return const SizedBox.shrink();

    final colores = [
      for (final entrada in totales) tonos.categoria(entrada.key).color,
    ];

    return Row(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: CustomPaint(
            painter: _PintorDonut(
              fracciones: [for (final e in totales) e.value / total],
              colores: colores,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatearImporte(total).replaceAll(' €', ''),
                    style: TextStyle(
                      fontFamily: DividiTheme.familiaTitulares,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: tema.colorScheme.onSurface,
                    ),
                  ),
                  Text('€', style: tema.textTheme.labelSmall),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (final entrada in totales)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: tonos.categoria(entrada.key).color,
                          borderRadius: BorderRadius.circular(3.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tonos.categoria(entrada.key).etiqueta,
                          style: tema.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        formatearImporte(entrada.value).replaceAll(' €', ''),
                        style: TextStyle(
                          fontFamily: DividiTheme.familiaTitulares,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: tema.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PintorDonut extends CustomPainter {
  final List<double> fracciones;
  final List<Color> colores;

  const _PintorDonut({required this.fracciones, required this.colores});

  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width / 2, size.height / 2);
    final radio = math.min(size.width, size.height) / 2 - 7;
    final pintura = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.butt;

    // pequeño hueco entre segmentos, solo si hay más de uno
    final hueco = fracciones.length > 1 ? 0.03 : 0.0;
    var inicio = -math.pi / 2;
    for (var i = 0; i < fracciones.length; i++) {
      final barrido = math.max(fracciones[i] * 2 * math.pi - hueco, 0.02);
      pintura.color = colores[i];
      canvas.drawArc(
        Rect.fromCircle(center: centro, radius: radio),
        inicio,
        barrido,
        false,
        pintura,
      );
      inicio += fracciones[i] * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_PintorDonut anterior) =>
      anterior.fracciones != fracciones || anterior.colores != colores;
}
