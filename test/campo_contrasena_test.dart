import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dividi/widgets/campo_contrasena.dart';

void main() {
  Future<void> pumpCampo(WidgetTester tester, TextEditingController c) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CampoContrasena(controller: c, label: 'Contraseña'),
      ),
    ));
  }

  /// El TextField interno, para mirar si oculta o no lo escrito.
  TextField campo(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('La contraseña nace oculta', (tester) async {
    await pumpCampo(tester, TextEditingController());
    expect(campo(tester).obscureText, isTrue);
  });

  testWidgets('El ojo la hace visible y vuelve a ocultarla', (tester) async {
    await pumpCampo(tester, TextEditingController());

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(campo(tester).obscureText, isFalse);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(campo(tester).obscureText, isTrue);
  });

  testWidgets('Ver la contraseña no altera lo escrito', (tester) async {
    final controller = TextEditingController();
    await pumpCampo(tester, controller);

    await tester.enterText(find.byType(TextField), 'secreta123');
    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(controller.text, 'secreta123');
  });
}
