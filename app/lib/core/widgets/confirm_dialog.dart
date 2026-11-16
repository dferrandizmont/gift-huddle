import 'package:flutter/material.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// Pregunta antes de borrar (§2.10 de la guía de movimiento).
///
/// Todo lo que borra pasa por aquí: el diálogo es una superficie de radio 8
/// con dos botones rectangulares que se reparten el ancho, «Cancelar» con
/// contorno y el destructivo en rojo claro. Devuelve `true` solo si se
/// confirma.
///
/// Entra con una escala de 1,08 a 1 (`snap`) y un fundido de 150 ms sobre el
/// velo de Reparto; sale en 150 ms con `fold` (opacidad a 0 y escala a 0,96).
/// Con «Reducir movimiento» solo se funde en 150 ms. El fondo no se mueve.
Future<bool> showRegalosConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final result = await showRegalosDialog<bool>(
    context,
    avoidKeyboard: false,
    builder: (dialogContext) => ConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  return result ?? false;
}

/// Abre un diálogo propio con el mismo movimiento y el mismo velo que
/// [showRegalosConfirm] (para los que llevan algo más que dos botones, como
/// el último paso de «Borrar todo»). El contenido suele ser un
/// [RegalosDialogSurface].
///
/// Con [avoidKeyboard], si sale el teclado el diálogo sube con él.
Future<T?> showRegalosDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool avoidKeyboard = true,
}) => Navigator.of(context, rootNavigator: true).push<T>(
  _ConfirmRoute<T>(
    avoidKeyboard: avoidKeyboard,
    reduce: RegalosMotion.of(context).reduce,
    scrim: RegalosTokens.of(context).scrim,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    builder: builder,
  ),
);

class _ConfirmRoute<T> extends PopupRoute<T> {
  _ConfirmRoute({
    required this.avoidKeyboard,
    required this.reduce,
    required this.scrim,
    required this.builder,
    required this.barrierLabel,
  });

  final bool avoidKeyboard;
  final bool reduce;
  final Color scrim;
  final WidgetBuilder builder;
  @override
  final String barrierLabel;

  @override
  Color get barrierColor => scrim;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reduce ? RegalosMotion.fade : RegalosSprings.snapDuration;

