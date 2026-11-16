import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  @override
  void initState() {
    super.initState();
    // Un enlace que llegó antes de montar la interfaz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _open(ref.read(incomingInviteProvider));
      }
    });
  }

  void _open(String? inviteId) {
    if (inviteId == null) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    ref.read(incomingInviteProvider.notifier).consume();
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JoinInviteScreen(initialInvite: inviteId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(incomingInviteProvider, (_, next) => _open(next));
    return widget.child;
  }
}
