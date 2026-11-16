import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/window_class.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../web_board/application/board_metrics.dart';
import '../../web_board/application/web_board.dart';
import '../application/web_app_provider.dart';

/// Las bandas de la web de escritorio
/// (la guía de diseño de escritorio, §2).
///
/// Mide el ancho lógico de la ventana (ya sin la escala de interfaz,
/// `UiScale`) y reparte [DesktopBands] por el árbol: las medidas de las
/// columnas, que usan `TwoPane`, el raíl y `detailColumnWidth`.
///
/// La composición (raíl, lista, detalle y tercera columna) no pasa de
/// `DesktopBands.maxWidth` (1880 o 2060). Si la ventana es más ancha, la
/// composición se centra y lo que sobra queda a cada lado como prolongación
/// de las bandas laterales, en `t.surface`. El hijo ve un `MediaQuery` con el
/// ancho de la composición, para que la clase de ventana, el raíl y los
/// paneles se midan sobre ella y no sobre toda la ventana.
///
/// Fuera de la web no hace nada: el hijo recibe las mismas restricciones y
/// ningún ámbito. En la web el árbol tiene siempre la misma forma (también sin
/// márgenes ni bandas): cambiar el tamaño de la ventana no desmonta la app.
class WebDesktopFrame extends ConsumerWidget {
  /// Crea el marco.
  const WebDesktopFrame({super.key, required this.child});

  /// El ancho máximo de la composición del tablero «Hoy»: el del tope de
  /// `BoardMetrics.maxComposition` (3840 lógicos). Con una pantalla de 34″ no se
  /// llega: el tablero llena la ventana y no hay franja a los lados.
  static const double boardMaxWidth = BoardMetrics.maxComposition;

  /// La app.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webAppProvider)) return child;
    final media = MediaQuery.of(context);
    final window = media.size.width;
    // El tablero «Hoy» (desde 1280) no usa las bandas: llena la ventana, sin
    // tope de composición (la guía de diseño de escritorio);
    // solo por encima de 3840 lógicos se centra y lo que sobra queda en `t.bg`.
    final board = ref.watch(webBoardEnabledProvider) && boardWidth(window);
    final bands = board ? null : DesktopBands.forWindow(window);
    final composition = math.min(
      window,
      board ? WebDesktopFrame.boardMaxWidth : (bands?.maxWidth ?? window),
    );
    final margin = (window - composition) / 2;
    final t = RegalosTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: margin,
          child: ColoredBox(color: board ? t.bg : t.surface),
        ),
        Expanded(
          child: MediaQuery(
            data: media.copyWith(size: Size(composition, media.size.height)),
            child: DesktopBandsScope(bands: bands, child: child),
          ),
        ),
        SizedBox(
          width: margin,
          child: ColoredBox(color: board ? t.bg : t.surface),
        ),
      ],
    );
  }
}
