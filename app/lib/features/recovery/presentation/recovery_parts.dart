import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/pop_in.dart';
import '../../../core/motion/step_segments.dart';
import '../../../core/motion/success_mark.dart' show DrawnCheck;
import '../../../core/theme/regalos_motion.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';

/// El marco de las pantallas a pantalla completa del código de recuperación
/// (crear, cambiar y recuperar): flecha de volver, pasos opcionales, el
/// contenido que se desplaza en una columna de 520 y, abajo, los botones.
///
/// Es el mismo esqueleto del primer uso, para que se sienta de la casa.
class RecoveryFlowScaffold extends StatelessWidget {
  /// Crea el marco.
  const RecoveryFlowScaffold({
    super.key,
    required this.child,
    required this.onBack,
    this.backLabel,
    this.step,
    this.steps,
    this.footer,
  });

  /// El contenido, que se desplaza.
  final Widget child;

  /// Lo que hace la flecha de volver; `null` la quita.
  final VoidCallback? onBack;

  /// La etiqueta accesible de la flecha.
  final String? backLabel;

  /// El paso actual (empieza en 1), si hay indicador de pasos.
  final int? step;

  /// Cuántos pasos hay.
  final int? steps;

  /// Los botones de abajo, si hay.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final step = this.step;
    final steps = this.steps;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ContentWidth(
              maxWidth: RegalosLayout.onboardingColumn,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 44,
                      child: onBack == null
                          ? null
                          : Semantics(
                              button: true,
                              label: backLabel ?? l10n.actionBack,
                              excludeSemantics: true,
                              onTap: onBack,
                              child: InkResponse(
                                onTap: onBack,
                                child: Center(
                                  child: StrokeIcon(
                                    AppIcons.back,
                                    color: t.text,
                                    strokeWidth: 1.9,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (step != null && steps != null)
                      Expanded(
                        child: StepSegments(
                          count: steps,
                          filled: step,
                          semanticLabel: l10n.onboardingStepOf(step, steps),
                        ),
                      )
                    else
                      const Spacer(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: ContentWidth(
                  maxWidth: RegalosLayout.onboardingColumn,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: child,
                  ),
                ),
              ),
            ),
            if (footer != null)
              Container(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.separator)),
                ),
                child: ContentWidth(
                  maxWidth: RegalosLayout.onboardingColumn,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    // Siempre en columna a ancho completo, sea un botón o
                    // varios.
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [footer!],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Título y explicación de un paso.
class RecoveryHeading extends StatelessWidget {
  /// Crea el encabezado.
  const RecoveryHeading({super.key, required this.title, this.body});

  /// El título.
  final String title;

  /// La explicación.
  final String? body;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: t.styles.screenTitle),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(body!, style: t.styles.body.copyWith(color: t.textSecondary)),
        ],
      ],
    );
  }
}

/// Un icono de trazo en un cuadro suave de radio 8.
class RecoveryBadge extends StatelessWidget {
  /// Crea el cuadro.
  const RecoveryBadge({super.key, required this.icon, this.size = 48});

  /// El icono.
  final StrokeIconBuilder icon;

  /// El lado del cuadro.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.card,
        ),
        child: StrokeIcon(
          icon,
          size: size * 0.5,
          color: t.ink,
          strokeWidth: 1.8,
        ),
      ),
    );
  }
}

/// Una superficie con título y texto, para el estado del código y los avisos.
class RecoveryCard extends StatelessWidget {
  /// Crea la tarjeta.
  const RecoveryCard({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.extra,
  });

  /// El título.
  final String title;

  /// El texto.
  final String body;

  /// Lo que va a la izquierda del título (un icono o un indicador).
  final Widget? leading;

  /// Lo que va debajo del texto.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: RegalosShape.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: t.styles.rowTitle),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: t.styles.body.copyWith(color: t.textSecondary),
                ),
                if (extra != null) ...[const SizedBox(height: 12), extra!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una frase corta con un punto de lista, para las ideas previas al código.
class RecoveryPoint extends StatelessWidget {
  /// Crea la frase.
  const RecoveryPoint(this.text, {super.key});

  /// La frase.
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 9, right: 12, left: 4),
            child: ExcludeSemantics(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: t.ink,
                  borderRadius: RegalosShape.tiny,
                ),
              ),
            ),
          ),
          Expanded(child: Text(text, style: t.styles.body)),
        ],
      ),
    );
  }
}

/// Cambia de alto con `snap` y funde lo que entra y lo que sale cuando
/// cambia [stateKey]; con «Reducir movimiento», solo el fundido de 150 ms.
class RecoveryFade extends StatelessWidget {
  /// Crea el cambiador.
  const RecoveryFade({super.key, required this.stateKey, required this.child});

  /// Qué contenido es.
  final Object stateKey;

  /// El contenido.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    final switcher = AnimatedSwitcher(
      duration: motion.duration(const Duration(milliseconds: 200)),
      switchInCurve: motion.curve(RegalosCurves.fold),
      switchOutCurve: motion.curve(RegalosCurves.fold),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
    if (motion.reduce) {
      return switcher;
    }
    return AnimatedSize(
      duration: RegalosSprings.snapDuration,
      curve: RegalosCurves.snap,
      alignment: Alignment.topCenter,
      child: switcher,
    );
  }
}

/// El indicador de «trabajando» de 20 de lado, con el color de tinta.
class RecoverySpinner extends StatelessWidget {
  /// Crea el indicador.
  const RecoverySpinner({super.key, this.size = 20});

  /// El lado.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: t.ink),
    );
  }
}

/// Cuántas columnas caben en [width] para las celdas de palabras: dos en el
/// móvil, tres si sobra sitio y una con la letra muy grande.
int recoveryGridColumns(BuildContext context, double width) {
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  if (scale > 1.6) {
    return 1;
  }
  if (scale > 1.25) {
    return 2;
  }
  return width >= 440 ? 3 : 2;
}

/// «¿Cancelar la recuperación?». El texto depende de si la reclamación ya se
/// envió ([claimSent]): antes basta con descartar lo temporal; después, la
/// lista ya se ha pasado a este código y cancelar no lo deshace.
Future<bool> confirmAbandonRecovery(
  BuildContext context, {
  required bool claimSent,
}) {
  final l10n = AppLocalizations.of(context);
  return showRegalosConfirm(
    context,
    title: l10n.recoverAbandonTitle,
    body: claimSent ? l10n.recoverAbandonBodyClaimed : l10n.recoverAbandonBody,
    confirmLabel: l10n.recoverAbandonConfirm,
    cancelLabel: l10n.recoverAbandonKeep,
  );
}

/// El sello de «hecho»: el mismo cuadro que `SuccessMark`, con el visto en el
/// color de encima del relleno (`onFill`) para que se lea también en oscuro.
class RecoverySuccessMark extends StatelessWidget {
  /// Crea el sello.
  const RecoverySuccessMark({super.key, this.size = 56});

  /// El lado del cuadro.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: PopIn(
        from: 0.8,
        delay: const Duration(milliseconds: 60),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: RegalosShape.chip,
          ),
          child: DrawnCheck(
            color: t.onFill,
            size: size * 0.55,
            delay: const Duration(milliseconds: 180),
            duration: const Duration(milliseconds: 300),
            curve: RegalosCurves.snap,
          ),
        ),
      ),
    );
  }
}
