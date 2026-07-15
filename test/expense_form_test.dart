import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dividi/screens/expense_form_screen.dart';

void main() {
  final members = [
    {'id': 'a', 'display_name': 'Ana'},
    {'id': 'b', 'display_name': 'Bea'},
    {'id': 'c', 'display_name': 'Carlos'},
  ];

  Future<void> pumpForm(WidgetTester tester) async {
    // pantalla alta para que el ListView construya todos los campos
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: ExpenseFormScreen(groupId: 'g1', members: members),
    ));
    // asegurar el modo porcentajes (segmento «Ingresos», el de serie)
    await tester.tap(find.text('Ingresos'));
    await tester.pumpAndSettle();
  }

  /// Los campos de % son los TextField después de Descripción e Importe.
  List<TextField> percentFields(WidgetTester tester) =>
      tester.widgetList<TextField>(find.byType(TextField)).skip(2).toList();

  testWidgets('Al activar porcentajes se reparten solos a partes iguales',
      (tester) async {
    await pumpForm(tester);
    final fields = percentFields(tester);
    expect(fields.length, 3);
    expect(fields[0].controller!.text, '33.33');
    expect(fields[1].controller!.text, '33.33');
    expect(fields[2].controller!.text, '33.34'); // el último absorbe el resto
  });

  testWidgets('Fijar un campo reajusta los automáticos hasta sumar 100',
      (tester) async {
    await pumpForm(tester);
    // escribir 50 en el campo de Ana
    await tester.enterText(find.byType(TextField).at(2), '50');
    await tester.pumpAndSettle();

    final fields = percentFields(tester);
    expect(fields[0].controller!.text, '50');
    expect(fields[1].controller!.text, '25');
    expect(fields[2].controller!.text, '25');
  });

  testWidgets('Borrar un campo fijado lo devuelve al automático',
      (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byType(TextField).at(2), '50');
    await tester.pumpAndSettle();
    // borrar: vuelve todo al reparto igualitario
    await tester.enterText(find.byType(TextField).at(2), '');
    await tester.pumpAndSettle();

    final fields = percentFields(tester);
    expect(fields[1].controller!.text, '33.33');
    expect(fields[2].controller!.text, '33.34');
  });

  testWidgets('Desmarcar un participante reparte entre los que quedan',
      (tester) async {
    await pumpForm(tester);
    await tester.tap(find.byType(CheckboxListTile).at(2)); // fuera Carlos
    await tester.pumpAndSettle();

    final fields = percentFields(tester);
    // quedan Ana y Bea al 50/50 (el campo de Carlos desaparece)
    expect(fields.length, 2);
    expect(fields[0].controller!.text, '50');
    expect(fields[1].controller!.text, '50');
  });
}
