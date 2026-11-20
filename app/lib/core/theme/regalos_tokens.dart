import 'package:flutter/material.dart';

import 'accent_palette.dart';
import 'app_typography.dart';
import 'gift_status.dart';
import 'neutral_palette.dart';
import 'occasion_theme.dart';

/// Tokens del diseño «Tareas» que Material no cubre, ya resueltos para el
/// brillo (claro u oscuro) y, si lo hay, para el tema de ocasión.
///
/// Se leen con `RegalosTokens.of(context)`.
@immutable
class RegalosTokens extends ThemeExtension<RegalosTokens> {
  const RegalosTokens._({
    required this.accent,
    required this.brightness,
    required this.occasion,
    required this.neutral,
    required this.fill,
    required this.onFill,
    required this.ink,
    required this.soft,
    required this.swatchBorder,
    required this.selection,
    required this.selectionBorder,
    required this.selectionEdge,
    required this.cardBorder,
    required this.givers,
    required this.giverOns,
    required this.styles,
  });

  /// Calcula todos los tokens a partir del acento, el brillo y la ocasión.
  /// Con [occasion] el acento de la ocasión sustituye a [accent].
  factory RegalosTokens.resolve({
    required AccentPalette accent,
    required Brightness brightness,
    OccasionTheme? occasion,
  }) {
    final dark = brightness == Brightness.dark;
    final p = occasion?.palette ?? accent;
    final n = dark ? NeutralPalette.dark : NeutralPalette.light;
    return RegalosTokens._(
      accent: accent,
      brightness: brightness,
      occasion: occasion,
      neutral: n,
      fill: dark ? p.pastelD : p.pastel,
      onFill: dark ? p.onFill : p.tinta,
      ink: dark ? p.tintaD : p.tinta,
      soft: dark ? p.tintD : p.pastel,
      swatchBorder: p.swatchBorder,
      selection: dark ? p.selectionD : p.selection,
      selectionBorder: dark ? p.borderD : p.swatchBorder,
      selectionEdge: Color.lerp(
        dark ? p.borderD : p.swatchBorder,
        dark ? p.tintaD : p.tinta,
        0.7,
      )!,
      cardBorder: occasion == null
          ? null
          : (dark ? occasion.cardBorderD : occasion.cardBorder),
      givers: [for (final g in giverColors) dark ? g.$2 : g.$1],
      giverOns: [for (final g in giverOnColors) dark ? g.$2 : g.$1],
      styles: RegalosTextStyles(text: n.text, secondary: n.textSecondary),
    );
  }

  /// Acento de Ajustes (sin tener en cuenta la ocasión).
  final AccentPalette accent;
  final Brightness brightness;

  /// Tema de ocasión activo, o `null`.
  final OccasionTheme? occasion;
  final NeutralPalette neutral;

  /// Relleno del acento: «Añadir regalo», «Guardar», segmento activo. En
  /// oscuro, el pastel velado al 18 %.
  final Color fill;

  /// Texto e iconos sobre [fill].
  final Color onFill;

  /// Acento como texto o trazo sobre el fondo: números, casilla, progreso.
  final Color ink;

  /// Fondo suave del acento: tarjeta de cuenta atrás, pista del interruptor.
  final Color soft;

  /// Borde de las muestras de color (solo se pinta en claro).
  final Color swatchBorder;

  /// Fondo de lo elegido: el filtro activo, el destino de la barra lateral, la
  /// opción de un desplegable. El texto encima va en [ink].
  final Color selection;

  /// Borde de lo elegido (un filtro activo).
  final Color selectionBorder;

  /// Borde de lo elegido cuando se reconoce también por él (la opción activa
  /// de un conmutador sin texto): el de [selectionBorder] acercado a la tinta,
  /// a 3:1 o más sobre el fondo, la tarjeta y la hoja, en claro y en oscuro.
  final Color selectionEdge;

  /// Borde de la tarjeta de cuenta atrás; `null` fuera de una ocasión.
  final Color? cardBorder;

  /// Colores de quien regala, ya para este brillo.
  final List<Color> givers;

