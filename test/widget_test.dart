import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dividi/screens/login_screen.dart';

void main() {
  testWidgets('La pantalla de login muestra los campos y el botón',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
