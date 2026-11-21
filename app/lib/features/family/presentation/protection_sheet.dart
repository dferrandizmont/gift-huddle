import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/step_segments.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/sync/pairing_v2.dart'
    show kSyncProtocolV2, syncProtocolOf;
import '../../../core/sync/protected_doc.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/sync_controller.dart'
    show localRegistryReadProvider;
import '../application/family_controller.dart' show familyControllerProvider;
import '../application/family_providers.dart';
import '../data/family_store.dart' show familyStoreProvider;
import 'protection_actions.dart';
import 'protection_texts.dart';

// Regalos en secreto de una persona (fase 3, lote 6): la hoja que explica qué
// significa, en qué estado está (sin proteger, pedida o activa) y deja pedirla,
// confirmarla o quitarla. La lógica es de `application/person_protection.dart`;
// aquí solo se pide y se cuenta con lenguaje llano.

const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
  borderRadius: RegalosShape.button,
);

/// Abre la hoja de protección de la persona [personId].
Future<void> showProtectionSheet(
  BuildContext context, {
  required String personId,
}) => showRegalosSheet<void>(
  context,
  flat: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => ProtectionSheet(personId: personId),
);

/// Ofrece la hoja en familias móviles v2 aunque falle la verificación.
final protectionAvailableProvider = Provider<bool>((ref) {
  if (!ref.read(familyStoreProvider).supportsSecretScopes) return false;
  final family = ref.watch(familyControllerProvider).value;
  if (family?.identity == null) return false;
  final registry = ref.watch(localRegistryReadProvider);
  return syncProtocolOf(family!.doc) == kSyncProtocolV2 ||
      registry.hasError ||
      registry.value?.hasV2Identity == true;
});

/// La fila «Regalos en secreto» de la hoja de una persona y de su lista: el
/// estado de ahora a la derecha y, al tocarla, la hoja de protección. No sale
/// si la familia no admite regalos en secreto.
class ProtectionRow extends ConsumerWidget {
  /// Crea la fila de la persona [personId]. Con [onlyWhenProtected] solo sale
  /// si la protección está pedida o activa (la lista de una persona no ofrece
  /// activarla: eso se hace en su hoja).
  const ProtectionRow({
    super.key,
    required this.personId,
    this.onlyWhenProtected = false,
    this.padding = EdgeInsets.zero,
  });

  /// La persona.
  final String personId;

  /// Si solo se enseña con la protección pedida o activa.
  final bool onlyWhenProtected;

