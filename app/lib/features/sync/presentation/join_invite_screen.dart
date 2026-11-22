import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/root_navigator.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/device/device_name.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/own_gifts_notice.dart'
    show markOwnGiftsHiddenSeen;
import '../../sharing/presentation/paired_sheet.dart';
import '../application/pairing_v2_controller.dart';
import '../data/sync_config.dart';
import '../invites/invite_guest.dart';
import '../invites/invite_link.dart';
import 'code_card.dart';
import 'pairing_v2_guest_view.dart';

/// Tracks joins opened from links, Settings or QR until their views unmount.
/// External links must not mount another view sharing the pairing controller.
class JoinInvitePresence {
  final _owners = <Object>{};

  bool get isActive => _owners.isNotEmpty;
}

final joinInvitePresenceProvider = Provider<JoinInvitePresence>(
  (ref) => JoinInvitePresence(),
);

/// Lo que dice la hoja final del móvil que entra (1.0.6): de quién es este
/// móvil y que no verá sus regalos, si se conoce el nombre de la persona que
/// eligió quien invitó; si aún no ha llegado la lista, la frase de siempre.
String joinedBody(WidgetRef ref, AppLocalizations l10n) {
  final id = ref.read(pairingV2GuestProvider).assignedPersonId;
  String? name;
  if (id != null) {
    final family = ref.read(familyControllerProvider).value;
    for (final r in family?.fullView.recipients ?? const []) {
      if (r.id == id && r.name.trim().isNotEmpty) name = r.name.trim();
    }
  }
  return name == null
      ? l10n.pairingV2GuestDoneBody
      : l10n.pairingV2GuestDoneFor(name);
}

