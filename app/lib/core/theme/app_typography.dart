import 'package:flutter/material.dart';

import 'regalos_shape.dart';

/// ÚNICO punto donde cambiar la fuente de toda la app.
///
/// Ahora es `null`: se usa la del sistema (Roboto en Android, SF en iOS).
/// Cuando llegue Inter como asset (declarado en `pubspec.yaml`), basta con
/// poner aquí `'Inter'`.
const String kAppFontFamily = 'Inter';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Estilos de texto del diseño «Tareas» (tamaños, interlineados y pesos de las
/// maquetas). Todos usan cifras tabulares y escalan con el tamaño del sistema.
@immutable
class RegalosTextStyles {
  RegalosTextStyles({required Color text, required Color secondary})
    : screenTitle = _s(24, 30, FontWeight.w700, text),
      screenTitleSmall = _s(22, 28, FontWeight.w700, text),
      sectionTitle = _s(14, 20, FontWeight.w700, text),
      rowTitle = _s(16, 22, FontWeight.w500, text),
      rowTitleCompact = _s(15, 20, FontWeight.w500, text),
      body = _s(15, 20, FontWeight.w400, text),
      label = _s(14, 20, FontWeight.w600, text),
      meta = _s(13, 18, FontWeight.w400, secondary),
      metaStrong = _s(13, 18, FontWeight.w500, text),
      caption = _s(13, 16, FontWeight.w400, secondary),
      navLabel = _s(13, 16, FontWeight.w500, secondary),
      stat = _s(20, 22, FontWeight.w700, text),
      countdownTitle = _s(15, 20, FontWeight.w600, text);

  final TextStyle screenTitle;
  final TextStyle screenTitleSmall;
  final TextStyle sectionTitle;
  final TextStyle rowTitle;
  final TextStyle rowTitleCompact;
  final TextStyle body;
  final TextStyle label;
  final TextStyle meta;
  final TextStyle metaStrong;
  final TextStyle caption;
  final TextStyle navLabel;
  final TextStyle stat;
  final TextStyle countdownTitle;

  /// Número grande de la cuenta atrás: 44, 56 o 64 px (maquetas Colores,
  /// Navidad y Cumple).
  TextStyle countdownNumber(CountdownSize size, Color color) {
    final (fontSize, height) = switch (size) {
      CountdownSize.compact => (44.0, 48.0),
      CountdownSize.medium => (56.0, 60.0),
      CountdownSize.large => (64.0, 68.0),
      CountdownSize.carousel => (RegalosSizes.countdownNumber, 64.0),
    };
    return _s(fontSize, height, FontWeight.w700, color);
  }

  /// Correspondencia con el `TextTheme` de Material.
  TextTheme toTextTheme() => TextTheme(
    headlineMedium: screenTitleSmall,
    headlineSmall: screenTitle,
    titleLarge: screenTitle,
    titleMedium: rowTitle,
    titleSmall: sectionTitle,
    bodyLarge: _s(16, 22, FontWeight.w400, body.color!),
    bodyMedium: body,
    bodySmall: meta,
    labelLarge: label,
    labelMedium: _s(13, 16, FontWeight.w500, body.color!),
    labelSmall: caption,
  );

  static TextStyle _s(
    double size,
    double lineHeight,
    FontWeight weight,
    Color color,
  ) => TextStyle(
    fontFamily: kAppFontFamily,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: color,
    fontFeatures: _tabular,
  );
}

/// Tamaños del número de la tarjeta de cuenta atrás.
/// [carousel] es el del carrusel de Personas (60 px, rediseño v3).
enum CountdownSize { compact, medium, large, carousel }
