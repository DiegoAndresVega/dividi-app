import 'package:flutter/material.dart';

import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import 'dividi_logo.dart';

/// Piezas pequeñas y compartidas de la interfaz de Dividi:
/// avatares de personas, chips de saldo, insignias de categoría,
/// etiquetas de sección y estados vacíos.

/// Avatar circular con inicial; color estable por nombre en toda la app.
class PersonaAvatar extends StatelessWidget {
  final String nombre;
  final double size;

  const PersonaAvatar({super.key, required this.nombre, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final color = DividiTones.of(context).colorPersona(nombre);
    final inicial = nombre.trim().isEmpty ? '?' : nombre.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        inicial,
        style: TextStyle(
          fontFamily: DividiTheme.familiaTitulares,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// Pila de avatares solapados, como en las tarjetas de grupo del manual.
/// Si hay más de [maximo], el último hueco muestra «+n».
class PilaAvatares extends StatelessWidget {
  final List<String> nombres;
  final double size;
  final int maximo;

  const PilaAvatares({
    super.key,
    required this.nombres,
    this.size = 30,
    this.maximo = 4,
  });

  @override
  Widget build(BuildContext context) {
    final desbordan = nombres.length > maximo;
    final visibles = desbordan ? maximo - 1 : nombres.length;
    final huecos = visibles + (desbordan ? 1 : 0);
    if (huecos == 0) return SizedBox(height: size + 4);

    final paso = size * 0.72;
    final borde = Theme.of(context).colorScheme.surface;
    final tonos = DividiTones.of(context);

    Widget conBorde(Widget hijo) => Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: borde, shape: BoxShape.circle),
          child: hijo,
        );

    return SizedBox(
      width: (huecos - 1) * paso + size + 4,
      height: size + 4,
      child: Stack(
        children: [
          for (var i = 0; i < visibles; i++)
            Positioned(
              left: i * paso,
              child: conBorde(PersonaAvatar(nombre: nombres[i], size: size)),
            ),
          if (desbordan)
            Positioned(
              left: visibles * paso,
              child: conBorde(Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: tonos.neutroFondo,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '+${nombres.length - visibles}',
                  style: TextStyle(
                    fontFamily: DividiTheme.familiaTitulares,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.36,
                    color: tonos.neutro,
                  ),
                ),
              )),
            ),
        ],
      ),
    );
  }
}

/// Chip de saldo: verde si te deben, rojo si debes, neutro «En paz».
/// El signo acompaña siempre al número; el color solo refuerza.
class SaldoChip extends StatelessWidget {
  final double importe;
  final String? divisa;

  const SaldoChip({super.key, required this.importe, this.divisa});

  @override
  Widget build(BuildContext context) {
    final tonos = DividiTones.of(context);
    final saldado = importe.abs() < 0.005;

    final Color fondo;
    final Color color;
    final String texto;
    if (saldado) {
      fondo = tonos.neutroFondo;
      color = tonos.neutro;
      texto = 'En paz';
    } else if (importe > 0) {
      fondo = tonos.positivoFondo;
      color = tonos.positivo;
      texto = formatearImporte(importe, divisa: divisa, conSigno: true);
    } else {
      fondo = tonos.negativoFondo;
      color = tonos.negativo;
      texto = formatearImporte(importe, divisa: divisa, conSigno: true);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: DividiTheme.familiaTitulares,
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Insignia cuadrada redondeada con el icono de la categoría del gasto.
class CategoriaInsignia extends StatelessWidget {
  final String? categoria;
  final double size;

  const CategoriaInsignia({super.key, required this.categoria, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final estilo = DividiTones.of(context).categoria(categoria);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: estilo.fondo,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(estilo.icono, size: size * 0.5, color: estilo.color),
    );
  }
}

/// Etiqueta de sección en mayúsculas — «BALANCES DEL GRUPO».
class EtiquetaSeccion extends StatelessWidget {
  final String texto;

  const EtiquetaSeccion(this.texto, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium,
    );
  }
}

/// Estado vacío o de error: el óbelo en reposo y un mensaje claro.
/// Pensado para ir dentro de un ListView (compatible con pull-to-refresh).
class EstadoVacio extends StatelessWidget {
  final String titulo;
  final String? detalle;

  /// Si se indica, muestra un botón «Reintentar» bajo el mensaje.
  final VoidCallback? onRetry;

  const EstadoVacio({
    super.key,
    required this.titulo,
    this.detalle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 96, 40, 40),
      child: Column(
        children: [
          Opacity(
            opacity: 0.35,
            child: DividiMark(
              size: 44,
              color: tema.colorScheme.onSurfaceVariant,
              puntoSuperior: tema.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: tema.textTheme.titleMedium,
          ),
          if (detalle != null) ...[
            const SizedBox(height: 8),
            Text(
              detalle!,
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Reintentar'),
            ),
          ],
        ],
      ),
    );
  }
}
