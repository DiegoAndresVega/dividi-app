/// Reglas de la casa para escribir números y etiquetas en Dividi.
///
/// Todo importe lleva dos decimales con coma, separador de miles con punto
/// y el símbolo detrás. El signo acompaña siempre a los saldos: el color
/// nunca viaja solo.
library;

/// «1234.5» → «1.234,50 €» · con [conSigno]: «+60,00 €» / «−30,00 €».
/// Divisas distintas de EUR se escriben con su código: «12,00 USD».
String formatearImporte(Object? valor, {String? divisa, bool conSigno = false}) {
  final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
  final absoluto = numero.abs();

  final fijo = absoluto.toStringAsFixed(2);
  final punto = fijo.indexOf('.');
  var entera = fijo.substring(0, punto);
  final decimales = fijo.substring(punto + 1);

  final conMiles = StringBuffer();
  for (var i = 0; i < entera.length; i++) {
    if (i > 0 && (entera.length - i) % 3 == 0) conMiles.write('.');
    conMiles.write(entera[i]);
  }

  final signo = numero < -0.004
      ? '−'
      : (conSigno && numero > 0.004 ? '+' : '');
  final simbolo =
      (divisa == null || divisa.toUpperCase() == 'EUR') ? '€' : divisa;
  return '$signo$conMiles,$decimales $simbolo';
}

/// Nombre en pantalla de cada método de división de la API.
const etiquetasMetodo = <String, String>{
  'equal': 'a partes iguales',
  'percentage': 'por porcentajes',
  'exact': 'importes exactos',
  'shares': 'por partes',
};

String etiquetaMetodo(String? metodo) => etiquetasMetodo[metodo] ?? metodo ?? '';