  /// Texto sobre cada color de [givers] (chip elegido, visto).
  final List<Color> giverOns;
  final RegalosTextStyles styles;

  bool get isDark => brightness == Brightness.dark;

  Color get bg => neutral.bg;
  Color get surface => neutral.surface;

  /// Relleno de una tarjeta de lista (la de persona): en claro, el fondo con
  /// su filete; en oscuro, el escalón de [surface], más claro que el fondo.
  Color get cardFill => isDark ? neutral.surface : neutral.bg;

  /// Hoja, tarjeta que sube y diálogo (en claro, igual que [bg]).
  Color get sheet => neutral.sheet;

  /// Filo de 1 px de arriba de la hoja; transparente en claro.
  Color get sheetEdge => neutral.sheetEdge;

  /// Velo bajo las hojas.
  Color get scrim => neutral.scrim;

  /// Sombra de las hojas.
  Color get shadow => neutral.shadow;

  /// Rojo de error o de acción destructiva, y su fondo suave.
  Color get danger => neutral.danger;
  Color get dangerOnTint => neutral.dangerOnTint;
  Color get dangerSoft => neutral.dangerSoft;
  Color get dangerRow => neutral.dangerRow;
  Color get text => neutral.text;
  Color get textSecondary => neutral.textSecondary;
  Color get textOnSoft => neutral.textOnSoft;
  Color get separator => neutral.separator;
  Color get outline => neutral.outline;
  Color get controlBorder => neutral.controlBorder;

  /// Borde de chips, filtros, casillas y celdas «por comprar»: el de control
  /// (3:1 como mínimo sobre el fondo y la hoja, en claro y en oscuro).
  Color get chipBorder => neutral.controlBorder;
  Color get track => neutral.track;

  /// Barra lateral del tablero, campos de texto y desplegables.
  Color get sidebar => neutral.sidebar;
  Color get field => neutral.field;
  Color get popover => neutral.popover;
  Color get ideaStroke => neutral.idea;

  /// Adorno principal, secundario y filete de la cabecera de la ocasión.
  Color? get ornament => occasion == null
      ? null
      : (isDark ? occasion!.ornamentD : occasion!.ornament);
  Color? get ornamentAlt => occasion == null
      ? null
      : (isDark ? occasion!.ornamentAltD : occasion!.ornamentAlt);
  Color? get ornamentLine => occasion == null
      ? null
      : (isDark ? occasion!.ornamentLineD : occasion!.ornamentLine);

  /// Trazo de la casilla de estado.
  Color statusStroke(GiftStatus status) =>
      status == GiftStatus.idea ? ideaStroke : ink;

  /// Relleno de la casilla de estado (el sector que avanza y el círculo de
  /// entregado): la tinta del acento, que se lee igual en claro y en oscuro.
  Color statusFill(GiftStatus status) => ink;

  /// Color de quien regala; el índice se repite si hay más de seis.
  Color giver(int index) => givers[index % givers.length];

  /// Texto sobre [giver] (chip elegido): en oscuro, tinta oscura de su tono.
  Color giverOn(int index) => giverOns[index % giverOns.length];

  static RegalosTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<RegalosTokens>();
    assert(
      tokens != null,
      'Falta RegalosTokens: usa buildTheme() para crear el tema.',
    );
    return tokens ??
        RegalosTokens.resolve(
          accent: AccentId.defaultAccent.palette,
          brightness: Theme.of(context).brightness,
        );
  }

  @override
  RegalosTokens copyWith({
    AccentPalette? accent,
    Brightness? brightness,
    OccasionTheme? occasion,
  }) => RegalosTokens.resolve(
    accent: accent ?? this.accent,
    brightness: brightness ?? this.brightness,
    occasion: occasion ?? this.occasion,
  );

  /// Los tokens no se interpolan: el cambio de tema es un corte limpio.
  @override
  RegalosTokens lerp(ThemeExtension<RegalosTokens>? other, double t) {
    if (other is! RegalosTokens) return this;
    return t < 0.5 ? this : other;
  }
}