  @override
  Duration get reverseTransitionDuration =>
      reduce ? RegalosMotion.fade : const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => AnimatedPadding(
    // Con el teclado fuera, el diálogo se centra en lo que queda a la vista.
    padding: avoidKeyboard ? MediaQuery.viewInsetsOf(context) : EdgeInsets.zero,
    duration: reduce ? Duration.zero : RegalosCurves.foldDuration,
    curve: RegalosCurves.fold,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            child: builder(context),
          ),
        ),
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduce) {
      return FadeTransition(opacity: animation, child: child);
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value;
        if (animation.status == AnimationStatus.reverse) {
          // La salida no rebota: 150 ms con `fold`.
          final k = RegalosCurves.fold.transform(v.clamp(0.0, 1.0));
          return Opacity(
            opacity: k,
            child: Transform.scale(scale: 0.96 + 0.04 * k, child: child),
          );
        }
        // La entrada: la escala sigue el muelle y el fundido dura el 40 %
        // inicial (150 ms).
        final scale = 1.08 - 0.08 * RegalosCurves.snap.transform(v);
        final opacity = (v / 0.4).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

/// El cuerpo del diálogo de confirmación.
class ConfirmDialog extends StatelessWidget {
  /// Crea el diálogo.
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  /// Lo que se pregunta («¿Borrar «Patinete»?»).
  final String title;

  /// La consecuencia.
  final String body;

  /// El botón destructivo.
  final String confirmLabel;

  /// El botón que cierra sin hacer nada.
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return RegalosDialogSurface(
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: t.styles.screenTitleSmall),
          ),
          const SizedBox(height: 8),
          Text(body, style: t.styles.body),
          const SizedBox(height: 20),
          DialogButtonRow(
            cancelLabel: cancelLabel,
            confirmLabel: confirmLabel,
            cancel: OutlinedButton(
              style: regalosDialogCancelStyle(t),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
            confirm: FilledButton(
              style: regalosDialogDangerStyle(t),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Los dos botones de un diálogo: lado a lado, repartiéndose el ancho, solo si
/// las dos etiquetas caben en una línea; si no, apilados a todo el ancho con
/// el que cierra sin hacer nada ([cancel]) arriba y la acción ([confirm])
/// debajo. Un botón nunca parte su texto en dos líneas por quedarse estrecho.
///
/// Mide las etiquetas con la letra y la escala del sistema y el estilo de
/// botón del tema, así que vale en cualquier idioma y con «Tamaño de letra».
/// [cancelLabel] y [confirmLabel] son los textos de [cancel] y [confirm].
class DialogButtonRow extends StatelessWidget {
  /// Crea la fila.
  const DialogButtonRow({
    super.key,
    required this.cancel,
    required this.confirm,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  /// El botón que cierra sin hacer nada.
  final Widget cancel;

  /// El botón de la acción.
  final Widget confirm;

  /// El texto de [cancel].
  final String cancelLabel;

  /// El texto de [confirm].
  final String confirmLabel;

  /// Relleno horizontal de cada botón (ver `regalosDialog*Style`) y el trazo
  /// del contorno, que también ocupa sitio.
  static const double _chrome = 2 * _buttonPadding + 2;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double labelWidth(String label, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style ?? theme.textTheme.labelLarge),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final cancelWidth = labelWidth(
      cancelLabel,
      theme.outlinedButtonTheme.style?.textStyle?.resolve(const {}),
    );
    final confirmWidth = labelWidth(
      confirmLabel,
      theme.filledButtonTheme.style?.textStyle?.resolve(const {}),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - _gap) / 2;
        final sideBySide =
            constraints.maxWidth.isFinite &&
            cancelWidth + _chrome <= half &&
            confirmWidth + _chrome <= half;
        if (sideBySide) {
          return Row(
            children: [
              Expanded(child: cancel),
              const SizedBox(width: _gap),
              Expanded(child: confirm),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cancel,
            const SizedBox(height: _gap),
            confirm,
          ],
        );
      },
    );
  }
}

/// La superficie de un diálogo: radio 8, borde fino y 340 de ancho como
/// mucho. Con [scrollable], si el contenido no cabe (letra grande, teclado)
/// se desplaza.
class RegalosDialogSurface extends StatelessWidget {
  /// Crea la superficie.
  const RegalosDialogSurface({
    super.key,
    required this.child,
    this.scrollable = false,
  });

  /// El contenido.
  final Widget child;

  /// Si el contenido se desplaza cuando no cabe.
  final bool scrollable;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(20, 20, 20, 16);

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          color: t.sheet,
          shape: RoundedRectangleBorder(
            borderRadius: RegalosShape.card,
            side: BorderSide(color: t.separator),
          ),
          clipBehavior: Clip.antiAlias,
          child: scrollable
              ? SingleChildScrollView(padding: _padding, child: child)
              : Padding(padding: _padding, child: child),
        ),
      ),
    );
  }
}

/// Relleno horizontal de los botones de un diálogo: menos que el de Material
/// (24) para que dos etiquetas medianas quepan lado a lado.
const double _buttonPadding = 16;

/// El botón que cierra un diálogo sin hacer nada: contorno, radio 8.
ButtonStyle regalosDialogCancelStyle(RegalosTokens t) =>
    OutlinedButton.styleFrom(
      foregroundColor: t.text,
      minimumSize: const Size(44, 48),
      padding: const EdgeInsets.symmetric(horizontal: _buttonPadding),
      side: BorderSide(color: t.controlBorder),
      shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
    );

/// El botón destructivo de un diálogo: rojo claro con texto rojo, radio 8.
/// Desactivado, se apaga sin cambiar de forma.
ButtonStyle regalosDialogDangerStyle(RegalosTokens t) => FilledButton.styleFrom(
  backgroundColor: t.dangerSoft,
  foregroundColor: t.danger,
  disabledBackgroundColor: t.dangerSoft.withValues(alpha: 0.45),
  disabledForegroundColor: t.danger.withValues(alpha: 0.45),
  padding: const EdgeInsets.symmetric(horizontal: _buttonPadding),
  shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
);

/// El botón principal de un diálogo que no destruye nada: relleno del acento,
/// radio 8 y alto de 48, como los demás botones de un diálogo.
ButtonStyle regalosDialogPrimaryStyle(RegalosTokens t) =>
    FilledButton.styleFrom(
      minimumSize: const Size(44, 48),
      padding: const EdgeInsets.symmetric(horizontal: _buttonPadding),
      shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
    );
