import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/root_navigator.dart';
import '../../family/application/family_controller.dart';
import '../../lock/application/lock_controller.dart';
import '../../lock/application/lock_gate_state.dart';
import '../../recovery/application/recovery_hold.dart';

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
    if (_joining || ref.read(joinInvitePresenceProvider).isActive) {
      ref.read(incomingInviteProvider.notifier).consume();
      return;
    }
    if (lockGateContent(
          family: ref.read(familyControllerProvider),
          lock: ref.read(lockControllerProvider),
          recoveryHeld: _hold.value,
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

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(incomingInviteProvider, (_, _) => _retryWhenReady());
    ref.listen(familyControllerProvider, (_, _) => _retryWhenReady());
    ref.listen(lockControllerProvider, (_, _) => _retryWhenReady());
    return widget.child;
  }
}
