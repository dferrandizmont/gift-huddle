import 'package:flutter/material.dart';

import '../motion/success_mark.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'settings_icons.dart';
import 'stroke_icon.dart';
import 'tabler_icons.dart';

// Piezas de las hojas de Ajustes y Compartir (la maqueta de ajustes):
// cabecera, opción con visto, puerta a un paso, aviso y el cambio de paso
// dentro de la misma hoja.

/// Cabecera de una hoja: título, frase opcional y, en un paso interior, la
/// flecha que vuelve al anterior.
class SheetHeading extends StatelessWidget {
  /// Crea la cabecera.
  const SheetHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.backLabel,
  });

  /// Título de la hoja o del paso.
  final String title;

  /// Frase bajo el título.
  final String? subtitle;

  /// Vuelve al paso anterior; sin ella no hay flecha.
  final VoidCallback? onBack;

  /// Etiqueta accesible de la flecha.
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack == null ? 16 : 6, 0, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            Semantics(
              container: true,
              button: true,
              label: backLabel,
              excludeSemantics: true,
              onTap: onBack,
              child: InkWell(
                onTap: onBack,
                customBorder: const RoundedRectangleBorder(
                  borderRadius: RegalosShape.button,
                ),
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: StrokeIcon(
                      SettingsIcons.arrowBack,
                      color: t.text,
                      strokeWidth: 1.9,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: onBack == null ? 0 : 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: t.styles.screenTitleSmall.copyWith(
                        fontSize: 18,
                        height: 24 / 18,
                      ),
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: t.styles.meta),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una opción de una lista de elegir una: nombre, frase opcional y, a la
/// derecha, el visto de la elegida.
///
/// El visto de la que ya estaba elegida al abrir aparece entero
/// ([drawCheck] `false`); el de la que se acaba de tocar se dibuja en 300 ms.
/// Con «Reducir movimiento» aparece entero siempre.
class CheckOptionRow extends StatelessWidget {
  /// Crea la opción.
  const CheckOptionRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.hint,
    this.leading,
    this.drawCheck = false,
  });

  /// Lo que va antes del nombre (el avatar de una persona, por ejemplo).
  /// Es decorativo: la etiqueta accesible es el nombre.
  final Widget? leading;

  /// Nombre de la opción.
  final String title;

  /// Frase bajo el nombre.
  final String? hint;

  /// Si es la elegida.
  final bool selected;

  /// Si el visto se dibuja (recién elegida) o sale entero.
  final bool drawCheck;

  /// Elige la opción.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: hint == null ? title : '$title. $hint',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: hint == null ? 52 : 60),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.separator)),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.styles.rowTitle.copyWith(
                        color: selected ? t.ink : t.text,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (hint != null) Text(hint!, style: t.styles.meta),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox.square(
                dimension: 22,
                child: selected
                    ? DrawnCheck(
                        key: ValueKey<bool>(drawCheck),
                        color: t.ink,
                        size: 22,
                        strokeWidth: 2.2,
                        duration: const Duration(milliseconds: 300),
                        delay: const Duration(milliseconds: 40),
                        curve: const Cubic(0.3, 0.7, 0.3, 1),
                        progress: drawCheck
                            ? null
                            : const AlwaysStoppedAnimation<double>(1),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una puerta dentro de una hoja: cuadro de 40 con icono, título, frase y
/// flecha. Lleva a otro paso o a otra pantalla.
class SheetDoor extends StatelessWidget {
  /// Crea la puerta.
  const SheetDoor({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  /// Icono del cuadro.
  final StrokeIconBuilder icon;

  /// Qué hace.
  final String title;

  /// Frase bajo el título.
  final String hint;

  /// Se llama al tocarla.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      button: true,
      label: '$title. $hint',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.separator)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.fill,
                  borderRadius: RegalosShape.chip,
                ),
                child: StrokeIcon(icon, color: t.onFill, strokeWidth: 1.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.styles.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(hint, style: t.styles.meta),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StrokeIcon(
                AppIcons.chevronRight,
                color: t.textSecondary,
                strokeWidth: 1.9,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso dentro de una hoja o de una pantalla: triángulo y texto sobre la
/// superficie, con radio 8.
class WarningBox extends StatelessWidget {
  /// Crea el aviso.
  const WarningBox(this.text, {super.key});

  /// Lo que avisa.
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: RegalosShape.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: StrokeIcon(
              tablerAlertTriangle,
              size: 18,
              color: t.text,
              strokeWidth: 1.9,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: t.styles.meta)),
        ],
      ),
    );
  }
}

/// El contenido de una hoja con pasos: al cambiar [step], el paso nuevo entra
/// 44 px desde la derecha (o desde la izquierda al volver, con [back]) y la
/// hoja cambia de alto con `snap`, sin cerrarse.
///
/// Con «Reducir movimiento» el paso nuevo se funde en 150 ms y la hoja no se
/// estira: cambia de alto de golpe.
class SheetSteps extends StatefulWidget {
  /// Crea el cambiador de pasos.
  const SheetSteps({
    super.key,
    required this.step,
    required this.child,
    this.back = false,
    this.distance = travel,
  });

  /// Cuánto se desplaza el paso que entra. En una pantalla entera (el primer
  /// uso) el recorrido es de 24 px, el del eje compartido.
  final double distance;

  /// El paso actual; al cambiar, se anima.
  final Object step;

  /// Si el último cambio fue volver atrás.
  final bool back;

  /// El contenido del paso actual.
  final Widget child;

  /// Cuánto se desplaza el paso que entra.
  static const double travel = 44;

  @override
  State<SheetSteps> createState() => _SheetStepsState();
}

class _SheetStepsState extends State<SheetSteps>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
    // Con «Quitar animaciones» el fundido sigue durando 150 ms.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(SheetSteps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) {
      final motion = RegalosMotion.of(context);
      _controller
        ..duration = motion.duration(RegalosSprings.snapDuration)
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    final content = AnimatedBuilder(
      animation: _controller,
      child: KeyedSubtree(
        key: ValueKey<Object>(widget.step),
        child: widget.child,
      ),
      builder: (context, child) {
        final v = _controller.value;
        if (motion.reduce) {
          return Opacity(opacity: v, child: child);
        }
        final k = RegalosCurves.snap.transform(v);
        return Opacity(
          opacity: (v / 0.5).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(
              (widget.back ? -1 : 1) * widget.distance * (1 - k),
              0,
            ),
            child: child,
          ),
        );
      },
    );
    if (motion.reduce) {
      return content;
    }
    return AnimatedSize(
      duration: RegalosSprings.snapDuration,
      curve: RegalosCurves.snap,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}
