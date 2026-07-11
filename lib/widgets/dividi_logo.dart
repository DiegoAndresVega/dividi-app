import 'package:flutter/material.dart';

import '../theme/dividi_theme.dart';

/// El símbolo de Dividi es el óbelo (÷): dos personas y la barra de
/// equilibrio entre ellas. Plano, sin degradados ni sombras, con el punto
/// superior encendido en Ámbar. Dibujado con widgets: vectorial y sin assets.

/// Óbelo suelto, para fondos claros u oscuros ([color] = tinta del trazo).
class DividiMark extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? puntoSuperior;

  const DividiMark({super.key, this.size = 64, this.color, this.puntoSuperior});

  @override
  Widget build(BuildContext context) {
    final trazo = color ?? Theme.of(context).colorScheme.onSurface;
    final acento = puntoSuperior ?? DividiColors.ambar;
    final punto = size * 0.225;
    final hueco = size * 0.145;

    Widget circulo(Color c) => Container(
          width: punto,
          height: punto,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );

    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          circulo(acento),
          SizedBox(height: hueco),
          Container(
            width: size * 0.82,
            height: size * 0.15,
            decoration: BoxDecoration(
              color: trazo,
              borderRadius: BorderRadius.circular(size),
            ),
          ),
          SizedBox(height: hueco),
          circulo(trazo),
        ],
      ),
    );
  }
}

/// Logotipo en baldosa: cuadrado redondeado Ámbar con el óbelo en Tinta.
/// Es la misma pieza que el icono de la app.
class DividiLogo extends StatelessWidget {
  final double size;

  const DividiLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: DividiColors.ambar,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Center(
        child: DividiMark(
          size: size * 0.54,
          color: DividiColors.tinta,
          puntoSuperior: DividiColors.tinta,
        ),
      ),
    );
  }
}

/// Wordmark «dividi»: Gabarito ExtraBold en caja baja, con la i central
/// en Ámbar — la parte que te toca.
class DividiWordmark extends StatelessWidget {
  final double size;

  const DividiWordmark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final tinta = Theme.of(context).colorScheme.onSurface;
    final estilo = TextStyle(
      fontFamily: DividiTheme.familiaTitulares,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1,
      letterSpacing: size * -0.035,
      color: tinta,
    );
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'div'),
        TextSpan(text: 'i', style: TextStyle(color: DividiColors.ambar)),
        const TextSpan(text: 'di'),
      ]),
      style: estilo,
      semanticsLabel: 'dividi',
    );
  }
}
