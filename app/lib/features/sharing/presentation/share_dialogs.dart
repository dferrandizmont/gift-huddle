import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../app/root_navigator.dart' show rootNavigatorObserver;
import '../../family/application/family_controller.dart';
import '../../family/domain/family_errors.dart';
import '../../family/presentation/family_texts.dart';
import '../../sync/presentation/invite_link_listener.dart';
import '../application/incoming_share.dart';
import 'share_error_text.dart';

/// Avisa de lo que trajo un envío: «3 regalos nuevos, 2 cambiados».
Future<void> showImportSummaryDialog(
  BuildContext context,
  ImportSummary summary,
) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.incomingTitle),
      content: Text(importSummaryText(l10n, summary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.actionDone),
        ),
      ],
    ),
  );
}

/// Avisa de por qué no se pudo abrir un envío.
Future<void> showImportErrorDialog(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.incomingFailedTitle),
      content: Text(shareErrorMessage(l10n, error)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    ),
  );
}

/// Escucha los envíos que abren la app desde fuera (un fichero `.regalos`,
/// un enlace) y enseña su resultado o su error.
///
/// Va dentro de la app, con [navigatorKey] el del router, para poder abrir el
/// aviso por encima de cualquier pantalla.
class IncomingShareListener extends ConsumerStatefulWidget {
  /// Crea el escuchador.
  const IncomingShareListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// Navegador raíz donde se abre el aviso.
  final GlobalKey<NavigatorState> navigatorKey;

  /// La app.
  final Widget child;

  @override
  ConsumerState<IncomingShareListener> createState() =>
      _IncomingShareListenerState();
}

class _IncomingShareListenerState extends ConsumerState<IncomingShareListener> {
  bool _showing = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    rootNavigatorObserver.addListener(_retryWhenReady);
    _retryWhenReady();
  }

  @override
  void dispose() {
    rootNavigatorObserver.removeListener(_retryWhenReady);
    super.dispose();
  }

  void _retryWhenReady() {
    if (_scheduled) return;
    _scheduled = true;
    // Un envío que llegó antes de montar la interfaz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) {
        _handle(ref.read(incomingShareProvider));
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _handle(IncomingShareEvent? event) async {
    if (event == null || _showing) {
      return;
    }
    // No consumir el aviso hasta que termine la redirección de bienvenida.
    if (ref.read(familyControllerProvider).isLoading) return;
    final dialogContext = widget.navigatorKey.currentContext;
    if (dialogContext == null) {
      return;
    }
    _showing = true;
    ref.read(incomingShareProvider.notifier).consume();
    try {
      switch (event) {
        case IncomingImported(:final summary):
          await showImportSummaryDialog(dialogContext, summary);
        case IncomingFailed(:final error):
          await showImportErrorDialog(dialogContext, error);
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<IncomingShareEvent?>(incomingShareProvider, (_, next) {
      _retryWhenReady();
    });
    ref.listen(familyControllerProvider, (_, _) => _retryWhenReady());
    return InviteLinkListener(
      navigatorKey: widget.navigatorKey,
      child: widget.child,
    );
  }
}
