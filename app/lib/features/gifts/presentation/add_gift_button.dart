import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_gutter.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import 'gift_editor_screen.dart';

/// Lo que hay que dejar libre al pie de una lista para que el botón (de 56 de
/// alto, solo icono) no tape su última fila: su alto, el margen de 16 de debajo
/// y otros 16. Con el botón extendido y letra grande, usa
/// [addGiftButtonClearance].
const double kAddGiftButtonClearance = 88;

/// Por debajo de esta altura (móvil en horizontal) el botón va solo con icono.
const double _kShortHeight = 500;

/// Con la letra a partir de este factor el botón va solo con icono.
const double _kLargeText = 1.4;

/// Si el botón va siempre en solo icono: poca altura o letra muy grande.
bool addGiftButtonCompact(BuildContext context) {
  final media = MediaQuery.of(context);
  return media.size.height < _kShortHeight ||
      media.textScaler.scale(14) / 14 >= _kLargeText;
}

/// El hueco que una lista deja al pie para el botón «Añadir regalo», según su
/// tamaño real: el del botón extendido crece con la letra (la línea del nombre
/// más el relleno, con 56 como mínimo); en solo icono son 56.
double addGiftButtonClearance(BuildContext context) {
  if (addGiftButtonCompact(context)) {
    return kAddGiftButtonClearance;
  }
  final line = MediaQuery.textScalerOf(context).scale(14) * 1.4;
  return 32 + math.max(56, line + 24);
}

/// Recoge lo que se desplaza la lista de debajo para que el botón se encoja a
/// solo icono al bajar y vuelva a extenderse al subir. Envuelve el `Scaffold`
/// que lleva el [AddGiftButton].
class AddGiftFabScope extends StatefulWidget {
  /// Crea el ámbito.
  const AddGiftFabScope({super.key, required this.child});

  /// El `Scaffold` con el botón.
  final Widget child;

  @override
  State<AddGiftFabScope> createState() => _AddGiftFabScopeState();
}

class _AddGiftFabScopeState extends State<AddGiftFabScope> {
  final ValueNotifier<bool> _extended = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _extended.dispose();
    super.dispose();
  }

  /// Lo recorrido en el sentido actual (positivo, hacia abajo).
  double _run = 0;

  /// Lo que hay que recorrer en un sentido para encoger o extender el botón;
  /// así vale también el desplazamiento lento o el del trackpad.
  static const double _threshold = 24;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) {
      return false;
    }
    if (n is ScrollUpdateNotification) {
      final delta = n.scrollDelta ?? 0;
      if (n.metrics.pixels <= 8) {
        _extended.value = true;
        _run = 0;
      } else if (delta != 0) {
        if (delta.sign != _run.sign) {
          _run = 0;
        }
        _run += delta;
        if (_run > _threshold) {
          _extended.value = false;
        } else if (_run < -_threshold) {
          _extended.value = true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => _FabExtent(
    extended: _extended,
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: widget.child,
    ),
  );
}

class _FabExtent extends InheritedWidget {
  const _FabExtent({required this.extended, required super.child});

  final ValueNotifier<bool> extended;

  @override
  bool updateShouldNotify(_FabExtent old) => old.extended != extended;
}

/// El botón «Añadir regalo» de las pestañas Personas y Ocasiones: un rectángulo
/// de radio 8 con el «+» y el nombre, abajo a la derecha, que abre el editor
/// con la elección de persona arriba.
///
/// Se pone en `Scaffold.floatingActionButton`: respeta el área segura, se
/// aparta de los avisos y, en tablet, se queda a 16 del borde de la columna y
/// no del panel. El nombre va escrito (no solo el «+») para no confundirse con
/// el «+» de la cabecera, que añade personas u ocasiones.
class AddGiftButton extends ConsumerWidget {
  /// Crea el botón.
  const AddGiftButton({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    ref.read(hapticsProvider).light();
    final id = await openGiftEditor(context, chooseRecipient: true);
    if (id == null || !context.mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final view = ref.read(familyFullViewProvider);
    final gift = view.gifts.where((g) => g.id == id).firstOrNull;
    final person = gift == null ? null : view.recipientsById[gift.recipientId];
    if (person == null) {
      return;
    }
    // El aviso lleva a la lista de esa persona: ahí se ve el regalo.
    showRegalosSnackBar(
      context,
      SnackBar(
        persist: false,
        content: Text(l10n.giftAddedNotice(person.name)),
        action: SnackBarAction(
          label: l10n.giftAddedView,
          onPressed: () => context.go('/people/${person.id}'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final compact = addGiftButtonCompact(context);
    final extended = context
        .getInheritedWidgetOfExactType<_FabExtent>()
        ?.extended;
    // Extendido (con el nombre) o solo el «+»: el cambio es animado. Con poca
    // altura o letra muy grande va siempre en solo icono; el nombre sigue en
    // el aviso y en la etiqueta de accesibilidad.
    Widget button(bool wide) {
      final isExtended = wide && !compact;
      return Semantics(
        // Sin el nombre a la vista, el lector de pantalla sigue leyéndolo.
        label: isExtended ? null : l10n.giftAdd,
        child: FloatingActionButton.extended(
          heroTag: null,
          tooltip: l10n.giftAdd,
          isExtended: isExtended,
          onPressed: () => _open(context, ref),
          shape: const RoundedRectangleBorder(borderRadius: RegalosShape.fab),
          icon: StrokeIcon(
            AppIcons.plus,
            size: 22,
            color: t.onFill,
            strokeWidth: 2.4,
          ),
          label: Text(
            l10n.giftAdd,
            style: t.styles.label.copyWith(
              color: t.onFill,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return ContentFloatingButton(
      maxWidth: RegalosLayout.listColumn,
      child: extended == null
          ? button(true)
          : ValueListenableBuilder<bool>(
              valueListenable: extended,
              builder: (context, value, _) => button(value),
            ),
    );
  }
}
