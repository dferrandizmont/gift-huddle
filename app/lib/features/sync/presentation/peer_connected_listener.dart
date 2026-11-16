import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../application/peer_connected.dart';

/// Avisa con «Se ha conectado otro móvil» en el móvil que enseñó el QR de
/// emparejar, en cuanto la sincronización ve que el otro ha entrado y esté
/// donde esté la persona.
class PeerConnectedListener extends ConsumerStatefulWidget {
  /// Crea el escuchador. [navigatorKey] es el navegador raíz.
  const PeerConnectedListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// Navegador raíz: su contexto tiene los textos y el `ScaffoldMessenger`.
  final GlobalKey<NavigatorState> navigatorKey;

  /// La app.
  final Widget child;

  @override
  ConsumerState<PeerConnectedListener> createState() =>
      _PeerConnectedListenerState();
}

class _PeerConnectedListenerState extends ConsumerState<PeerConnectedListener> {
  @override
  void initState() {
    super.initState();
    // Un aviso que llegó antes de montar la interfaz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _show(ref.read(peerConnectedProvider));
      }
    });
  }

  void _show(PeerConnected? event) {
    if (event == null) {
      return;
    }
    final context = widget.navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    ref.read(peerConnectedProvider.notifier).consume();
    // Llega un móvil: es un momento de éxito.
    ref.read(hapticsProvider).success();
    final l10n = AppLocalizations.of(context);
    final name = event.name;
    showRegalosSnackBar(
      context,
      SnackBar(
        content: Text(
          name == null ? l10n.peerConnected : l10n.peerConnectedNamed(name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PeerConnected?>(peerConnectedProvider, (_, next) => _show(next));
    return widget.child;
  }
}
