import 'package:flutter/material.dart';

/// Sistema de diseño de Dividi — «Cuentas claras, amistades largas.»
///
/// La identidad se apoya en tres decisiones:
///  - Base neutra y cálida (Porcelana + Tinta) para leer números sin fatiga.
///  - Un único acento, Ámbar, reservado a la marca y a la acción principal.
///  - El verde y el rojo son el lenguaje semántico de los saldos
///    (te deben / debes) y no significan nada más en toda la app.
abstract final class DividiColors {
  // núcleo
  static const tinta = Color(0xFF212B36);
  static const porcelana = Color(0xFFF7F6F2);
  static const blanco = Color(0xFFFFFFFF);
  static const hueso = Color(0xFFEFEDE6);
  static const bruma = Color(0xFF5B6672);
  static const linea = Color(0xFFE3E0D8);
  static const ambar = Color(0xFFF0A32F);
  static const ambarProfundo = Color(0xFFD8890E);

  // modo noche (sesgo azul, nunca negro puro)
  static const noche = Color(0xFF141A21);
  static const pizarra = Color(0xFF1C242E);
  static const nieve = Color(0xFFECEFF1);
  static const brumaNoche = Color(0xFF9AA6B2);
  static const lineaNoche = Color(0xFF2A3441);
  static const ambarNoche = Color(0xFFF3AC42);
  static const sobreAmbarNoche = Color(0xFF1A222B);

  // saldos — claro
  static const verde = Color(0xFF1F8A56);
  static const verdeTexto = Color(0xFF17754A);
  static const verdeFondo = Color(0xFFDFF0E7);
  static const rojo = Color(0xFFC94F44);
  static const rojoTexto = Color(0xFFB03E33);
  static const rojoFondo = Color(0xFFF7E3E0);

  // saldos — noche
  static const verdeNoche = Color(0xFF2E9E6B);
  static const verdeTextoNoche = Color(0xFF4CC28E);
  static const verdeFondoNoche = Color(0xFF18332A);
  static const rojoNoche = Color(0xFFD4685D);
  static const rojoTextoNoche = Color(0xFFE9857A);
  static const rojoFondoNoche = Color(0xFF3B2421);
}

/// Estilo visual de una categoría de gasto: tinte de fondo, color pleno e icono.
class CategoriaEstilo {
  final String etiqueta;
  final Color fondo;
  final Color color;
  final IconData icono;

  const CategoriaEstilo(this.etiqueta, this.fondo, this.color, this.icono);
}

/// Tokens que dependen del brillo y no caben en [ColorScheme]:
/// saldos, categorías de gasto y la paleta de avatares de personas.
class DividiTones extends ThemeExtension<DividiTones> {
  final Color positivo;
  final Color positivoFondo;
  final Color negativo;
  final Color negativoFondo;
  final Color neutro;
  final Color neutroFondo;
  final Map<String, CategoriaEstilo> categorias;
  final List<Color> paletaPersonas;

  const DividiTones({
    required this.positivo,
    required this.positivoFondo,
    required this.negativo,
    required this.negativoFondo,
    required this.neutro,
    required this.neutroFondo,
    required this.categorias,
    required this.paletaPersonas,
  });

  static DividiTones of(BuildContext context) {
    final tema = Theme.of(context);
    return tema.extension<DividiTones>() ??
        (tema.brightness == Brightness.dark ? oscuro : claro);
  }

  /// Color estable por persona: mismo nombre, mismo color, en cualquier pantalla.
  Color colorPersona(String nombre) {
    var h = 0;
    for (final unidad in nombre.trim().toLowerCase().codeUnits) {
      h = (h * 31 + unidad) & 0x7fffffff;
    }
    return paletaPersonas[h % paletaPersonas.length];
  }

  CategoriaEstilo categoria(String? nombre) =>
      categorias[nombre] ?? categorias['otros']!;

  static const _categoriasClaro = <String, CategoriaEstilo>{
    'comida': CategoriaEstilo('Comida', Color(0xFFF6E3D7), Color(0xFFC4622F),
        Icons.restaurant_rounded),
    'transporte': CategoriaEstilo('Transporte', Color(0xFFDFE9F3),
        Color(0xFF3D6FA5), Icons.directions_bus_rounded),
    'alojamiento': CategoriaEstilo('Alojamiento', Color(0xFFEAE3F4),
        Color(0xFF7A5FA8), Icons.hotel_rounded),
    'ocio': CategoriaEstilo('Ocio', Color(0xFFF5DFEA), Color(0xFFB94F7D),
        Icons.local_activity_rounded),
    'otros': CategoriaEstilo('Otros', Color(0xFFE7E9EB), Color(0xFF5B6672),
        Icons.more_horiz_rounded),
  };

