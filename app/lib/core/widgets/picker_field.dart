import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/haptics.dart';
import '../motion/pop_in.dart';
import '../motion/sheet_motion.dart';
import '../motion/stagger.dart';
import '../motion/value_switcher.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'section_header.dart';
import 'stroke_icon.dart';

/// Una opción de [PickerField] y de [showPickerSheet].
@immutable
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.label,
    this.leading,
    this.group,
    this.hint,
    this.enabled = true,
  });

  /// El valor que se devuelve al elegirla.
  final T value;

  /// El texto que se ve y que lee el lector de pantalla.
  final String label;

  /// Lo que va delante del texto (punto, icono, inicial). Es decorativo: el
  /// texto siempre va al lado. Debe caber en 28 x 28.
  final Widget? leading;

  /// Cabecera de sección bajo la que se muestra. Las opciones seguidas con el
  /// mismo grupo comparten cabecera; sin grupo no hay cabecera.
  final String? group;

  /// Una frase bajo el texto (por qué no se puede elegir, por ejemplo).
  final String? hint;

  /// Si se puede elegir. Deshabilitada se ve apagada, no se toca y el lector
  /// de pantalla la lee como no disponible.
  final bool enabled;
}

const double _rowHeight = 52;
const double _headerHeight = 40;

/// Abre una hoja inferior para elegir una de [options] y devuelve su valor, o
/// `null` si se cierra sin elegir. Crece hasta el 75 % de la pantalla y
/// después se desplaza.
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
}) => showRegalosSheet<T>(
  context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.75,
  ),
  builder: (_) =>
      _PickerSheet<T>(title: title, options: options, selected: selected),
);

/// Lo que se espera tras elegir para que se vea la opción antes de que la hoja
/// se vaya. La única pausa que permite la guía de movimiento.
const Duration _pickPause = Duration(milliseconds: 120);

/// Campo de formulario que enseña el valor elegido y, al tocarlo, abre una
/// hoja inferior con las opciones (sustituye al desplegable de Material).
class PickerField<T> extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.sheetTitle,
  });

  /// Etiqueta del campo (también el título de la hoja salvo [sheetTitle]).
  final String label;
  final List<PickerOption<T>> options;

  /// El valor elegido; si no está en [options] el campo sale vacío.
  final T? value;
  final ValueChanged<T> onChanged;
  final String? sheetTitle;

  PickerOption<T>? get _current {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showPickerSheet<T>(
      context,
      title: sheetTitle ?? label,
      options: options,
      selected: value,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final current = _current;
    return Semantics(
      button: true,
      label: current == null ? label : '$label, ${current.label}',
      excludeSemantics: true,
      onTap: () => _open(context),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: RegalosShape.field,
          onTap: () => _open(context),
          child: InputDecorator(
            isEmpty: current == null,
            decoration: InputDecoration(labelText: label),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 24),
              child: Row(
                children: [
                  Expanded(
                    // Al cambiar el valor, el nuevo entra subiendo 4 px y el
                    // viejo se va: 150 ms de fundido.
                    child: ValueSwitcher(
                      child: Row(
                        key: ValueKey(current?.label ?? ''),
                        children: [
                          if (current?.leading != null) ...[
                            current!.leading!,
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              current?.label ?? '',
                              style: t.styles.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StrokeIcon(
                    AppIcons.chevronDown,
                    size: 20,
                    color: t.text,
                    strokeWidth: 1.75,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<PickerOption<T>> options;
  final T? selected;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  late final ScrollController _scroll;

  /// La opción tocada, mientras se ve elegida antes de cerrar la hoja.
  T? _picked;
  bool _hasPicked = false;
  Timer? _pause;

  /// Elige una opción: el dato se entrega siempre; la pausa solo es para que
  /// se vea. Un segundo toque durante la pausa cierra al momento con ese valor.
  void _choose(T value) {
    if (_pause != null) {
      _pause!.cancel();
      _pause = null;
      Navigator.of(context).pop(value);
      return;
    }
    context.haptics.selection();
    setState(() {
      _picked = value;
      _hasPicked = true;
    });
    _pause = Timer(_pickPause, () {
      _pause = null;
      if (mounted) {
        Navigator.of(context).pop(value);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Con una lista larga se abre con la opción elegida a la vista.
    var offset = 0.0;
    String? lastGroup;
    for (final o in widget.options) {
      if (o.group != null && o.group != lastGroup) offset += _headerHeight;
      lastGroup = o.group;
      if (o.value == widget.selected) break;
      offset += _rowHeight;
    }
    _scroll = ScrollController(
      initialScrollOffset: math.max(0, offset - 2 * _rowHeight),
    );
  }

  @override
  void dispose() {
    _pause?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final shown = _hasPicked ? _picked : widget.selected;
    final children = <Widget>[];
    String? lastGroup;
    var index = 0;
    for (var i = 0; i < widget.options.length; i++) {
      final o = widget.options[i];
      final group = o.group;
      if (group != null && group != lastGroup) {
        final count = widget.options.where((x) => x.group == group).length;
        children.add(
          StaggerItem(
            index: index++,
            dy: 6,
            child: SectionHeader(
              title: group,
              trailing: '$count',
              bordered: false,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            ),
          ),
        );
      }
      lastGroup = group;
      children.add(
        StaggerItem(
          index: index++,
          dy: 6,
          child: _PickerRow<T>(
            option: o,
            selected: o.value == shown,
            justPicked: _hasPicked && o.value == _picked,
            onTap: () => _choose(o.value),
          ),
        ),
      );
    }
    // Las opciones entran escalonadas: 18 ms por fila desde los 60 ms.
    return StaggerScope(
      step: const Duration(milliseconds: 18),
      delay: const Duration(milliseconds: 60),
      child: _sheet(context, t, children),
    );
  }

  Widget _sheet(BuildContext context, RegalosTokens t, List<Widget> children) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Semantics(
              header: true,
              child: Text(widget.title, style: t.styles.screenTitleSmall),
            ),
          ),
          Divider(height: 1, thickness: 1, color: t.separator),
          Flexible(
            child: ListView(
              controller: _scroll,
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.option,
    required this.selected,
    required this.justPicked,
    required this.onTap,
  });

  final PickerOption<T> option;
  final bool selected;

  /// Si es la opción que se acaba de tocar: el check entra con rebote.
  final bool justPicked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final enabled = option.enabled;
    final hint = option.hint;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled ? null : false,
      selected: selected,
      label: hint == null ? option.label : '${option.label}. $hint',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Material(
        color: selected ? t.soft : Colors.transparent,
        // El fondo se tiñe del pastel en 120 ms al elegir.
        animationDuration: _pickPause,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _rowHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  if (option.leading != null) ...[
                    SizedBox.square(
                      dimension: 28,
                      child: Center(
                        child: Opacity(
                          opacity: enabled ? 1 : 0.5,
                          child: option.leading,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          option.label,
                          style: t.styles.body.copyWith(
                            fontWeight: selected ? FontWeight.w700 : null,
                            color: !enabled
                                ? t.textSecondary
                                : (selected ? t.textOnSoft : null),
                          ),
                        ),
                        if (hint != null) Text(hint, style: t.styles.meta),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 12),
                    // Al elegirla, el visto entra con rebote (desde 0,6) y
                    // fundido; con «Reducir movimiento», solo fundido.
                    PopIn(
                      animate: justPicked,
                      from: 0.6,
                      child: StrokeIcon(
                        AppIcons.check,
                        size: 22,
                        color: t.ink,
                        strokeWidth: 2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
