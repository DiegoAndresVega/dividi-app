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
/// El método `percentage` se presenta como «según ingresos»: es la seña de
/// identidad de Dividi — cada uno aporta su peso en el hogar.
const etiquetasMetodo = <String, String>{
  'equal': 'a partes iguales',
  'percentage': 'según ingresos',
  'exact': 'importes exactos',
  'shares': 'por partes',
};

String etiquetaMetodo(String? metodo) => etiquetasMetodo[metodo] ?? metodo ?? '';

/// Versión corta para las líneas secundarias de las listas: «· iguales».
const etiquetasMetodoCorto = <String, String>{
  'equal': 'iguales',
  'percentage': 'según ingresos',
  'exact': 'exacto',
  'shares': 'por partes',
};

String etiquetaMetodoCorto(String? metodo) =>
    etiquetasMetodoCorto[metodo] ?? metodo ?? '';

/// «50.00» → «50 %» · «33.33» → «33,33 %».
String formatearPorcentaje(Object? valor) {
  final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
  final texto = numero.toStringAsFixed(2);
  final limpio = texto.endsWith('.00')
      ? numero.toStringAsFixed(0)
      : texto.replaceAll('.', ',');
  return '$limpio %';
}

// ---------------------------------------------------------------------------
// Fechas en español, sin dependencias.
// ---------------------------------------------------------------------------

const _dias = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _mesesCortos = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// «viernes, 10 de julio» — para el saludo de la pantalla de inicio.
String saludoFecha(DateTime fecha) =>
    '${_dias[fecha.weekday - 1]}, ${fecha.day} de ${_meses[fecha.month - 1]}';

/// «2026-07» → «julio de 2026» — para los planes de ahorro.
String mesDePeriodo(String? periodo) {
  final partes = (periodo ?? '').split('-');
  if (partes.length != 2) return periodo ?? '';
  final mes = int.tryParse(partes[1]);
  if (mes == null || mes < 1 || mes > 12) return periodo!;
  return '${_meses[mes - 1]} de ${partes[0]}';
}

/// «hoy», «ayer» o «8 mar» — para las líneas secundarias de las listas.
String fechaCorta(String? iso) {
  final fecha = DateTime.tryParse(iso ?? '')?.toLocal();
  if (fecha == null) return '';
  final ahora = DateTime.now();
  final dias = DateTime(ahora.year, ahora.month, ahora.day)
      .difference(DateTime(fecha.year, fecha.month, fecha.day))
      .inDays;
  if (dias == 0) return 'hoy';
  if (dias == 1) return 'ayer';
  return '${fecha.day} ${_mesesCortos[fecha.month - 1]}';
}

// ---------------------------------------------------------------------------
// Previsualización del reparto — espejo en cliente del split_calculator del
// backend, SOLO para mostrar en vivo lo que paga cada uno mientras se rellena
// el formulario. El importe definitivo lo calcula siempre la API.
// ---------------------------------------------------------------------------

double _redondear2(double valor) => (valor * 100).roundToDouble() / 100;

/// Devuelve el importe que corresponde a cada participante, en el mismo orden
/// que [entradas]. Regla de la casa: cada parte se redondea a 2 decimales y
/// el último participante absorbe la diferencia para que la suma sea exacta.
///
/// - equal: [entradas] se ignora (solo cuenta cuántos son).
/// - percentage: [entradas] son porcentajes; solo cuadra el total si suman 100.
/// - exact: [entradas] son importes y se muestran tal cual.
/// - shares: [entradas] son partes (enteros).
List<double> previsualizarReparto({
  required String metodo,
  required double total,
  required List<double> entradas,
}) {
  final n = entradas.length;
  if (n == 0 || total <= 0) return const [];

  switch (metodo) {
    case 'equal':
      final parte = _redondear2(total / n);
      final partes = List.filled(n, parte);
      partes[n - 1] = _redondear2(total - parte * (n - 1));
      return partes;
    case 'percentage':
      final partes =
          entradas.map((p) => _redondear2(total * p / 100)).toList();
      final sumaPct = entradas.fold(0.0, (a, b) => a + b);
      if ((sumaPct - 100).abs() < 0.01) {
        final resto = partes.take(n - 1).fold(0.0, (a, b) => a + b);
        partes[n - 1] = _redondear2(total - resto);
      }
      return partes;
    case 'exact':
      return entradas.map(_redondear2).toList();
    case 'shares':
      final sumaPartes = entradas.fold(0.0, (a, b) => a + b);
      if (sumaPartes <= 0) return List.filled(n, 0);
      final partes = entradas
          .map((s) => _redondear2(total * s / sumaPartes))
          .toList();
      final resto = partes.take(n - 1).fold(0.0, (a, b) => a + b);
      partes[n - 1] = _redondear2(total - resto);
      return partes;
    default:
      return List.filled(n, 0);
  }
}
