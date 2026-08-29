import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dividi/theme/dividi_format.dart';
import 'package:dividi/widgets/saldar_dialog.dart';

void main() {
  late String? resultado;
  late bool cerrado;

  /// Abre el diálogo sobre una pantalla mínima y guarda lo que devuelve.
  Future<void> abrirDialogo(WidgetTester tester,
      {double pendiente = 35}) async {
    resultado = null;
    cerrado = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              resultado = await mostrarDialogoSaldar(
                context,
                de: 'Ana',
                para: 'Bea',
                pendiente: pendiente,
              );
              cerrado = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> elegirParte(WidgetTester tester) async {
    await tester.tap(find.text('Saldar parte'));
    await tester.pumpAndSettle();
  }

  Future<void> pulsarRegistrar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar'));
    await tester.pumpAndSettle();
  }

  testWidgets('De serie salda la deuda entera', (tester) async {
    // Arrange
    await abrirDialogo(tester);

    // Act
    await pulsarRegistrar(tester);

    // Assert
    expect(resultado, '35.00');
  });

  testWidgets('«Saldar parte» devuelve solo el importe escrito',
      (tester) async {
    // Arrange
    await abrirDialogo(tester);
    await elegirParte(tester);

    // Act
    await tester.enterText(find.byType(TextField), '30');
    await pulsarRegistrar(tester);

    // Assert
    expect(resultado, '30.00');
  });

  testWidgets('La coma decimal vale como separador', (tester) async {
    // Arrange
    await abrirDialogo(tester);
    await elegirParte(tester);

    // Act
    await tester.enterText(find.byType(TextField), '12,5');
    await pulsarRegistrar(tester);

    // Assert
    expect(resultado, '12.50');
  });

  testWidgets('Pagar más de lo pendiente no cierra el diálogo',
      (tester) async {
    // Arrange
    await abrirDialogo(tester);
    await elegirParte(tester);

    // Act
    await tester.enterText(find.byType(TextField), '40');
    await pulsarRegistrar(tester);

    // Assert · el importe se escribe con las reglas de la casa (espacio duro)
    expect(find.text('Como mucho ${formatearImporte(35)}'), findsOneWidget);
    expect(cerrado, isFalse);
  });

  testWidgets('Sin importe válido avisa en vez de registrar', (tester) async {
    // Arrange
    await abrirDialogo(tester);
    await elegirParte(tester);

    // Act
    await tester.enterText(find.byType(TextField), '0');
    await pulsarRegistrar(tester);

    // Assert
    expect(find.text('Escribe un importe mayor que 0'), findsOneWidget);
    expect(cerrado, isFalse);
  });
}
