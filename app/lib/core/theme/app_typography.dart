import 'package:flutter/material.dart';

import 'regalos_shape.dart';

/// ÚNICO punto donde cambiar la fuente de toda la app.
///
/// Ahora es `null`: se usa la del sistema (Roboto en Android, SF en iOS).
/// Cuando llegue Inter como asset (declarado en `pubspec.yaml`), basta con
/// poner aquí `'Inter'`.
const String kAppFontFamily = 'Inter';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Estilos de texto del diseño «A + Actual» (tamaños, interlineados y pesos de
/// la ficha). Todos usan cifras tabulares y escalan con el tamaño del sistema;
/// los títulos grandes se aprietan un 2 %.
@immutable
class RegalosTextStyles {
  RegalosTextStyles({required Color text, required Color secondary})
    : boardTitle = _s(32, 38, FontWeight.w700, text, tight: 0.02),
      screenTitle = _s(28, 34, FontWeight.w700, text, tight: 0.02),
      screenTitleSmall = _s(20, 26, FontWeight.w600, text, tight: 0.01),
      sectionTitle = _s(15, 20, FontWeight.w600, text),
      rowTitle = _s(16, 22, FontWeight.w500, text),
      rowTitleCompact = _s(15, 20, FontWeight.w500, text),
      body = _s(15, 20, FontWeight.w400, text),
      label = _s(14, 20, FontWeight.w600, text),
      meta = _s(13, 18, FontWeight.w400, secondary),
      metaStrong = _s(13, 18, FontWeight.w500, text),
      caption = _s(12, 16, FontWeight.w500, secondary),
      navLabel = _s(13, 16, FontWeight.w500, secondary),
      stat = _s(20, 22, FontWeight.w700, text),
      statLarge = _s(24, 28, FontWeight.w700, text),
      amount = _s(15, 20, FontWeight.w700, text),
      status = _s(13, 18, FontWeight.w600, text),
      countdownTitle = _s(15, 20, FontWeight.w600, text),
      price = _s(14, 20, FontWeight.w500, text),
      tableTitle = _s(14, 20, FontWeight.w500, text),
      boardSubtitle = _s(14, 20, FontWeight.w400, secondary),
      cardTitle = _s(13, 18, FontWeight.w500, text),
      fieldText = _s(16, 22, FontWeight.w400, text);

  /// El título de una pantalla del tablero de la web («Hoy»): 32/38.
  final TextStyle boardTitle;

  /// El título de una pantalla del móvil («Personas», «Leo»): 28/34.
  final TextStyle screenTitle;

  /// El título de una hoja o un diálogo («Editar regalo»): 20/26.
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

  /// La cifra grande del resumen del presupuesto (presupuesto, gastado y lo que
  /// queda) en la app y en la web: 24/28.
  final TextStyle statLarge;

  /// El importe gastado de una tarjeta o fila del presupuesto: 15/20.
  final TextStyle amount;

  /// El estado de un presupuesto («Queda 120 €», «Te pasas 40 €», «Si compras
  /// lo que falta…»): 13/18. Para avisar solo cambia el color.
  final TextStyle status;
  final TextStyle countdownTitle;

  /// El importe de un regalo (lista, tabla y tarjeta de carril); lo
  /// «previsto» va debajo con [caption].
  final TextStyle price;

  /// El nombre del regalo en la tabla de la web: 14/20.
  final TextStyle tableTitle;

  /// La línea de debajo del título del tablero («jueves, 19 de noviembre…»).
  final TextStyle boardSubtitle;

  /// El título de una tarjeta de carril: 13/18.
  final TextStyle cardTitle;

  /// El texto de un campo de búsqueda del móvil: 16/22.
  final TextStyle fieldText;

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
    Color color, {
    double tight = 0,
  }) => TextStyle(
    fontFamily: kAppFontFamily,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: color,
    letterSpacing: tight == 0 ? null : -tight * size,
    fontFeatures: _tabular,
  );
}

/// Tamaños del número de la tarjeta de cuenta atrás.
/// [carousel] es el del carrusel de Personas (60 px, rediseño v3).
enum CountdownSize { compact, medium, large, carousel }
