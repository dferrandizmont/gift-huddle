import 'package:flutter/material.dart';

import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';

// Hojas del cambio de «Este móvil es de» en una familia v2 (fase 3, lote 3b;
// ADR 0004, «Cambiar de persona»): lo que se pierde de vista antes de
// confirmar, la espera de aprobación después y el aviso de que ya no quedan
// cambios. Cambiar de persona afecta a lo que ven los demás móviles, no solo
// al nombre.

const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
  borderRadius: RegalosShape.button,
);

Widget _ghost(
  RegalosTokens t,
  String label,
  VoidCallback onPressed, {
  Key? key,
}) => OutlinedButton(
  key: key,
  style: OutlinedButton.styleFrom(
    foregroundColor: t.text,
    minimumSize: const Size(44, 48),
    side: BorderSide(color: t.controlBorder),
    shape: _buttonShape,
  ),
  onPressed: onPressed,
  child: Text(label),
);

/// Abre la hoja que explica qué pasa al cambiar de persona y pide confirmar.
/// [personName] es la persona nueva, o `null` para «Nadie». Devuelve `true`
/// solo si se confirma.
Future<bool> showSelfChangeConfirmSheet(
  BuildContext context, {
  required String? personName,
}) async {
  final confirmed = await showRegalosSheet<bool>(
    context,
    flat: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ConfirmSheet(personName: personName),
  );
  return confirmed ?? false;
}

/// Abre la hoja de «Esperando aprobación de otro móvil», tras cambiar de
/// persona. Con [hasOrphans] ofrece ir a «Revisar móviles». Devuelve `true`
/// si se pide revisar los móviles.
Future<bool> showSelfChangePendingSheet(
  BuildContext context, {
  required String? personName,
  required bool hasOrphans,
}) async {
  final review = await showRegalosSheet<bool>(
    context,
    flat: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _PendingSheet(personName: personName, hasOrphans: hasOrphans),
  );
  return review ?? false;
}

/// Abre el aviso de que este móvil ya no puede cambiar de persona.
Future<void> showSelfChangeExhaustedSheet(BuildContext context) =>
    showRegalosSheet<void>(
      context,
      flat: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ExhaustedSheet(),
    );

/// Una consecuencia: un cuadrito y la frase.
class _Effect extends StatelessWidget {
  const _Effect(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.personName});

  final String? personName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final name = personName;
    // Sin persona, otro móvil que lo apruebe no devuelve las sorpresas: la
    // espera no es el final del problema, así que no se promete.
    final effects = name == null
        ? [l10n.selfChangeEffectNobody, l10n.selfChangeEffectReconfirm]
        : [
            l10n.selfChangeEffectHides(name),
            l10n.selfChangeEffectWait,
            l10n.selfChangeEffectReconfirm,
          ];
    return SafeArea(
      top: false,
      child: StaggerScope(
        step: const Duration(milliseconds: 40),
        delay: const Duration(milliseconds: 80),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeading(title: l10n.selfChangeConfirmTitle),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      name == null
                          ? l10n.selfChangeConfirmIntroNobody
                          : l10n.selfChangeConfirmIntro(name),
                      style: t.styles.body.copyWith(color: t.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < effects.length; i++)
                            StaggerItem(
                              key: ValueKey<int>(i),
                              index: i,
                              dy: 6,
                              child: _Effect(effects[i]),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey<String>('selfChangeConfirm'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(44, 48),
                        shape: _buttonShape,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(l10n.selfChangeConfirmAction),
                    ),
                    const SizedBox(height: 8),
                    _ghost(
                      t,
                      l10n.actionCancel,
                      () => Navigator.of(context).pop(false),
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

class _PendingSheet extends StatelessWidget {
  const _PendingSheet({required this.personName, required this.hasOrphans});

  final String? personName;
  final bool hasOrphans;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final name = personName;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Padding(
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
                  l10n.selfChangePendingTitle,
                  textAlign: TextAlign.center,
                  style: t.styles.screenTitleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  name == null
                      ? l10n.selfChangePendingBodyNobody
                      : l10n.selfChangePendingBody(name),
                  textAlign: TextAlign.center,
                  style: t.styles.body.copyWith(color: t.textSecondary),
                ),
                if (hasOrphans) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.selfChangePendingOrphans,
                    textAlign: TextAlign.center,
                    style: t.styles.meta.copyWith(color: t.text),
                  ),
                ],
                const SizedBox(height: 16),
                if (hasOrphans) ...[
                  FilledButton(
                    key: const ValueKey<String>('selfChangeReview'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 48),
                      shape: _buttonShape,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l10n.deviceReviewOpen),
                  ),
                  const SizedBox(height: 8),
                  _ghost(
                    t,
                    l10n.deviceApproveLater,
                    () => Navigator.of(context).pop(false),
                  ),
                ] else
                  _ghost(
                    t,
                    l10n.actionUnderstood,
                    () => Navigator.of(context).pop(false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExhaustedSheet extends StatelessWidget {
  const _ExhaustedSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(title: l10n.selfChangeExhaustedTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.selfChangeExhaustedBody,
                      style: t.styles.body.copyWith(color: t.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ghost(
                    t,
                    l10n.actionUnderstood,
                    () => Navigator.of(context).pop(),
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
