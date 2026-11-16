import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../motion/regalos_page_transitions.dart';
import 'accent_palette.dart';
import 'app_typography.dart';
import 'occasion_theme.dart';
import 'regalos_shape.dart';
import 'regalos_tokens.dart';

/// Crea el `ThemeData` Material 3 de la app con el diseño «Tareas».
///
/// - [accent]: pareja pastel/tinta elegida en Ajustes (`AccentId.x.palette`).
/// - [brightness]: claro u oscuro.
/// - [occasion]: si se pasa, su acento sustituye al de Ajustes.
///
/// El `ThemeData` lleva una [RegalosTokens] en `extensions`.
ThemeData buildTheme(
  AccentPalette accent,
  Brightness brightness, {
  OccasionTheme? occasion,
}) {
  final t = RegalosTokens.resolve(
    accent: accent,
    brightness: brightness,
    occasion: occasion,
  );
  final dark = t.isDark;
  final p = occasion?.palette ?? accent;

  final scheme =
      ColorScheme.fromSeed(seedColor: p.tinta, brightness: brightness).copyWith(
        primary: t.ink,
        onPrimary: dark ? p.onFill : Colors.white,
        primaryContainer: t.fill,
        onPrimaryContainer: t.onFill,
        secondary: t.ink,
        onSecondary: dark ? p.onFill : Colors.white,
        secondaryContainer: t.fill,
        onSecondaryContainer: t.onFill,
        tertiaryContainer: t.soft,
        onTertiaryContainer: t.ink,
        surface: t.bg,
        onSurface: t.text,
        onSurfaceVariant: t.textSecondary,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: t.bg,
        surfaceContainerLow: t.surface,
        surfaceContainer: t.surface,
        surfaceContainerHigh: t.surface,
        surfaceContainerHighest: t.surface,
        outline: t.controlBorder,
        outlineVariant: t.separator,
      );

  final textTheme = t.styles.toTextTheme();
  // El estilo de los botones sustituye al del tema y no hereda la familia: se
  // la damos explícita: Inter, incluida como asset.
  const buttonFont = kAppFontFamily;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kAppFontFamily,
    textTheme: textTheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    splashFactory: InkRipple.splashFactory,
    // El pasar el ratón por filas y tarjetas lo pinta `PointerSurface` (120 ms)
    // y el foco con teclado, `FocusRingOverlay` (un filete de 2 px por
    // fuera): las manchas de Material por defecto sobrarían.
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    // Barra de desplazamiento fina, sin flechas. El pulgar usa el borde de
    // control (`outline`): el del filete (`separator`) apenas se veía en
    // oscuro (1,4:1). Al pasar el ratón se oscurece (claro) o se aclara
    // (oscuro) un tercio hacia el texto.
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith<Color>(
        (states) => states.contains(WidgetState.hovered)
            ? Color.lerp(t.outline, t.text, 0.35)!
            : t.outline,
      ),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
    ),
    // Android: la pantalla nueva llega con muelle y la de debajo se aparta.
    // iOS: la nativa, que trae el gesto de volver deslizando.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: RegalosPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: [t],
    dividerTheme: DividerThemeData(color: t.separator, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: t.styles.screenTitle,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.fill,
      foregroundColor: t.onFill,
      // En oscuro la sombra solo dibuja un aro negro: el relleno pleno basta.
      elevation: dark ? 0 : 2,
      focusElevation: dark ? 0 : 4,
      hoverElevation: dark ? 0 : 4,
      highlightElevation: dark ? 0 : 6,
      shape: const RoundedRectangleBorder(borderRadius: RegalosShape.fab),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.fill,
        foregroundColor: t.onFill,
        minimumSize: const Size(44, 48),
        shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
        textStyle: t.styles.label.copyWith(
          fontSize: 15,
          fontFamily: buttonFont,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size(44, 44),
        // Sin esto, Material 3 le da forma de píldora (se ve al pulsar).
        shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
        textStyle: t.styles.label.copyWith(fontFamily: buttonFont),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size(44, 44),
        // Sin esto, Material 3 le da forma de píldora.
        shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
        side: BorderSide(color: t.chipBorder),
        textStyle: t.styles.label.copyWith(fontFamily: buttonFont),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: t.fill,
      side: BorderSide(color: t.chipBorder),
      labelStyle: t.styles.metaStrong,
      shape: const RoundedRectangleBorder(borderRadius: RegalosShape.chip),
    ),
    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: t.styles.body.copyWith(color: t.textSecondary),
      floatingLabelStyle: t.styles.metaStrong.copyWith(color: t.ink),
      helperStyle: t.styles.meta,
      errorStyle: t.styles.meta.copyWith(color: t.danger),
      border: OutlineInputBorder(
        borderRadius: RegalosShape.field,
        borderSide: BorderSide(color: t.controlBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: RegalosShape.field,
        borderSide: BorderSide(color: t.controlBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: RegalosShape.field,
        borderSide: BorderSide(color: t.ink, width: 2),
      ),
    ),
    // La hoja es un escalón por encima del fondo y lleva un filo de 1 px
    // arriba (solo visible en oscuro; los lados y el pie quedan fuera de la
    // pantalla).
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.sheet,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.chipBorder,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.sheetEdge),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(RegalosShape.sheetRadius),
        ),
      ),
    ),
    // Los avisos flotan sobre la barra inferior, con esquinas de 8.
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: RegalosShape.card),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.sheet,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(RegalosShape.dialogRadius),
        ),
      ),
      titleTextStyle: t.styles.screenTitleSmall,
      contentTextStyle: t.styles.body,
    ),
    // El calendario es otro diálogo: 8 también (Material 3 le pone 28).
    datePickerTheme: const DatePickerThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(RegalosShape.dialogRadius),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.fill,
      height: RegalosSizes.navBarHeight,
      elevation: 0,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.text,
      minVerticalPadding: 8,
    ),
  );
}
