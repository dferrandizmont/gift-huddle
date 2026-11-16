import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/family_device_review.dart';
import '../../sync/application/family_devices.dart' show FamilyDeviceRow;
import '../../sync/application/pairing_v2_controller.dart';

// Hojas de «Móviles de la familia» (fase 3, lote 2): el detalle de un móvil,
// con quitarlo o aprobarlo, y la bandeja «Revisar móviles». Todo es de un solo
// móvil a la vez: nunca se aprueba ni se quita en bloque.

/// El nombre con que se enseña un móvil: la persona, si la tiene y se
/// conoce; si no, el nombre del móvil; si tampoco, «Otro móvil» (o «Este
/// móvil» para el propio). Una web se llama «Web de Nora» (o «Web»).
String deviceTitle(
  AppLocalizations l10n,
  FamilyDeviceRow row, {
  required Map<String, String> people,
  required String selfName,
}) {
  final person = people[row.personId]?.trim();
  if (row.isWeb) {
    return person != null && person.isNotEmpty
        ? l10n.devicesWebOf(person)
        : l10n.devicesWebTitle;
  }
  final deviceName = (row.isSelf ? selfName : row.deviceName)?.trim();
  final fallback = row.isSelf ? l10n.devicesThisPhone : l10n.devicesOtherPhone;
  return person != null && person.isNotEmpty
      ? person
      : (deviceName != null && deviceName.isNotEmpty ? deviceName : fallback);
}

/// La frase del estado de un móvil en la lista y en su hoja.
String deviceStatusLabel(AppLocalizations l10n, FamilyDeviceStatus status) =>
    switch (status) {
      FamilyDeviceStatus.active => l10n.deviceStatusActive,
      FamilyDeviceStatus.noPerson => l10n.deviceStatusNoPerson,
      FamilyDeviceStatus.reconfirm => l10n.deviceStatusReconfirm,
      FamilyDeviceStatus.pending => l10n.deviceStatusPending,
      FamilyDeviceStatus.frozen => l10n.deviceStatusFrozen,
    };

/// Cómo acaba una hoja de móvil, para que la pantalla avise o siga.
enum DeviceSheetResult {
  /// Se aprobó el móvil.
  approved,

  /// Se quitó el móvil.
  removed,

  /// Se quitó y quedaron móviles sueltos por confirmar: sigue la bandeja.
  removedWithOrphans,

  /// Se quitó de este móvil pero falta cortar su acceso en el servidor: se
  /// hará con la siguiente conexión.
  removedCutPending,

  /// Lo mismo, y además quedaron móviles sueltos por confirmar.
  removedCutPendingWithOrphans,
}

/// Abre la hoja de [entry] (su detalle, con quitarlo o aprobarlo). [people]
/// son los nombres por id de persona.
Future<DeviceSheetResult?> showDeviceDetailSheet(
  BuildContext context, {
  required FamilyDeviceEntry entry,
  required Map<String, String> people,
  required String selfName,
}) => showRegalosSheet<DeviceSheetResult>(
  context,
  flat: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _DeviceSheet(entry: entry, people: people, selfName: selfName),
);

/// Abre la bandeja «Revisar móviles».
Future<void> showDeviceReviewSheet(
  BuildContext context, {
  required Map<String, String> people,
}) => showRegalosSheet<void>(
  context,
  flat: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ReviewSheet(people: people),
);

// --------------------------------------------------------------- acciones

enum _Outcome {
  cancelled,
  done,

  /// Quitado aquí, falta cortar el acceso en el servidor.
  cutPending,

  /// La ficha que se enseñó ya no es la del móvil: hay que volver a mirar.
  changed,
  failed,
}

enum _Fail { none, approve, remove }

/// El resultado de «Permitir desbloquear otra vez» en la hoja de una web.
enum _Resume { none, done, failed }

