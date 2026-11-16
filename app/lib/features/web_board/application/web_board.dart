import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/window_class.dart';
import '../../web_device/application/web_app_provider.dart';

/// Si la web usa el tablero «Hoy» en las ventanas de escritorio.
///
/// Es la decisión de producto del 2026-11-14: la web de escritorio pasa al
/// diseño A de la guía de diseño de escritorio (barra lateral,
/// tablero de carriles y editor como panel fijo a la derecha). Solo la web: el
/// móvil y la tablet nativos no cambian. Las pruebas lo apagan para comprobar
/// el diseño anterior por bandas.
final webBoardEnabledProvider = Provider<bool>(
  (ref) => ref.watch(webAppProvider),
);

/// Si una ventana de [windowWidth] puntos lógicos (ya sin la escala de
/// interfaz) enseña el tablero: desde 1280.
bool boardWidth(double windowWidth) => RegalosLayout.isDesktop(windowWidth);

/// Si el árbol de [context] está en el tablero de la web de escritorio.
bool isWebBoard(BuildContext context, WidgetRef ref) =>
    ref.watch(webBoardEnabledProvider) &&
    boardWidth(MediaQuery.sizeOf(context).width);

/// Elige entre el tablero ([board]) y la pantalla de siempre ([classic])
/// según la ventana. Fuera de la web, o por debajo de 1280, siempre [classic].
class WebBoardGate extends ConsumerWidget {
  /// Crea la puerta.
  const WebBoardGate({super.key, required this.board, required this.classic});

  /// La pantalla del tablero.
  final Widget board;

  /// La de siempre.
  final Widget classic;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      isWebBoard(context, ref) ? board : classic;
}
