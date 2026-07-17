/// Reparte lo que queda (100 - nuevoPorcentaje) entre `otros`, manteniendo sus
/// proporciones relativas. Si todos están a 0, reparte a partes iguales. El
/// último absorbe el redondeo para que el total sea 100 exacto.
///
/// Devuelve un mapa {memberId: '%'} listo para el campo `rebalance` de la API.
/// Se usa al añadir, editar o eliminar un miembro.
Map<String, String> proportionalRebalance(
    List<dynamic> otros, double nuevoPorcentaje) {
  if (otros.isEmpty) return {};
  final resto = 100 - nuevoPorcentaje;
  final pesos = otros
      .map((m) => double.tryParse('${m['default_percentage']}') ?? 0.0)
      .toList();
  final suma = pesos.fold(0.0, (a, b) => a + b);
  final rebalance = <String, String>{};
  var asignado = 0.0;
  for (var i = 0; i < otros.length; i++) {
    double value;
    if (i == otros.length - 1) {
      value = resto - asignado;
    } else {
      final fraccion = suma > 0 ? pesos[i] / suma : 1 / otros.length;
      value = double.parse((resto * fraccion).toStringAsFixed(2));
      asignado += value;
    }
    rebalance[otros[i]['id']] = value.toStringAsFixed(2);
  }
  return rebalance;
}