  static const _categoriasNoche = <String, CategoriaEstilo>{
    'comida': CategoriaEstilo('Comida', Color(0xFF3A2A1E), Color(0xFFE8935C),
        Icons.restaurant_rounded),
    'transporte': CategoriaEstilo('Transporte', Color(0xFF1E2C3B),
        Color(0xFF7FA9D4), Icons.directions_bus_rounded),
    'alojamiento': CategoriaEstilo('Alojamiento', Color(0xFF2C2438),
        Color(0xFFB3A0D6), Icons.hotel_rounded),
    'ocio': CategoriaEstilo('Ocio', Color(0xFF38222D), Color(0xFFD98BAE),
        Icons.local_activity_rounded),
    'otros': CategoriaEstilo('Otros', Color(0xFF242A31), Color(0xFF9AA6B2),
        Icons.more_horiz_rounded),
  };

  static const _personas = <Color>[
    Color(0xFFD8890E), // ámbar profundo
    Color(0xFF7A5FA8), // violeta
    Color(0xFF3D6FA5), // azul
    Color(0xFFB94F7D), // frambuesa
    Color(0xFF4E9C8B), // jade
    Color(0xFF8A6D3B), // bronce
  ];

  static const claro = DividiTones(
    positivo: DividiColors.verdeTexto,
    positivoFondo: DividiColors.verdeFondo,
    negativo: DividiColors.rojoTexto,
    negativoFondo: DividiColors.rojoFondo,
    neutro: DividiColors.bruma,
    neutroFondo: DividiColors.hueso,
    categorias: _categoriasClaro,
    paletaPersonas: _personas,
  );

  static const oscuro = DividiTones(
    positivo: DividiColors.verdeTextoNoche,
    positivoFondo: DividiColors.verdeFondoNoche,
    negativo: DividiColors.rojoTextoNoche,
    negativoFondo: DividiColors.rojoFondoNoche,
    neutro: DividiColors.brumaNoche,
    neutroFondo: Color(0xFF242A31),
    categorias: _categoriasNoche,
    paletaPersonas: _personas,
  );

  @override
  DividiTones copyWith() => this;