/// Ajustes › Compartir › Unirme con un enlace: pega el enlace de invitación,
/// espera la aprobación, compara el código con quien invitó y entra.
class JoinInviteScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla. [initialInvite] es lo que ya se sabe del enlace (por
  /// ejemplo, el id que trajo un App Link): rellena el campo.
  const JoinInviteScreen({
    super.key,
    this.initialInvite,
    this.fromWelcome = false,
    this.fromQr = false,
    this.deviceName = '',
  });

  /// Si se abrió al leer un QR (1.0.6): el título no habla de enlaces.
  final bool fromQr;

  /// Si se abrió desde la bienvenida, antes de tener ninguna lista: la
  /// cabecera no habla de Ajustes › Compartir y «volver» vuelve a la
  /// bienvenida.
  final bool fromWelcome;

  /// Texto con el que se rellena el campo del enlace.
  final String? initialInvite;

  /// Nombre ya escrito o aceptado en la bienvenida o en el lector de QR.
  final String deviceName;

  @override
  ConsumerState<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

class _JoinInviteScreenState extends ConsumerState<JoinInviteScreen> {
  late final JoinInvitePresence _presence;
  late final TextEditingController _link = TextEditingController(
    text: widget.initialInvite ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.deviceName,
  );
  bool _dialogOpen = false;

  @override
  void dispose() {
    _presence._owners.remove(this);
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty && mounted) {
      setState(() => _link.text = text);
    }
  }

  void _ask() {
    FocusScope.of(context).unfocus();
    ref
        .read(inviteGuestProvider.notifier)
        .begin(_link.text, deviceName: deviceNameToSend(ref, _name.text));
  }

  Future<void> _askReplace() async {
    if (_dialogOpen) {
      return;
    }
    _dialogOpen = true;
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(inviteGuestProvider.notifier);
    final replace = await showRegalosConfirm(
      context,
      title: l10n.joinConflictTitle,
      body: l10n.joinConflictBody,
      confirmLabel: l10n.joinReplace,
      cancelLabel: l10n.actionCancel,
    );
    _dialogOpen = false;
    if (replace) {
      await controller.confirmReplace();
    } else {
      controller.reset();
    }
  }

  // ---- v2: se entra comparando un número (ADR 0004).

  /// El id de la invitación que ya se está abriendo en v2; null: se pide el
  /// enlace.
  String? _v2Invite;
  String? _v2Error;

  /// El nombre de este móvil tal como estaba al pulsar «Pedir entrada» (o el
  /// que ya venía confirmado): no se vuelve a leer del campo después, porque
  /// la sugerencia del modelo puede llegar en medio. Vacío también vale.
  String _v2Name = '';

  @override
  void initState() {
    super.initState();
    _presence = ref.read(joinInvitePresenceProvider);
    _presence._owners.add(this);
    final initial = widget.initialInvite;
    // Con el nombre ya escrito o aceptado (bienvenida, lector de QR) se abre la
    // invitación sin más. Con un enlace que llega solo (App Link) no: antes la
    // persona ve el campo del nombre de este móvil, con el modelo propuesto, y
    // pulsa «Pedir entrada». El enlace ya está en [_link].
    if (initial != null &&
        widget.deviceName.trim().isNotEmpty &&
        ref.read(pairingV2AvailableProvider)) {
      _v2Invite = _inviteIdOf(initial);
      _v2Name = deviceNameToSend(ref, widget.deviceName);
    }
  }

  String? _inviteIdOf(String text) {
    try {
      return parseInvite(
        text,
        expectedHost: ref.read(syncEndpointProvider)?.invitationHost,
      );
    } on InviteFormatException {
      return null;
    }
  }

  void _askV2() {
    FocusScope.of(context).unfocus();
    final id = _inviteIdOf(_link.text);
    final name = deviceNameToSend(ref, _name.text);
    setState(() {
      _v2Name = name;
      _v2Invite = id;
      _v2Error = id == null
          ? AppLocalizations.of(context).joinInviteBadLink
          : null;
    });
  }

  Widget _v2Body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final invite = _v2Invite;
    if (invite != null) {
      return PairingV2GuestView(
        key: ValueKey<String>(invite),
        inviteId: invite,
        deviceName: _v2Name,
        onDone: () {
          final body = joinedBody(ref, l10n);
          // La hoja final ya dice que no verá sus regalos: el aviso de una vez
          // no se repite.
          if (body != l10n.pairingV2GuestDoneBody) {
            markOwnGiftsHiddenSeen(ref.read(sharedPreferencesProvider));
          }
          unawaited(_finish(body));
        },
        onExit: () => setState(() => _v2Invite = null),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.joinInviteIntro, style: t.styles.body),
        const SizedBox(height: 16),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l10n.joinInviteFieldLabel,
            suffixIcon: TextButton(
              onPressed: _paste,
              child: Text(l10n.joinInvitePaste),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DeviceNameField(controller: _name),
        if (_v2Error != null) ...[
          const SizedBox(height: 12),
          Text(_v2Error!, style: t.styles.body),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: _askV2, child: Text(l10n.joinInviteAsk)),
      ],
    );
  }

  Future<void> _finish(String body) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    navigator.pop();
    router?.go('/people');
    await WidgetsBinding.instance.endOfFrame;
    final sheetContext =
        rootNavigatorKey.currentContext ?? navigator.overlay?.context;
    if (sheetContext != null && sheetContext.mounted) {
      // La misma hoja de éxito que al emparejar con el QR (momento L).
      await showPairedSheet(
        sheetContext,
        title: l10n.joinDoneTitle,
        body: body,
      );
    }
  }

  String? _errorText(AppLocalizations l10n, InviteGuestState s) {
    switch (s.phase) {
      case JoinPhase.gone:
        return l10n.joinInviteGone;
      case JoinPhase.taken:
        return l10n.joinInviteTaken;
      case JoinPhase.mismatch:
        return l10n.joinInviteMismatchBody;
      case JoinPhase.failed:
        return switch (s.issue ?? JoinIssue.unknown) {
          JoinIssue.badLink => l10n.joinInviteBadLink,
          JoinIssue.unavailable => l10n.joinInviteUnavailable,
          JoinIssue.network => l10n.joinInviteNetwork,
          JoinIssue.tampered => l10n.joinInviteTampered,
          JoinIssue.unknown => l10n.joinInviteUnknown,
        };
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(pairingV2AvailableProvider)) {
      return _frame(
        context,
        _v2Body(context),
        _v2Invite != null ? 'guest' : 'entry',
        _v2Invite != null ? 1 : 0,
      );
    }
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    ref.listen<InviteGuestState>(inviteGuestProvider, (previous, next) {
      if (next.phase == JoinPhase.conflict &&
          previous?.phase != JoinPhase.conflict) {
        _askReplace();
      } else if (next.phase == JoinPhase.joined &&
          previous?.phase != JoinPhase.joined) {
        _finish(l10n.joinInviteDoneBody(next.hostName ?? ''));
      }
    });
    final state = ref.watch(inviteGuestProvider);
    final controller = ref.read(inviteGuestProvider.notifier);

    Widget progress() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: CircularProgressIndicator()),
    );

    final Widget body;
    switch (state.phase) {
      case JoinPhase.requesting:
      case JoinPhase.joining:
        body = progress();
      case JoinPhase.waiting:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.joinInviteWaitingTitle,
                style: t.styles.screenTitleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.joinInviteWaitingBody, style: t.styles.body),
            progress(),
            TextButton(
              onPressed: controller.reset,
              child: Text(l10n.actionCancel),
            ),
          ],
        );
      case JoinPhase.compare:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.joinInviteConfirmTitle,
                style: t.styles.screenTitleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.joinInviteConfirmBody, style: t.styles.body),
            const SizedBox(height: 16),
            VerificationCodeCard(
              label: l10n.inviteCodeLabel,
              code: state.code ?? '',
            ),
            const SizedBox(height: 12),
            Text(
              l10n.joinInviteWaitingForConfirm,
              style: t.styles.meta,
              textAlign: TextAlign.center,
            ),
            progress(),
            OutlinedButton(
              onPressed: controller.reject,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(44, 48),
                foregroundColor: t.text,
                side: BorderSide(color: t.controlBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(l10n.joinInviteMismatch),
            ),
          ],
        );
      case JoinPhase.joined:
        body = progress();
      case JoinPhase.idle:
      case JoinPhase.conflict:
      case JoinPhase.mismatch:
      case JoinPhase.gone:
      case JoinPhase.taken:
      case JoinPhase.failed:
        final error = _errorText(l10n, state);
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.joinInviteIntro, style: t.styles.body),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.joinInviteFieldLabel,
                suffixIcon: TextButton(
                  onPressed: _paste,
                  child: Text(l10n.joinInvitePaste),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DeviceNameField(controller: _name),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error, style: t.styles.body),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _ask, child: Text(l10n.joinInviteAsk)),
          ],
        );
    }

    final (step, order) = switch (state.phase) {
      JoinPhase.requesting ||
      JoinPhase.joining ||
      JoinPhase.joined => ('busy', 1),
      JoinPhase.waiting => ('waiting', 2),
      JoinPhase.compare => ('compare', 3),
      _ => ('entry', 0),
    };
    return _frame(context, body, step, order);
  }

  /// El orden del paso de ahora y si el último cambio volvió atrás (un fallo
  /// devuelve al formulario): el paso entra desde el lado contrario.
  int _stepOrder = 0;
  bool _stepBack = false;

  Widget _frame(BuildContext context, Widget body, Object step, int order) {
    if (order != _stepOrder) {
      _stepBack = order < _stepOrder;
      _stepOrder = order;
    }
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // En tablet, una columna de 520 centrada, como el primer uso
        // (la guía de diseño para tablet, §3); en el móvil cabe entera.
        child: Column(
          children: [
            ContentWidth(
              maxWidth: RegalosLayout.onboardingColumn,
              child: ScreenHeader(
                eyebrow: widget.fromWelcome ? null : l10n.settingsShare,
                title: widget.fromQr
                    ? l10n.joinQrPairingTitle
                    : l10n.joinInviteRowTitle,
                backLabel: widget.fromWelcome
                    ? l10n.actionBack
                    : l10n.backTo(l10n.settingsShare),
                onBack: () => widget.fromWelcome && !context.canPop()
                    ? context.go('/welcome')
                    : Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: ContentWidth(
                  maxWidth: RegalosLayout.onboardingColumn,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: SheetSteps(
                      step: step,
                      back: _stepBack,
                      distance: 24,
                      child: body,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
