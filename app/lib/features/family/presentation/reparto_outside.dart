import 'package:flutter/material.dart';

import '../../../core/layout/large_text.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import 'reparto_fold.dart';
import 'reparto_grid.dart' show RepartoAvatar;

/// Clave del botón que pliega y despliega «Fuera del reparto» (para las
/// pruebas).
const Key kRepartoOutsideToggleKey = ValueKey<String>('repartoOutsideToggle');

/// Clave del botón «Volver a incluir» de una persona (para las pruebas).
Key repartoIncludeKey(String recipientId) =>
    ValueKey<String>('repartoInclude:$recipientId');

/// El bloque plegable del final de la rejilla: «Fuera del reparto · N», con
/// cada persona que no sale en Reparto y su botón «Volver a incluir».
///
/// Excluir no borra nada: la persona sigue en Personas con todos sus regalos.
/// Cuando alguien sale, su fila se pliega arriba y aparece aquí; al volver a
/// incluirla, esta fila se pliega y la de arriba vuelve con muelle.
class OutsideBlock extends StatefulWidget {
  /// Crea el bloque.
  const OutsideBlock({
    super.key,
    required this.outside,
    required this.onOpenPerson,
    required this.onInclude,
  });

  /// Las personas que no salen en Reparto.
  final List<Recipient> outside;

  /// Al tocar el nombre de una persona se abre su ficha.
  final void Function(Recipient recipient, Rect from) onOpenPerson;

  /// Al pulsar «Volver a incluir».
  final ValueChanged<Recipient> onInclude;

  @override
  State<OutsideBlock> createState() => _OutsideBlockState();
}

class _OutsideBlockState extends State<OutsideBlock> {
  bool _open = false;
  late final FoldTracker<Recipient> _rows = FoldTracker<Recipient>(
    (r) => r.id,
    widget.outside,
  );

  @override
  void didUpdateWidget(OutsideBlock old) {
    super.didUpdateWidget(old);
    _rows.update(widget.outside);
    if (!_open) {
      // Plegado no hay filas que animar: los fantasmas sobran.
      _rows.entries.removeWhere((e) => e.leaving);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _rows.settle());
  }

  void _toggle() => setState(() {
    _open = !_open;
    if (!_open) {
      _rows.entries.removeWhere((e) => e.leaving);
    }
  });

  void _gone(String id) {
    if (!mounted) {
      return;
    }
    setState(() => _rows.gone(id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final count = widget.outside.length;
    final visible = count > 0 || _rows.hasLeaving;
    final title = l10n.familyOutsideTitle(count);
    final Widget content = visible
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Semantics(
                container: true,
                button: true,
                expanded: _open,
                label: title,
                excludeSemantics: true,
                onTap: _toggle,
                child: GestureDetector(
                  key: kRepartoOutsideToggleKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: RegalosShape.button,
                    ),
                    // Con letra grande el título pasa a varias líneas y la
                    // barra crece en vez de cortarlo con «…».
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: isLargeText(context) ? 8 : 0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: motion.duration(
                                  const Duration(milliseconds: 200),
                                ),
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [...previous, ?current],
                                ),
                                child: Text(
                                  title,
                                  key: ValueKey<int>(count),
                                  maxLines: isLargeText(context) ? 3 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.styles.metaStrong.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: t.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _open ? 0.5 : 0,
                              duration: motion.duration(
                                RegalosSprings.snapDuration,
                              ),
                              curve: motion.curve(RegalosCurves.snap),
                              child: StrokeIcon(
                                AppIcons.chevronDown,
                                size: 16,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                alignment: Alignment.topCenter,
                duration: _open
                    ? motion.duration(RegalosSprings.snapDuration)
                    : motion.duration(RegalosCurves.foldDuration),
                curve: _open
                    ? motion.curve(RegalosCurves.snap)
                    : RegalosCurves.fold,
                child: _open
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final e in _rows.entries)
                            FoldTransition(
                              key: ValueKey<String>('out:${e.item.id}'),
                              entering: e.entering,
                              leaving: e.leaving,
                              onGone: () => _gone(e.item.id),
                              child: _OutsideRow(
                                recipient: e.item,
                                onOpenPerson: widget.onOpenPerson,
                                onInclude: widget.onInclude,
                              ),
                            ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          )
        : const SizedBox(width: double.infinity);
    // En una ventana ancha el bloque no se estira con la rejilla ni con las
    // dos columnas de tarjetas: «Volver a incluir» se queda junto al nombre.
    // En el móvil no hay tope y mide lo de siempre.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: WindowClass.of(context).usesRail
              ? RegalosLayout.formColumn
              : double.infinity,
        ),
        child: AnimatedSize(
          alignment: Alignment.topCenter,
          duration: motion.duration(RegalosSprings.snapDuration),
          curve: motion.curve(RegalosCurves.snap),
          child: content,
        ),
      ),
    );
  }
}

/// Una persona fuera del reparto: avatar cuadrado de tamaño fijo (nunca una
/// elipse), su nombre, la nota y el botón para volver a incluirla.
class _OutsideRow extends StatelessWidget {
  const _OutsideRow({
    required this.recipient,
    required this.onOpenPerson,
    required this.onInclude,
  });

  final Recipient recipient;
  final void Function(Recipient, Rect) onOpenPerson;
  final ValueChanged<Recipient> onInclude;

  void _open(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      return;
    }
    onOpenPerson(recipient, box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.separator)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: _OutsideRowLayout(
          large: isLargeText(context),
          person: Builder(
            builder: (context) => Semantics(
              container: true,
              button: true,
              label: l10n.repartoPersonOpen(recipient.name),
              excludeSemantics: true,
              onTap: () => _open(context),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Opacity(
                    opacity: 0.75,
                    child: Row(
                      children: [
                        RepartoAvatar(
                          name: recipient.name,
                          colorIndex: recipient.colorIndex,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recipient.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.styles.metaStrong.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                l10n.familyOutsideNote,
                                maxLines: isLargeText(context) ? 3 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.styles.caption.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          include: _IncludeButton(
            key: repartoIncludeKey(recipient.id),
            label: l10n.familyIncludeAgain,
            semantics: '${l10n.familyIncludeAgain}: ${recipient.name}',
            onTap: () => onInclude(recipient),
          ),
        ),
      ),
    );
  }
}

/// Una fila de «Fuera del reparto»: la persona y su botón «Volver a incluir».
/// Lado a lado, o con letra grande el botón debajo, alineado con el nombre.
class _OutsideRowLayout extends StatelessWidget {
  const _OutsideRowLayout({
    required this.large,
    required this.person,
    required this.include,
  });

  final bool large;
  final Widget person;
  final Widget include;

  @override
  Widget build(BuildContext context) {
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          person,
          Padding(
            padding: const EdgeInsets.only(
              left: kAvatarIndent,
              bottom: kStackedBottom,
            ),
            child: include,
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: person),
        const SizedBox(width: 8),
        include,
      ],
    );
  }
}

/// «Volver a incluir»: chip de borde discontinuo con radio 8, como los demás
/// botones de Reparto (nada de píldoras).
class _IncludeButton extends StatelessWidget {
  const _IncludeButton({
    super.key,
    required this.label,
    required this.semantics,
    required this.onTap,
  });

  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      button: true,
      label: semantics,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: DashedBox(
              color: t.ink.withValues(alpha: 0.65),
              radius: RegalosShape.chipRadius,
              strokeWidth: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
