import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/anchored_picker.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/picker_option.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/sync/pairing_v2.dart'
    show kSyncProtocolV2, syncProtocolOf;
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/self_recipient_provider.dart';
import '../../sharing/presentation/device_sheets.dart'
    show showDeviceReviewSheet;
import '../../sync/application/family_device_review.dart';
import '../../sync/application/family_device_rows.dart';
import '../../sync/application/sync_controller.dart'
    show localRegistryViewProvider;
import 'self_person_change_sheets.dart';

/// Lo que devuelve la hoja para «Nadie» (el proveedor lo guarda como `null`).
/// Un id de persona nunca está vacío.
const String _nobody = '';

/// Lado del avatar de cada persona en la hoja.
const double _avatarSize = 32;

/// Fila «Este móvil es de» de Ajustes (ADR 0004, «Yo»): enseña a la derecha
/// el nombre de la persona dueña de este móvil, o «Nadie», y abre la hoja
/// para cambiarla. Al volver, el valor nuevo entra desde abajo.
///
/// Sin familia v2 solo vale en este móvil. En una familia v2 con otros
/// móviles, cambiar de persona publica una ficha nueva que otro móvil debe
/// aprobar: antes se explica en una hoja y después se enseña la espera. Mientras
/// ese móvil no lo apruebe, la fila lo dice debajo.
class SelfRecipientRow extends ConsumerStatefulWidget {
  const SelfRecipientRow({super.key});

  @override
  ConsumerState<SelfRecipientRow> createState() => _SelfRecipientRowState();
}

class _SelfRecipientRowState extends ConsumerState<SelfRecipientRow> {
  // El foco de la fila: el desplegable lo devuelve aquí al cerrarse.
  final FocusNode _focus = FocusNode(debugLabel: 'SelfRecipientRow');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final self = ref.watch(selfRecipientProvider);
    final waiting = ref.watch(
      localRegistryViewProvider.select((v) {
        final view = v.value;
        return view != null && !view.selfApproved;
      }),
    );
    return SettingsRow(
      icon: SettingsIcons.phone,
      title: l10n.settingsSelf,
      value: self?.name ?? l10n.settingsSelfNobody,
      hint: waiting ? l10n.selfWaitingHint : null,
      focusNode: _focus,
      onTap: () => _change(context, ref, _focus),
    );
  }
}

/// Si cambiar de persona pide antes una explicación: la familia es v2 y hay
/// otros móviles. Si no se sabe leer la lista, se avisa por si acaso.
Future<bool> _needsWarning(WidgetRef ref) async {
  final family = ref.read(familyControllerProvider).value;
  if (family == null || syncProtocolOf(family.doc) != kSyncProtocolV2) {
    return false;
  }
  try {
    final rows = await ref.read(familyDeviceRowsProvider.future);
    return rows != null && rows.any((r) => !r.isSelf);
  } on Object {
    return true;
  }
}

Future<void> _change(
  BuildContext context,
  WidgetRef ref,
  FocusNode focus,
) async {
  final l10n = AppLocalizations.of(context);
  final picked = await _pickSelf(context, ref, focus);
  if (picked == null || !context.mounted) {
    return;
  }
  final next = picked == _nobody ? null : picked;
  if (next == ref.read(selfRecipientIdProvider)) {
    return;
  }
  final people = {
    for (final r in ref.read(familyFullViewProvider).recipients)
      r.id: r.name.trim(),
  };
  final name = next == null ? null : people[next];
  if (await _needsWarning(ref)) {
    if (!context.mounted) {
      return;
    }
    final go = await showSelfChangeConfirmSheet(context, personName: name);
    if (!go || !context.mounted) {
      return;
    }
  }
  final ChangeSelfPersonResult result;
  try {
    result = await ref.read(selfRecipientIdProvider.notifier).choose(next);
  } on SelfPersonSequenceExhaustedException {
    if (context.mounted) {
      await showSelfChangeExhaustedSheet(context);
    }
    return;
  } on Object {
    // No se guardó (el almacén seguro falló): la fila sigue como estaba y
    // se avisa.
    if (context.mounted) {
      showRegalosSnackBar(
        context,
        SnackBar(content: Text(l10n.settingsSelfError)),
      );
    }
    return;
  }
  if (result != ChangeSelfPersonResult.pendingApproval || !context.mounted) {
    return;
  }
  // Los móviles que quedan sueltos al cambiar de persona salen en la bandeja.
  var hasOrphans = false;
  try {
    final review = await ref.read(deviceReviewProvider.future);
    hasOrphans = review.items.any((i) => i.reason == DeviceReviewReason.orphan);
  } on Object {
    // Sin bandeja que leer, solo se enseña la espera.
  }
  if (!context.mounted) {
    return;
  }
  final openReview = await showSelfChangePendingSheet(
    context,
    personName: name,
    hasOrphans: hasOrphans,
  );
  if (openReview && context.mounted) {
    await showDeviceReviewSheet(context, people: people);
  }
}

