import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dividi/screens/register_screen.dart';

void main() {
  const noCoinciden = 'Las dos contraseñas no coinciden';

  Future<void> pumpRegistro(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
  }

  /// Los dos campos de contraseña: el tercero y el cuarto del formulario,
  /// después de Nombre y Email.
  Finder contrasena() => find.byType(TextField).at(2);
  Finder repetir() => find.byType(TextField).at(3);

  testWidgets('El registro pide repetir la contraseña', (tester) async {
    await pumpRegistro(tester);
    expect(find.text('Repite la contraseña'), findsOneWidget);
  });

  testWidgets('Avisa en cuanto la repetición no coincide', (tester) async {
    await pumpRegistro(tester);

    await tester.enterText(contrasena(), 'secreta123');
    await tester.enterText(repetir(), 'secreta124');
    await tester.pumpAndSettle();

    expect(find.text(noCoinciden), findsOneWidget);
  });

  testWidgets('No avisa mientras la repetición está vacía', (tester) async {
    await pumpRegistro(tester);

    await tester.enterText(contrasena(), 'secreta123');
    await tester.pumpAndSettle();

    expect(find.text(noCoinciden), findsNothing);
  });

  testWidgets('El aviso desaparece al corregir la repetición', (tester) async {
    await pumpRegistro(tester);

    await tester.enterText(contrasena(), 'secreta123');
    await tester.enterText(repetir(), 'secreta124');
    await tester.pumpAndSettle();
    expect(find.text(noCoinciden), findsOneWidget);

    await tester.enterText(repetir(), 'secreta123');
    await tester.pumpAndSettle();
    expect(find.text(noCoinciden), findsNothing);
  });

  testWidgets('No deja crear la cuenta si las contraseñas no coinciden',
      (tester) async {
    await pumpRegistro(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Ana');
    await tester.enterText(find.byType(TextField).at(1), 'ana@example.com');
    await tester.enterText(contrasena(), 'secreta123');
    await tester.enterText(repetir(), 'secreta124');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear mi cuenta'));
    await tester.pumpAndSettle();

    // el aviso sale en un SnackBar; sin red, no se llega a llamar a la API
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.descendant(of: find.byType(SnackBar), matching: find.text(noCoinciden)),
        findsOneWidget);
  });

  testWidgets('Exige un mínimo de 8 caracteres', (tester) async {
    await pumpRegistro(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Ana');
    await tester.enterText(find.byType(TextField).at(1), 'ana@example.com');
    await tester.enterText(contrasena(), 'corta');
    await tester.enterText(repetir(), 'corta');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear mi cuenta'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('La contraseña necesita al menos 8 caracteres'),
      ),
      findsOneWidget,
    );
  });
}