/// Aviso N7 (si toca), consecuencias y, al confirmar, quita [deviceId].
/// Los huérfanos quedan recordados para la bandeja.
Future<(_Outcome, List<DeviceReviewItem>)> _removeFlow(
  BuildContext context,
  WidgetRef ref,
  String deviceId, {
  bool retried = false,
  bool web = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final actions = ref.read(familyDeviceActionsProvider);
  final haptics = ref.read(hapticsProvider);
  final DeviceRemovalPreview preview;
  try {
    preview = await actions.previewRemoval(deviceId);
  } on Object {
    haptics.error();
    return (_Outcome.failed, const <DeviceReviewItem>[]);
  }
  if (!context.mounted) return (_Outcome.cancelled, const <DeviceReviewItem>[]);
  if (preview.selfWouldWait) {
    haptics.warning();
    final go = await showRegalosConfirm(
      context,
      title: l10n.deviceRemoveWaitTitle,
      body: l10n.deviceRemoveWaitBody,
      confirmLabel: l10n.deviceRemoveWaitAction,
      cancelLabel: l10n.actionCancel,
    );
    if (!go || !context.mounted) {
      return (_Outcome.cancelled, const <DeviceReviewItem>[]);
    }
  }
  haptics.warning();
  final sure = await showRegalosConfirm(
    context,
    title: web
        ? l10n.deviceRemoveWebConfirmTitle
        : l10n.deviceRemoveConfirmTitle,
    body: web ? l10n.deviceRemoveWebConfirmBody : l10n.deviceRemoveConfirmBody,
    confirmLabel: web
        ? l10n.deviceRemoveWebConfirmAction
        : l10n.deviceRemoveConfirmAction,
    cancelLabel: l10n.actionCancel,
  );
  if (!sure || !context.mounted) {
    return (_Outcome.cancelled, const <DeviceReviewItem>[]);
  }
  try {
    final orphans = await actions.remove(
      deviceId,
      selfWaitAccepted: preview.selfWouldWait,
    );
    haptics.success();
    return (_Outcome.done, orphans);
  } on DeviceRemovalChangedException {
    // Entre el aviso y el botón cambió la situación: se pregunta de nuevo.
    if (retried || !context.mounted) {
      haptics.error();
      return (_Outcome.failed, const <DeviceReviewItem>[]);
    }
    return _removeFlow(context, ref, deviceId, retried: true, web: web);
  } on DeviceRemovalPendingException catch (e) {
    haptics.warning();
    return (_Outcome.cutPending, e.orphans);
  } on Object {
    haptics.error();
    return (_Outcome.failed, const <DeviceReviewItem>[]);
  }
}

Future<_Outcome> _approveFlow(WidgetRef ref, DeviceReviewItem item) async {
  final haptics = ref.read(hapticsProvider);
  try {
    await ref
        .read(familyDeviceActionsProvider)
        .approve(item.deviceId, recordDigest: item.recordDigest);
    haptics.success();
    return _Outcome.done;
  } on DeviceRecordChangedException {
    haptics.warning();
    return _Outcome.changed;
  } on Object {
    haptics.error();
    return _Outcome.failed;
  }
}

String _reasonText(AppLocalizations l10n, DeviceReviewItem item) {
  final base = switch (item.reason) {
    DeviceReviewReason.newcomer => l10n.deviceApproveNewcomer,
    DeviceReviewReason.personChanged => l10n.deviceApprovePersonChanged,
    DeviceReviewReason.orphan => l10n.deviceApproveOrphan,
    DeviceReviewReason.detached => l10n.deviceApproveDetached,
    DeviceReviewReason.frozen => l10n.deviceApproveFrozen,
  };
  // Una ficha con cambios de persona, sea cual sea el motivo de la revisión,
  // al aprobarla da derecho a avalar a otros móviles.
  return item.canVouch && item.reason != DeviceReviewReason.personChanged
      ? '$base ${l10n.deviceApproveCanVouch}'
      : base;
}

// ------------------------------------------------------- piezas comunes

/// «¿Este móvil es de Leo?» con su explicación, aprobar, quitar y, si se da,
/// «Después». Es el mismo cuerpo en la hoja de un móvil y en la bandeja.
class _ReviewBody extends StatelessWidget {
  const _ReviewBody({
    required this.item,
    required this.personName,
    required this.busy,
    required this.error,
    this.notice,
    required this.onApprove,
    required this.onRemove,
    this.onLater,
  });

  final DeviceReviewItem item;
  final String? personName;
  final bool busy;
  final String? error;
  final String? notice;
  final VoidCallback onApprove;
  final VoidCallback onRemove;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    const buttonShape = RoundedRectangleBorder(
      borderRadius: RegalosShape.button,
    );
    final named = personName != null && personName!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _reasonText(l10n, item),
            style: t.styles.body.copyWith(color: t.textSecondary),
          ),
          if (notice != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                notice!,
                style: t.styles.meta.copyWith(color: t.text),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: t.styles.meta.copyWith(color: t.danger),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 48),
              shape: buttonShape,
            ),
            onPressed: busy ? null : onApprove,
            child: Text(
              named
                  ? l10n.deviceApproveYes(personName!)
                  : l10n.deviceApproveYesNoPerson,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 48),
              backgroundColor: t.dangerSoft,
              foregroundColor: t.danger,
              shape: buttonShape,
            ),
            onPressed: busy ? null : onRemove,
            child: Text(l10n.deviceRemoveTitle),
          ),
          if (onLater != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text,
                minimumSize: const Size(44, 48),
                side: BorderSide(color: t.controlBorder),
                shape: buttonShape,
              ),
              onPressed: busy ? null : onLater,
              child: Text(l10n.deviceApproveLater),
            ),
          ],
        ],
      ),
    );
  }
}

