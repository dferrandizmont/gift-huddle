import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/family_providers.dart';
import 'protection_actions.dart';
import 'protection_texts.dart';

// Regalos pendientes de guardar o compartir (fase 3, lote 6): los que un móvil
// con derecho tiene cifrados solo en sí mismo porque no han cabido en el
// bloque secreto o en su cupo. La hoja los cuenta con claridad (si se pierde
// ese móvil, se pierden) y deja reintentar; el aviso discreto lleva a ella.

const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
  borderRadius: RegalosShape.button,
);

/// Abre la hoja de regalos pendientes. Con [personId] enseña solo los de esa
/// persona; sin él, los de todas.
Future<void> showPendingGiftsSheet(BuildContext context, {String? personId}) =>
    showRegalosSheet<void>(
      context,
      flat: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PendingGiftsSheet(personId: personId),
    );

/// Los pendientes de [personId] (o de todas las personas), ya leídos.
List<PendingProtectedGift> pendingOf(
  AsyncValue<List<PendingProtectedGift>> value,
  String? personId,
) => [
  for (final p in value.value ?? const <PendingProtectedGift>[])
    if (personId == null || p.personId == personId) p,
];

/// Aviso discreto «N regalos pendientes de guardar» con un «Ver» que abre la
/// hoja. No ocupa nada si no hay pendientes; aparece y se va con un
/// despliegue suave.
class PendingGiftsNotice extends ConsumerWidget {
  /// Crea el aviso; con [personId], solo de esa persona.
  const PendingGiftsNotice({
    super.key,
    this.personId,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  /// La persona, o `null` para todas.
  final String? personId;

  /// El hueco alrededor, cuando se ve.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = pendingOf(
      ref.watch(pendingProtectedGiftsProvider),
      personId,
    );
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final text = l10n.pendingGiftsNotice(pending.length);
    void open() => showPendingGiftsSheet(context, personId: personId);
    return UnfoldSection(
      show: pending.isNotEmpty,
      child: Padding(
        padding: padding,
        child: Semantics(
          container: true,
          liveRegion: true,
          button: true,
          label: '$text. ${l10n.pendingGiftsNoticeAction}',
          excludeSemantics: true,
          onTap: open,
          child: InkWell(
            onTap: open,
            borderRadius: RegalosShape.card,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: RegalosShape.card,
                border: Border.all(color: t.separator),
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: StrokeIcon(
                      SettingsIcons.lock,
                      size: 18,
                      color: t.textSecondary,
                      strokeWidth: 1.9,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: t.styles.meta)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      l10n.pendingGiftsNoticeAction,
                      style: t.styles.metaStrong.copyWith(color: t.text),
                    ),
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

/// El contenido de la hoja de regalos pendientes.
class PendingGiftsSheet extends ConsumerStatefulWidget {
  /// Crea la hoja; con [personId], solo de esa persona.
  const PendingGiftsSheet({super.key, this.personId});

  /// La persona, o `null` para todas.
  final String? personId;

  @override
  ConsumerState<PendingGiftsSheet> createState() => _PendingGiftsSheetState();
}

enum _Result { still, failed }

class _PendingGiftsSheetState extends ConsumerState<PendingGiftsSheet> {
  final Set<String> _busy = <String>{};
  final Map<String, _Result> _results = <String, _Result>{};

  Future<void> _retry(String personId) async {
    if (_busy.contains(personId)) return;
    setState(() {
      _busy.add(personId);
      _results.remove(personId);
    });
    _Result? result;
    try {
      await ref.read(protectionActionsProvider).retryPending(personId);
      ref.invalidate(pendingProtectedGiftsProvider);
      final after = await ref.read(pendingProtectedGiftsProvider.future);
      if (after.any((p) => p.personId == personId)) {
        result = _Result.still;
      }
    } on Object {
      result = _Result.failed;
    }
    if (!mounted) return;
    final haptics = ref.read(hapticsProvider);
    if (result == null) {
      haptics.success();
    } else {
      haptics.warning();
    }
    setState(() {
      _busy.remove(personId);
      if (result != null) _results[personId] = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final people = ref.watch(familyFullViewProvider).recipientsById;
    final pending = pendingOf(
      ref.watch(pendingProtectedGiftsProvider),
      widget.personId,
    );
    final byPerson = <String, List<PendingProtectedGift>>{};
    for (final p in pending) {
      byPerson.putIfAbsent(p.personId, () => []).add(p);
    }
    final done = pending.isEmpty;
    final Widget content;
    if (done) {
      content = Padding(
        key: const ValueKey<String>('pending-done'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SuccessMark(size: 56)),
              const SizedBox(height: 14),
              Text(
                l10n.pendingGiftsDoneTitle,
                textAlign: TextAlign.center,
                style: t.styles.screenTitleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.pendingGiftsDoneBody,
                textAlign: TextAlign.center,
                style: t.styles.body.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
      );
    } else {
      content = Padding(
        key: const ValueKey<String>('pending-list'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.pendingGiftsIntro,
              style: t.styles.body.copyWith(color: t.textSecondary),
            ),
            for (final entry in byPerson.entries) ...[
              const SizedBox(height: 16),
              _PersonGroup(
                personId: entry.key,
                name: people[entry.key]?.name ?? '',
                colorIndex: people[entry.key]?.colorIndex ?? 0,
                gifts: entry.value,
                busy: _busy.contains(entry.key),
                result: _results[entry.key],
                onRetry: () => _retry(entry.key),
              ),
            ],
          ],
        ),
      );
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(title: l10n.pendingGiftsTitle),
            SheetSteps(step: done ? 'done' : 'list', child: content),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.text,
                  minimumSize: const Size(44, 48),
                  side: BorderSide(color: t.controlBorder),
                  shape: _buttonShape,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionClose),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Los pendientes de una persona, con su motivo y su «Reintentar».
class _PersonGroup extends StatelessWidget {
  const _PersonGroup({
    required this.personId,
    required this.name,
    required this.colorIndex,
    required this.gifts,
    required this.busy,
    required this.result,
    required this.onRetry,
  });

  final String personId;
  final String name;
  final int colorIndex;
  final List<PendingProtectedGift> gifts;
  final bool busy;
  final _Result? result;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reason = protectionReasonText(l10n, gifts.first.reason, name);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
          border: Border.all(color: t.separator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PersonAvatar(name: name, colorIndex: colorIndex, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      name,
                      style: t.styles.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final p in gifts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  p.gift.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.styles.body,
                ),
              ),
            const SizedBox(height: 6),
            Text(reason, style: t.styles.meta),
            UnfoldSection(
              show: result != null,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    result == _Result.failed
                        ? l10n.pendingGiftsRetryError
                        : l10n.pendingGiftsStill,
                    style: t.styles.meta.copyWith(color: t.text),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: ValueKey<String>('pending-retry:$personId'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 48),
                shape: _buttonShape,
              ),
              onPressed: busy ? null : onRetry,
              child: Text(
                busy ? l10n.pendingGiftsRetrying : l10n.pendingGiftsRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