/// Elige la persona de este móvil: en una ventana de escritorio con ratón, un
/// desplegable anclado a la fila (con la misma explicación encima de la
/// lista); en el móvil y con el dedo, la hoja ([showSelfRecipientSheet]).
Future<String?> _pickSelf(
  BuildContext context,
  WidgetRef ref,
  FocusNode focus,
) {
  if (!usesAnchoredPicker(context)) {
    return showSelfRecipientSheet(context);
  }
  final l10n = AppLocalizations.of(context);
  final current = ref.read(selfRecipientIdProvider) ?? _nobody;
  final family = ref.read(familyControllerProvider).value;
  final isV2 = family != null && syncProtocolOf(family.doc) == kSyncProtocolV2;
  final t = RegalosTokens.of(context);
  return showAnchoredPicker<String>(
    context,
    label: l10n.settingsSelfSheetTitle,
    description: isV2
        ? l10n.settingsSelfSheetHintV2
        : l10n.settingsSelfSheetHint,
    selected: current,
    options: [
      for (final r in ref.read(familyFullViewProvider).recipients)
        if (!r.archived || r.id == current)
          PickerOption<String>(
            value: r.id,
            label: r.name,
            leading: PersonAvatar(
              name: r.name,
              colorIndex: r.colorIndex,
              size: 28,
            ),
          ),
      PickerOption<String>(
        value: _nobody,
        label: l10n.settingsSelfNobody,
        // Un hueco vacío, con el trazo de «nada aún».
        leading: DashedBox(
          color: t.outline,
          radius: PersonAvatar.radiusFor(28),
          strokeWidth: 1.2,
          child: const SizedBox.square(dimension: 28),
        ),
      ),
    ],
    maxWidth: 360,
    alignEnd: true,
    returnFocusTo: focus,
  );
}

/// Abre la hoja «¿De quién es este móvil?»: las personas de la familia (sin
/// las archivadas, salvo la elegida) con su avatar, y al final «Nadie», con
/// un visto en la elegida. Devuelve el id tocado (vacío para «Nadie») o
/// `null` si se cierra sin elegir.
Future<String?> showSelfRecipientSheet(BuildContext context) =>
    showRegalosSheet<String>(
      context,
      flat: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SelfRecipientSheet(),
    );

class _SelfRecipientSheet extends ConsumerStatefulWidget {
  const _SelfRecipientSheet();

  @override
  ConsumerState<_SelfRecipientSheet> createState() =>
      _SelfRecipientSheetState();
}

class _SelfRecipientSheetState extends ConsumerState<_SelfRecipientSheet> {
  /// Lo que tarda la hoja en bajar sola tras elegir: deja ver el visto.
  static const Duration _closeDelay = Duration(milliseconds: 340);

  String? _picked;
  Timer? _close;

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  void _pick(String id) {
    if (_picked != null) {
      return;
    }
    setState(() => _picked = id);
    final reduce = RegalosMotion.of(context).reduce;
    _close = Timer(reduce ? RegalosMotion.fade : _closeDelay, () {
      if (mounted) {
        Navigator.of(context).pop(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final current = ref.watch(selfRecipientIdProvider) ?? _nobody;
    final family = ref.watch(familyControllerProvider).value;
    final isV2 =
        family != null && syncProtocolOf(family.doc) == kSyncProtocolV2;
    final selected = _picked ?? current;
    final people = [
      for (final r in ref.watch(familyFullViewProvider).recipients)
        if (!r.archived || r.id == current) r,
    ];
    var index = 0;
    return SafeArea(
      top: false,
      // Las opciones entran escalonadas, como en los selectores: 18 ms por
      // fila desde los 60 ms.
      child: StaggerScope(
        step: const Duration(milliseconds: 18),
        delay: const Duration(milliseconds: 60),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeading(
                title: l10n.settingsSelfSheetTitle,
                // En v2 la elección se publica y cambia lo que se ve: no se
                // dice que no se comparte.
                subtitle: isV2
                    ? l10n.settingsSelfSheetHintV2
                    : l10n.settingsSelfSheetHint,
              ),
              Semantics(
                container: true,
                explicitChildNodes: true,
                label: l10n.settingsSelfSheetTitle,
                child: Column(
                  children: [
                    Divider(height: 1, thickness: 1, color: t.separator),
                    for (final person in people)
                      StaggerItem(
                        key: ValueKey<String>(person.id),
                        index: index++,
                        dy: 6,
                        child: CheckOptionRow(
                          leading: PersonAvatar(
                            name: person.name,
                            colorIndex: person.colorIndex,
                            size: _avatarSize,
                          ),
                          title: person.name,
                          selected: person.id == selected,
                          drawCheck: person.id == _picked,
                          onTap: () => _pick(person.id),
                        ),
                      ),
                    StaggerItem(
                      key: const ValueKey<String>(_nobody),
                      index: index++,
                      dy: 6,
                      child: CheckOptionRow(
                        // Un hueco vacío, con el trazo de «nada aún».
                        leading: DashedBox(
                          color: t.outline,
                          radius: PersonAvatar.radiusFor(_avatarSize),
                          strokeWidth: 1.2,
                          child: const SizedBox.square(dimension: _avatarSize),
                        ),
                        title: l10n.settingsSelfNobody,
                        selected: selected == _nobody,
                        drawCheck: _picked == _nobody,
                        onTap: () => _pick(_nobody),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