  /// El hueco alrededor, solo cuando la fila se ve.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(protectionAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final access = ref
        .watch(giftRecipientAccessProvider)
        .value
        ?.where((a) => a.recipient.id == personId)
        .firstOrNull;
    if (access == null || (onlyWhenProtected && !access.isProtected)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final name = access.recipient.name;
    final status = protectionStatusText(l10n, access.status);
    void open() => showProtectionSheet(context, personId: personId);
    return Padding(
      padding: padding,
      child: Semantics(
        container: true,
        button: true,
        label:
            '${l10n.protectionRowTitle}. ${l10n.protectionRowHint(name)} $status',
        excludeSemantics: true,
        onTap: open,
        child: InkWell(
          onTap: open,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: t.separator),
                bottom: BorderSide(color: t.separator),
              ),
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.soft,
                      borderRadius: RegalosShape.chip,
                    ),
                    child: StrokeIcon(
                      SettingsIcons.lock,
                      size: 20,
                      color: t.textOnSoft,
                      strokeWidth: 1.9,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.protectionRowTitle,
                        style: t.styles.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(l10n.protectionRowHint(name), style: t.styles.meta),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ValueSwitcher(
                  alignment: Alignment.centerRight,
                  child: Text(
                    status,
                    key: ValueKey<String>(status),
                    style: t.styles.metaStrong.copyWith(color: t.text),
                  ),
                ),
                const SizedBox(width: 4),
                StrokeIcon(
                  AppIcons.chevronRight,
                  color: t.textSecondary,
                  strokeWidth: 1.9,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El contenido de la hoja de protección.
class ProtectionSheet extends ConsumerStatefulWidget {
  /// Crea la hoja de la persona [personId].
  const ProtectionSheet({super.key, required this.personId});

  /// La persona.
  final String personId;

  @override
  ConsumerState<ProtectionSheet> createState() => _ProtectionSheetState();
}

class _ProtectionSheetState extends ConsumerState<ProtectionSheet> {
  bool _busy = false;
  String? _error;

  // El estado que se veía, para saber si el cambio avanza o vuelve atrás.
  PersonProtectionStatus? _shown;
  bool _back = false;

  Future<void> _run(
    Future<void> Function(ProtectionActions actions) action, {
    required String name,
    required bool success,
    bool ownPhone = false,
  }) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final haptics = ref.read(hapticsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await action(ref.read(protectionActionsProvider));
      if (success) {
        haptics.success();
      } else {
        haptics.medium();
      }
    } on ProtectedPersonException catch (e) {
      error = protectionReasonText(l10n, e.reason, name, ownPhone: ownPhone);
      haptics.error();
    } on Object {
      error = l10n.protectionChangeFailed;
      haptics.error();
    }
    if (!mounted) return;
    // Lo que se ve ahora lo da el proveedor; se vuelve a leer por si el
    // cambio acaba de llegar.
    ref.invalidate(giftRecipientAccessProvider);
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _deactivate(String name) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showRegalosConfirm(
      context,
      title: l10n.protectionDeactivateTitle(name),
      body: l10n.protectionDeactivateBody(name),
      confirmLabel: l10n.protectionDeactivateConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!ok || !mounted) return;
    await _run(
      (a) => a.deactivate(widget.personId),
      name: name,
      success: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final accessAsync = ref.watch(giftRecipientAccessProvider);
    // Mientras se vuelve a leer (por ejemplo, tras un rechazo) el valor
    // anterior sigue a la vista, pero sus acciones no se pueden pulsar.
    final reloading = accessAsync.isLoading;
    final access = accessAsync.value
        ?.where((a) => a.recipient.id == widget.personId)
        .firstOrNull;
    if (access == null) {
      return SafeArea(
        top: false,
        child: SizedBox(
          height: 160,
          child: Center(
            child: Semantics(
              header: true,
              child: Text(
                l10n.protectionRowTitle,
                style: t.styles.screenTitleSmall,
              ),
            ),
          ),
        ),
      );
    }
    final name = access.recipient.name;
    final status = access.status;
    final previous = _shown;
    if (previous != null && previous != status) {
      _back = status.index < previous.index;
    }
    _shown = status;

    Widget primary(String label, VoidCallback? onPressed, {Key? key}) =>
        FilledButton(
          key: key,
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 48),
            shape: _buttonShape,
          ),
          onPressed: _busy || reloading ? null : onPressed,
          child: Text(label),
        );

    final (title, body) = switch (status) {
      PersonProtectionStatus.unprotected => (
        l10n.protectionStatusOff,
        l10n.protectionRowHint(name),
      ),
      PersonProtectionStatus.requested => (
        l10n.protectionRequestedTitle,
        access.canConfirm
            ? l10n.protectionConfirmBody(name)
            : l10n.protectionWaitingBody(name),
      ),
      PersonProtectionStatus.active => (
        l10n.protectionActiveTitle,
        l10n.protectionActiveBody(name),
      ),
    };

    final Widget action = switch (status) {
      PersonProtectionStatus.unprotected =>
        access.canRequest
            ? primary(
                l10n.protectionRequest,
                () => _run(
                  (a) => a.request(widget.personId),
                  name: name,
                  success: true,
                  ownPhone: access.viewerIsRecipient,
                ),
                key: const ValueKey<String>('protectionRequest'),
              )
            : Text(
                protectionReasonText(
                  l10n,
                  access.requestReason ??
                      ProtectedPersonReason.registryUnavailable,
                  name,
                  ownPhone: access.viewerIsRecipient,
                ),
                key: const ValueKey<String>('protectionRequestHelp'),
                style: t.styles.meta,
              ),
      PersonProtectionStatus.requested =>
        access.canConfirm
            ? primary(
                l10n.protectionActivate,
                () => _run(
                  (a) => a.activate(widget.personId),
                  name: name,
                  success: true,
                ),
                key: const ValueKey<String>('protectionActivate'),
              )
            : const SizedBox.shrink(),
      PersonProtectionStatus.active =>
        access.canDeactivate
            ? OutlinedButton(
                key: const ValueKey<String>('protectionDeactivate'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.text,
                  minimumSize: const Size(44, 48),
                  side: BorderSide(color: t.controlBorder),
                  shape: _buttonShape,
                ),
                onPressed: _busy || reloading ? null : () => _deactivate(name),
                child: Text(l10n.protectionDeactivate),
              )
            : Text(l10n.protectionCannotDeactivate(name), style: t.styles.meta),
    };

    final effects = [
      l10n.protectionEffectOthers,
      l10n.protectionEffectKept(name),
      l10n.protectionEffectConfirm,
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(title: l10n.protectionSheetTitle(name)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.protectionIntro(name),
                    style: t.styles.body.copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  for (final e in effects) _Effect(e),
                  const SizedBox(height: 14),
                  StepSegments(
                    count: 2,
                    filled: status.index,
                    semanticLabel: switch (status) {
                      PersonProtectionStatus.unprotected =>
                        l10n.protectionStatusOff,
                      PersonProtectionStatus.requested =>
                        l10n.protectionRequestedTitle,
                      PersonProtectionStatus.active =>
                        l10n.protectionActiveTitle,
                    },
                  ),
                  const SizedBox(height: 12),
                  SheetSteps(
                    step: status,
                    back: _back,
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            style: t.styles.rowTitle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(body, style: t.styles.meta),
                          const SizedBox(height: 12),
                          action,
                        ],
                      ),
                    ),
                  ),
                  UnfoldSection(
                    show: _error != null,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: WarningBox(_error ?? ''),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.text,
                      minimumSize: const Size(44, 48),
                      side: BorderSide(color: t.controlBorder),
                      shape: _buttonShape,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionClose),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una consecuencia: un cuadrito y la frase.
class _Effect extends StatelessWidget {
  const _Effect(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 12),
            child: ExcludeSemantics(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: t.textSecondary,
                  borderRadius: BorderRadius.circular(1.5),
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
