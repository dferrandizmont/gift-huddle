import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/root_navigator.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../lock/application/lock_controller.dart';
import '../../lock/application/lock_gate_state.dart';
import '../../recovery/application/recovery_hold.dart';

import '../application/pairing_v2_controller.dart';
import '../application/replace_join_hold.dart';
import '../invites/incoming_invite.dart';
import 'join_invite_screen.dart';

/// Abre «Unirme con un enlace» cuando llega un App Link de invitación
/// (`https://<host>/i#<id>`), por encima de cualquier pantalla.
class InviteLinkListener extends ConsumerStatefulWidget {
  /// Crea el escuchador. [navigatorKey] es el navegador raíz.
  const InviteLinkListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// Navegador raíz donde se abre la pantalla.
  final GlobalKey<NavigatorState> navigatorKey;

  /// La app.
  final Widget child;

  @override
  ConsumerState<InviteLinkListener> createState() => _InviteLinkListenerState();
}

class _InviteLinkListenerState extends ConsumerState<InviteLinkListener> {
  bool _scheduled = false;
  bool _joining = false;
  late final RecoveryHold _hold = ref.read(recoveryHoldProvider);

  @override
  void initState() {
    super.initState();
    rootNavigatorObserver.addListener(_retryWhenReady);
    _hold.addListener(_retryWhenReady);
    _retryWhenReady();
  }

  @override
  void dispose() {
    rootNavigatorObserver.removeListener(_retryWhenReady);
    _hold.removeListener(_retryWhenReady);
    super.dispose();
  }

  void _retryWhenReady() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _open(ref.read(incomingInviteProvider));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _open(String? inviteId) {
    if (inviteId == null) {
      return;
    }
    // Ignore every link while this join is mounted, including its exit
    // transition: v2 views share a controller and reset it on disposal.
    // Nor while a join is installing (its screen may already be closed): the
    // new screen could not open anything and would show that progress.
    if (_joining ||
        ref.read(joinInvitePresenceProvider).isActive ||
        ref.read(pairingV2GuestProvider.notifier).installing) {
      ref.read(incomingInviteProvider.notifier).consume();
      return;
    }
    if (lockGateContent(
          family: ref.read(familyControllerProvider),
          lock: ref.read(lockControllerProvider),
          recoveryHeld: _hold.value,
          replacingFamily: ref.read(replaceJoinHoldProvider).value,
        ) !=
        LockGateContent.none) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    ref.read(incomingInviteProvider.notifier).consume();
    _joining = true;
    final route = MaterialPageRoute<void>(
      builder: (_) => JoinInviteScreen(initialInvite: inviteId),
    );
    navigator.push<void>(route);
    route.completed.then((_) {
      _joining = false;
      if (mounted) _retryWhenReady();
    });
  }

  /// Este móvil ya está dentro, pero quizá ninguna vista de unirse lo va a
  /// recoger (la que entraba se cerró a media instalación; otra pantalla de
  /// unirse abierta después se queda en el formulario). Las vistas lo piden al
  /// momento; esto espera al final del fotograma y, si nadie lo ha pedido,
  /// cierra las pantallas de unirse que queden, va a Personas y enseña la hoja
  /// final ([PairingV2GuestController.claimDone]: una sola vez).
  void _joinedWithoutScreen(String? assignedPersonId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guest = ref.read(pairingV2GuestProvider.notifier);
      final navigator = widget.navigatorKey.currentState;
      final navigatorContext = widget.navigatorKey.currentContext;
      if (navigator == null || navigatorContext == null) return;
      if (!guest.claimDone()) return;
      ref.read(joinInvitePresenceProvider).closeAll(navigator);
      unawaited(
        finishJoin(
          container: ProviderScope.containerOf(context, listen: false),
          l10n: AppLocalizations.of(navigatorContext),
          router: GoRouter.maybeOf(navigatorContext),
          // La de esta entrada, leída al llegar «hecho»: para ahora el
          // emparejamiento puede haber vuelto a reposo.
          assignedPersonId: assignedPersonId,
        ),
      );
      // El emparejamiento vuelve a reposo, si nadie lo ha movido ya.
      if (ref.read(pairingV2GuestProvider).phase == PairingV2GuestPhase.done) {
        guest.reset();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PairingV2GuestState>(pairingV2GuestProvider, (previous, next) {
      if (next.phase == PairingV2GuestPhase.done &&
          previous?.phase != PairingV2GuestPhase.done) {
        _joinedWithoutScreen(next.assignedPersonId);
      }
    });
    ref.listen<String?>(incomingInviteProvider, (_, _) => _retryWhenReady());
    ref.listen(familyControllerProvider, (_, _) => _retryWhenReady());
    ref.listen(lockControllerProvider, (_, _) => _retryWhenReady());
    return widget.child;
  }
}
