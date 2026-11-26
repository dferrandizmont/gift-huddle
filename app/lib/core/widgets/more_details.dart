import 'package:flutter/material.dart';

import '../motion/unfold_section.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Una sección plegable de un formulario («Más detalles»): una fila de 48 dp
/// con el título y un chevron, y debajo [child], que se despliega con el
/// muelle `snap` al abrir y se pliega sin rebote al cerrar ([UnfoldSection]).
///
/// El estado ([open]) lo lleva quien la usa, para poder abrirla sola cuando
/// un campo de dentro ya tiene valor o falla al guardar. Plegada, y con
/// [summary] (qué campos de dentro tienen datos), lo dice en una línea bajo
/// el título. Con «Reducir movimiento» el chevron cambia con un fundido y el
/// contenido aparece y desaparece fundido, sin cambiar de altura.
class MoreDetails extends StatelessWidget {
  /// Crea la sección.
  const MoreDetails({
    super.key,
    required this.title,
    required this.open,
    required this.onToggle,
    required this.child,
    this.summary,
  });

  /// El título de la fila.
  final String title;

  /// Si el contenido está a la vista.
  final bool open;

  /// Abre o cierra la sección.
  final VoidCallback onToggle;

  /// Lo que se pliega.
  final Widget child;

  /// Qué hay dentro con datos, para la fila plegada; `null`, nada.
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final showSummary = !open && summary != null && summary!.isNotEmpty;
    final chevron = reduce
        ? AnimatedSwitcher(
            duration: RegalosMotion.fade,
            child: StrokeIcon(
              open ? AppIcons.chevronUp : AppIcons.chevronDown,
              key: ValueKey<bool>(open),
              size: 20,
              color: t.textSecondary,
            ),
          )
        : AnimatedRotation(
            turns: open ? 0.5 : 0,
            // A la par del despliegue: `snap` al abrir, `fold` al cerrar.
            duration: open
                ? RegalosSprings.snapDuration
                : RegalosCurves.foldDuration,
            curve: open ? RegalosCurves.snap : RegalosCurves.fold,
            child: StrokeIcon(
              AppIcons.chevronDown,
              size: 20,
              color: t.textSecondary,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          expanded: open,
          label: showSummary ? '$title. $summary' : title,
          onTap: onToggle,
          excludeSemantics: true,
          child: InkWell(
            onTap: onToggle,
            customBorder: const RoundedRectangleBorder(
              borderRadius: RegalosShape.button,
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.separator)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: t.styles.label.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (showSummary)
                          Text(
                            summary!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.styles.meta,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  chevron,
                ],
              ),
            ),
          ),
        ),
        UnfoldSection(
          show: open,
          child: Padding(padding: const EdgeInsets.only(top: 8), child: child),
        ),
      ],
    );
  }
}