String _question(AppLocalizations l10n, String? personName) =>
    personName != null && personName.isNotEmpty
    ? l10n.deviceApproveQuestion(personName)
    : l10n.deviceApproveQuestionNoPerson;

// --------------------------------------------------- hoja de un móvil

enum _Step { detail, review }

class _DeviceSheet extends ConsumerStatefulWidget {
  const _DeviceSheet({
    required this.entry,
    required this.people,
    required this.selfName,
  });

  final FamilyDeviceEntry entry;
  final Map<String, String> people;
  final String selfName;

  @override
  ConsumerState<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends ConsumerState<_DeviceSheet> {
  _Step _step = _Step.detail;
  bool _back = false;
  bool _busy = false;
  _Fail _failed = _Fail.none;
  // La ficha que se está enseñando: lo que se avala es esa, no otra.
  late DeviceReviewItem? _item = widget.entry.review;
  bool _changed = false;
  _Resume _resumed = _Resume.none;

  void _go(_Step step, {bool back = false}) => setState(() {
    _step = step;
    _back = back;
    _failed = _Fail.none;
  });

  // La persona de la ficha que se va a firmar: si hay ficha en pantalla, es
  // la suya aunque no tenga persona (nunca se recupera la anterior).
  String? get _person {
    final item = _item;
    final id = item != null ? item.personId : widget.entry.row.personId;
    return widget.people[id]?.trim();
  }

  // El móvil publicó otra ficha mientras la hoja estaba abierta: se enseña la
  // nueva, con aviso, y se vuelve a preguntar.
  void _showChanged(DeviceReviewItem current) => setState(() {
    _item = current;
    _changed = true;
    _busy = false;
    _step = _Step.review;
    _back = false;
    _failed = _Fail.none;
  });

  Future<void> _reread() async {
    ref.invalidate(deviceReviewProvider);
    DeviceReview? review;
    try {
      review = await ref.read(deviceReviewProvider.future);
    } on Object {
      review = null;
    }
    if (!mounted) return;
    final current = review?.of(widget.entry.row.deviceId);
    if (current != null) {
      _showChanged(current);
    } else {
      setState(() {
        _busy = false;
        _failed = _Fail.approve;
      });
    }
  }

  Future<void> _remove() async {
    setState(() {
      _busy = true;
      _failed = _Fail.none;
    });
    final (outcome, orphans) = await _removeFlow(
      context,
      ref,
      widget.entry.row.deviceId,
      web: widget.entry.row.isWeb,
    );
    if (!mounted) return;
    switch (outcome) {
      case _Outcome.done:
        Navigator.of(context).pop(
          orphans.isEmpty
              ? DeviceSheetResult.removed
              : DeviceSheetResult.removedWithOrphans,
        );
      case _Outcome.cutPending:
        Navigator.of(context).pop(
          orphans.isEmpty
              ? DeviceSheetResult.removedCutPending
              : DeviceSheetResult.removedCutPendingWithOrphans,
        );
      case _Outcome.cancelled:
        setState(() => _busy = false);
      case _Outcome.changed:
      case _Outcome.failed:
        setState(() {
          _busy = false;
          _failed = _Fail.remove;
        });
    }
  }

  /// Quita la suspensión de la guarda de esta web (con confirmación). No
  /// borra nada ni cambia ningún secreto.
  Future<void> _resumeWeb() async {
    final l10n = AppLocalizations.of(context);
    ref.read(hapticsProvider).warning();
    final go = await showRegalosConfirm(
      context,
      title: l10n.deviceWebResumeTitle,
      body: l10n.deviceWebResumeBody,
      confirmLabel: l10n.deviceWebResumeConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!go || !mounted) return;
    setState(() {
      _busy = true;
      _resumed = _Resume.none;
    });
    var result = _Resume.done;
    try {
      await ref
          .read(pairingV2HostProvider.notifier)
          .resumeWebUnlock(widget.entry.row.deviceId);
    } on Object {
      result = _Resume.failed;
    }
    if (!mounted) return;
    final haptics = ref.read(hapticsProvider);
    result == _Resume.done ? haptics.success() : haptics.error();
    setState(() {
      _busy = false;
      _resumed = result;
    });
  }

  Future<void> _approve(DeviceReviewItem item) async {
    setState(() {
      _busy = true;
      _failed = _Fail.none;
    });
    final outcome = await _approveFlow(ref, item);
    if (!mounted) return;
    if (outcome == _Outcome.done) {
      Navigator.of(context).pop(DeviceSheetResult.approved);
    } else if (outcome == _Outcome.changed) {
      await _reread();
    } else {
      setState(() {
        _busy = false;
        _failed = _Fail.approve;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final entry = widget.entry;
    final name = deviceTitle(
      l10n,
      entry.row,
      people: widget.people,
      selfName: widget.selfName,
    );
    final status = deviceStatusLabel(l10n, entry.status);
    final review = _item;
    ref.listen(deviceReviewProvider, (previous, next) {
      final shown = _item;
      final current = next.value?.of(widget.entry.row.deviceId);
      if (shown != null &&
          current != null &&
          current.recordDigest != shown.recordDigest) {
        _showChanged(current);
      }
    });
    final List<Widget> children;
    switch (_step) {
      case _Step.detail:
        children = [
          SheetHeading(title: name, subtitle: status),
          Divider(height: 1, thickness: 1, color: t.separator),
          SettingsRow(
            title: l10n.deviceDetailOwner,
            value: _person != null && _person!.isNotEmpty
                ? _person
                : l10n.deviceDetailNoPerson,
            chevron: false,
          ),
          SettingsRow(
            title: l10n.deviceDetailStatus,
            value: status,
            chevron: false,
          ),
          if (entry.isSelf)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.deviceDetailSelfNote,
                style: t.styles.body.copyWith(color: t.textSecondary),
              ),
            )
          else ...[
            // Una web no se aprueba ni cambia de persona desde esta hoja: solo
            // se le puede quitar la suspensión o quitarla.
            if (entry.row.isWeb) ...[
              SettingsRow(
                icon: SettingsIcons.refresh,
                title: l10n.deviceWebResume,
                hint: l10n.deviceWebResumeHint,
                chevron: false,
                onTap: _busy ? null : _resumeWeb,
              ),
              if (_resumed != _Resume.none)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _resumed == _Resume.done
                          ? l10n.deviceWebResumeDone
                          : l10n.deviceWebResumeError,
                      style: t.styles.meta.copyWith(
                        color: _resumed == _Resume.done ? t.text : t.danger,
                      ),
                    ),
                  ),
                ),
            ] else if (review != null)
              SettingsRow(
                icon: SettingsIcons.shield,
                title: l10n.deviceApproveYesNoPerson,
                onTap: _busy ? null : () => _go(_Step.review),
              ),
            SettingsRow(
              icon: SettingsIcons.leave,
              title: entry.row.isWeb
                  ? l10n.deviceRemoveWebTitle
                  : l10n.deviceRemoveTitle,
              hint: entry.row.isWeb
                  ? l10n.deviceRemoveWebHint
                  : l10n.deviceRemoveHint,
              danger: true,
              chevron: false,
              onTap: _busy ? null : _remove,
            ),
            if (_failed == _Fail.remove)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    entry.row.isWeb
                        ? l10n.deviceRemoveWebError
                        : l10n.deviceRemoveError,
                    style: t.styles.meta.copyWith(color: t.danger),
                  ),
                ),
              ),
          ],
        ];
      case _Step.review:
        children = [
          SheetHeading(
            title: _question(l10n, _person),
            backLabel: l10n.backTo(name),
            onBack: () => _go(_Step.detail, back: true),
          ),
          _ReviewBody(
            item: review!,
            personName: _person,
            busy: _busy,
            notice: _changed ? l10n.deviceChangedNotice : null,
            error: _failed == _Fail.none
                ? null
                : (_failed == _Fail.approve
                      ? l10n.deviceApproveError
                      : l10n.deviceRemoveError),
            onApprove: () => _approve(review),
            onRemove: _remove,
          ),
        ];
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: SheetSteps(
          step: _step,
          back: _back,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- bandeja

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.people});

  final Map<String, String> people;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  // Cuántos se han dejado «para después» en esta vuelta: el actual es el
  // siguiente del orden de la bandeja, dando la vuelta.
  int _offset = 0;
  bool _busy = false;
  _Fail _failed = _Fail.none;
  bool _resolved = false;
  // Móviles cuya ficha cambió mientras la bandeja estaba abierta.
  final Set<String> _changedIds = {};
  String? _notice;

  Future<void> _after(
    Future<_Outcome> action,
    _Fail onFail, {
    String? deviceId,
  }) async {
    setState(() {
      _busy = true;
      _failed = _Fail.none;
      _notice = null;
    });
    final outcome = await action;
    if (!mounted) return;
    if (outcome == _Outcome.changed && deviceId != null) {
      // Otra ficha: se vuelve a leer y se pregunta de nuevo con aviso.
      _changedIds.add(deviceId);
      ref.invalidate(deviceReviewProvider);
    }
    if (outcome == _Outcome.cutPending) {
      _notice = AppLocalizations.of(context).deviceRemovedPendingSnack;
    }
    if (outcome == _Outcome.done || outcome == _Outcome.cutPending) {
      _resolved = true;
      // Espera a que la bandeja se vuelva a leer: el siguiente móvil entra
      // cuando ya no está el que se acaba de resolver.
      try {
        await ref.read(deviceReviewProvider.future);
      } on Object {
        // Se muestra lo último que se sabía.
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = outcome == _Outcome.failed ? onFail : _Fail.none;
    });
  }

  Future<void> _remove(DeviceReviewItem item) => _after(
    () async {
      final (outcome, _) = await _removeFlow(context, ref, item.deviceId);
      return outcome;
    }(),
    _Fail.remove,
    deviceId: item.deviceId,
  );

  void _later(int count) {
    if (count <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _offset++;
      _failed = _Fail.none;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final review = ref.watch(deviceReviewProvider).value ?? DeviceReview.empty;
    ref.listen(deviceReviewProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before == null || after == null) return;
      for (final item in after.items) {
        final old = before.of(item.deviceId);
        if (old != null && old.recordDigest != item.recordDigest) {
          setState(() => _changedIds.add(item.deviceId));
        }
      }
    });
    final items = review.items;
    final index = items.isEmpty ? 0 : _offset % items.length;
    final current = items.isEmpty ? null : items[index];
    final Object step;
    final List<Widget> children;
    if (current == null) {
      step = 'done';
      children = [
        SheetHeading(title: l10n.deviceReviewOpen),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_resolved) const Center(child: SuccessMark(size: 56)),
              if (_resolved) const SizedBox(height: 14),
              Text(
                l10n.deviceReviewDoneTitle,
                textAlign: TextAlign.center,
                style: t.styles.screenTitleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.deviceReviewDoneBody,
                textAlign: TextAlign.center,
                style: t.styles.body.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.text,
                  minimumSize: const Size(44, 48),
                  side: BorderSide(color: t.controlBorder),
                  shape: const RoundedRectangleBorder(
                    borderRadius: RegalosShape.button,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionUnderstood),
              ),
            ],
          ),
        ),
      ];
    } else {
      step = current.deviceId;
      final person = widget.people[current.personId]?.trim();
      children = [
        SheetHeading(
          title: _question(l10n, person),
          subtitle: items.length > 1
              ? l10n.deviceReviewProgress(index + 1, items.length)
              : null,
        ),
        _ReviewBody(
          item: current,
          personName: person,
          busy: _busy,
          notice: _changedIds.contains(current.deviceId)
              ? l10n.deviceChangedNotice
              : _notice,
          error: _failed == _Fail.none
              ? null
              : (_failed == _Fail.approve
                    ? l10n.deviceApproveError
                    : l10n.deviceRemoveError),
          onApprove: () => _after(
            _approveFlow(ref, current),
            _Fail.approve,
            deviceId: current.deviceId,
          ),
          onRemove: () => _remove(current),
          onLater: () => _later(items.length),
        ),
      ];
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: SheetSteps(
          step: step,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