  @override
  DividiTones lerp(DividiTones? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Los dos temas de Dividi. El modo noche no invierte: se redefine token a token.
abstract final class DividiTheme {
  static const familiaTitulares = 'Gabarito';
  static const familiaCuerpo = 'HankenGrotesk';

  static ThemeData claro() => _construir(Brightness.light);

  static ThemeData oscuro() => _construir(Brightness.dark);

  static ThemeData _construir(Brightness brillo) {
    final esNoche = brillo == Brightness.dark;

    final fondo = esNoche ? DividiColors.noche : DividiColors.porcelana;
    final superficie = esNoche ? DividiColors.pizarra : DividiColors.blanco;
    final tinta = esNoche ? DividiColors.nieve : DividiColors.tinta;
    final bruma = esNoche ? DividiColors.brumaNoche : DividiColors.bruma;
    final linea = esNoche ? DividiColors.lineaNoche : DividiColors.linea;
    final ambar = esNoche ? DividiColors.ambarNoche : DividiColors.ambar;
    final sobreAmbar =
        esNoche ? DividiColors.sobreAmbarNoche : DividiColors.tinta;
    final tonos = esNoche ? DividiTones.oscuro : DividiTones.claro;

    final esquema = ColorScheme(
      brightness: brillo,
      primary: ambar,
      onPrimary: sobreAmbar,
      primaryContainer: ambar,
      onPrimaryContainer: sobreAmbar,
      secondary: tinta,
      onSecondary: fondo,
      secondaryContainer: tonos.neutroFondo,
      onSecondaryContainer: tinta,
      tertiary: bruma,
      onTertiary: fondo,
      error: esNoche ? DividiColors.rojoTextoNoche : DividiColors.rojoTexto,
      onError: esNoche ? DividiColors.noche : DividiColors.blanco,
      surface: superficie,
      onSurface: tinta,
      onSurfaceVariant: bruma,
      surfaceContainerHighest: tonos.neutroFondo,
      surfaceContainerLow: superficie,
      outline: linea,
      outlineVariant: linea,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: esNoche ? DividiColors.porcelana : DividiColors.tinta,
      onInverseSurface: esNoche ? DividiColors.tinta : DividiColors.porcelana,
      inversePrimary: DividiColors.ambarProfundo,
      surfaceTint: Colors.transparent,
    );

    final textos = _textos(tinta: tinta, bruma: bruma);

    return ThemeData(
      useMaterial3: true,
      brightness: brillo,
      colorScheme: esquema,
      scaffoldBackgroundColor: fondo,
      fontFamily: familiaCuerpo,
      textTheme: textos,
      splashFactory: InkSparkle.splashFactory,
      extensions: [tonos],

      appBarTheme: AppBarTheme(
        backgroundColor: fondo,
        foregroundColor: tinta,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: familiaTitulares,
          fontWeight: FontWeight.w800,
          fontSize: 22,
          letterSpacing: -0.2,
          color: tinta,
        ),
        iconTheme: IconThemeData(color: tinta, size: 24),
        actionsIconTheme: IconThemeData(color: bruma, size: 24),
      ),

      cardTheme: CardThemeData(
        color: superficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: linea),
        ),
      ),

      // La acción principal: Ámbar, grande (56 px) y única por pantalla.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ambar,
          foregroundColor: sobreAmbar,
          disabledBackgroundColor: linea,
          disabledForegroundColor: bruma,
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: familiaTitulares,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tinta,
          side: BorderSide(color: tinta, width: 2),
          minimumSize: const Size(64, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: familiaTitulares,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tinta,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: familiaCuerpo,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ambar,
        foregroundColor: sobreAmbar,
        elevation: 3,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        extendedTextStyle: const TextStyle(
          fontFamily: familiaTitulares,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
        sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
        extendedSizeConstraints: const BoxConstraints.tightFor(height: 56),
      ),

      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: superficie,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: linea),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: linea),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: ambar, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: esquema.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: esquema.error, width: 2),
        ),
        labelStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w500,
          color: bruma,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w700,
          color: tinta,
        ),
        helperStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontSize: 12,
          color: bruma,
        ),
        suffixIconColor: bruma,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((estados) =>
              estados.contains(WidgetState.selected) ? tinta : superficie),
          foregroundColor: WidgetStateProperty.resolveWith((estados) =>
              estados.contains(WidgetState.selected) ? fondo : bruma),
          side: WidgetStatePropertyAll(BorderSide(color: linea)),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          )),
          textStyle: const WidgetStatePropertyAll(TextStyle(
            fontFamily: familiaTitulares,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          )),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: superficie,
        selectedColor: ambar,
        checkmarkColor: sobreAmbar,
        side: BorderSide(color: linea),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        labelStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
          color: tinta,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected)
                ? tinta
                : Colors.transparent),
        checkColor: WidgetStatePropertyAll(fondo),
        side: BorderSide(color: bruma, width: 1.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: tinta,
        unselectedLabelColor: bruma,
        indicatorColor: ambar,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: linea,
        labelStyle: const TextStyle(
          fontFamily: familiaTitulares,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: familiaTitulares,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: superficie,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: TextStyle(
          fontFamily: familiaTitulares,
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: tinta,
        ),
        contentTextStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w500,
          fontSize: 15,
          height: 1.5,
          color: bruma,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            esNoche ? DividiColors.porcelana : DividiColors.tinta,
        contentTextStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
          color: esNoche ? DividiColors.tinta : DividiColors.porcelana,
        ),
        actionTextColor: ambar,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dividerTheme: DividerThemeData(color: linea, thickness: 1, space: 1),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: ambar),

      listTileTheme: ListTileThemeData(
        iconColor: bruma,
        textColor: tinta,
        titleTextStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w600,
          fontSize: 15.5,
          color: tinta,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: bruma,
        ),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(
          fontFamily: familiaCuerpo,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: tinta,
        ),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ambar,
        selectionColor: ambar.withValues(alpha: 0.35),
        selectionHandleColor: ambar,
      ),

      // Barra de navegación inferior (Grupos · Actividad · Perfil):
      // icono activo en Ámbar, sin píldora — como marca la identidad.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: superficie,
        elevation: 0,
        height: 68,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith((estados) => IconThemeData(
              size: 26,
              color: estados.contains(WidgetState.selected)
                  ? (esNoche ? ambar : DividiColors.ambarProfundo)
                  : bruma,
            )),
        labelTextStyle:
            WidgetStateProperty.resolveWith((estados) => TextStyle(
                  fontFamily: familiaCuerpo,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: estados.contains(WidgetState.selected) ? tinta : bruma,
                )),
      ),
    );
  }

  static TextTheme _textos({required Color tinta, required Color bruma}) {
    TextStyle titular(double talla, FontWeight peso,
            {double espaciado = 0}) =>
        TextStyle(
          fontFamily: familiaTitulares,
          fontSize: talla,
          fontWeight: peso,
          letterSpacing: espaciado,
          color: tinta,
        );
    TextStyle cuerpo(double talla, FontWeight peso, Color color,
            {double alto = 1.5}) =>
        TextStyle(
          fontFamily: familiaCuerpo,
          fontSize: talla,
          fontWeight: peso,
          height: alto,
          color: color,
        );

    return TextTheme(
      // cifras protagonistas ("cifra héroe" de la identidad)
      displayLarge: titular(44, FontWeight.w800, espaciado: -0.8),
      displayMedium: titular(34, FontWeight.w800, espaciado: -0.5),
      displaySmall: titular(28, FontWeight.w800, espaciado: -0.3),
      headlineMedium: titular(24, FontWeight.w800, espaciado: -0.2),
      headlineSmall: titular(22, FontWeight.w800),
      titleLarge: titular(19, FontWeight.w700),
      titleMedium: titular(16.5, FontWeight.w700),
      titleSmall: titular(14.5, FontWeight.w700),
      bodyLarge: cuerpo(16, FontWeight.w500, tinta),
      bodyMedium: cuerpo(14.5, FontWeight.w500, tinta),
      bodySmall: cuerpo(12.5, FontWeight.w500, bruma, alto: 1.4),
      labelLarge: titular(16.5, FontWeight.w700),
      labelMedium: TextStyle(
        fontFamily: familiaCuerpo,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: bruma,
      ),
      labelSmall: cuerpo(11, FontWeight.w600, bruma, alto: 1.3),
    );
  }
}
