import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dividi/screens/login_screen.dart';
import 'package:dividi/widgets/dividi_logo.dart';

void main() {
  testWidgets('La pantalla de login muestra el logo, los campos y el botón',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.byType(DividiLogo), findsOneWidget);
    expect(find.byType(DividiWordmark), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
