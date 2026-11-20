import 'package:flutter/material.dart';

import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_tokens.dart';
import 'board_scope.dart';

/// El marco de una pantalla del tablero (la guía de diseño de escritorio): cabecera con el título, una línea de apoyo y los
/// botones a la derecha, y debajo lo que traiga la pantalla.
///
/// Dos formas:
/// - con [body], la cabecera y los [children] se quedan fijos y el [body]
///   llena el alto que queda (los carriles de «Hoy» y de una ocasión se
///   desplazan por dentro);
/// - sin él, todo va en una sola columna que se desplaza.
///
/// Todas las pantallas empiezan en el mismo margen izquierdo
/// (`BoardScope.marginOf`: 24, 32 o 40 según el ancho de la ventana) y llenan
/// el ancho hasta el mismo margen derecho. Entra de arriba abajo, un bloque
/// tras otro, una sola vez por visita, como las demás pantallas.
class BoardPage extends StatelessWidget {
  /// Crea el marco.
  const BoardPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.children = const <Widget>[],
    this.body,
  });

  /// El título.
  final String title;

  /// La línea de apoyo bajo el título.
  final String? subtitle;

  /// Los botones de la derecha de la cabecera.
  final List<Widget> actions;

  /// Los bloques de debajo (fijos si hay [body]; con él, antes del cuerpo).
  final List<Widget> children;

  /// El cuerpo que llena el alto que queda, o `null` para una columna que se
  /// desplaza con los [children].
  final Widget? body;

  /// El margen por defecto de los lados (el de las ventanas de 1600 a 2400).
  static const double gutter = 32;

  /// El margen de arriba.
  static const double top = 20;

  /// El margen de abajo del cuerpo que llena el alto, por encima del margen
  /// seguro del sistema (la barra de gestos de una tableta, por ejemplo).
  static const double bottom = 16;

  Widget _header(BuildContext context, RegalosTokens t) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: t.styles.boardTitle),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: t.styles.boardSubtitle),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final margin = BoardScope.marginOf(context);
    // El margen seguro de abajo va dentro del relleno: con `SafeArea` de
    // abajo apagado, el final del carril quedaba debajo de la barra del
    // sistema.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    var order = 0;
    final header = StaggerItem(index: order++, child: _header(context, t));
    final Widget content;
    if (body != null) {
      content = Padding(
        padding: EdgeInsets.fromLTRB(margin, top, margin, bottom + safeBottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            for (final child in children)
              StaggerItem(index: order++, child: child),
            Expanded(
              child: StaggerItem(index: order++, child: body!),
            ),
          ],
        ),
      );
    } else {
      content = ListView(
        padding: EdgeInsets.fromLTRB(margin, top, margin, 48 + safeBottom),
        children: [
          header,
          for (final child in children)
            StaggerItem(index: order++, child: child),
        ],
      );
    }
    return StaggerScope(
      child: ColoredBox(
        color: t.bg,
        child: SafeArea(bottom: false, child: content),
      ),
    );
  }
}

/// El título pequeño de una zona de la pantalla («Qué toca ahora»).
class BoardCaption extends StatelessWidget {
  /// Crea el título.
  const BoardCaption(this.text, {super.key});

  /// El texto.
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Semantics(
        header: true,
        child: Text(text, style: t.styles.sectionTitle),
      ),
    );
  }
}

/// Una pantalla del tablero que no se monta mientras otra la tapa: la lista de
/// `/people` queda debajo de la de una persona, y no hay por qué pintar los
/// carriles dos veces.
class BoardCoveredGuard extends StatelessWidget {
  /// Crea la guarda.
  const BoardCoveredGuard({super.key, required this.child});

  /// La pantalla.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
