import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart' show AppRoutes, routerProvider;
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/recovery_file_flow.dart';
import 'recovery_file_parts.dart'
    show recoveryFileRestoringProvider, recoveryFileScreenOpenProvider;
import 'recovery_file_problem.dart';

/// Escucha los ficheros de recuperación que llegan de fuera (Archivos, otra
/// app, la hoja de compartir; ADR 0008). No generan avisos de importación: se
/// quedan en `recoveryFileProvider` y esta pieza decide qué se ve.
///
/// * Móvil vacío y fichero utilizable: abre «Recuperar con fichero», que pide
///   la contraseña (nunca se deriva sin ella).
/// * Fichero inservible, o móvil que ya tiene lista: un aviso y nada más.
/// * Otro fichero mientras se procesa uno: se pregunta antes de cambiar.
///
/// Va dentro de la app, con [navigatorKey] el del router, para abrir los
/// avisos por encima de cualquier pantalla.
class RecoveryFileListener extends ConsumerStatefulWidget {
  /// Crea el escuchador.
  const RecoveryFileListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// Navegador raíz donde se abren los avisos.
  final GlobalKey<NavigatorState> navigatorKey;

  /// La app.
  final Widget child;

  @override
  ConsumerState<RecoveryFileListener> createState() =>
      _RecoveryFileListenerState();
}

class _RecoveryFileListenerState extends ConsumerState<RecoveryFileListener> {
  RecoveryFileSelection? _handled;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    // Un fichero que llegó antes de montar la interfaz (arranque en frío).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_handle(ref.read(recoveryFileProvider)));
      }
    });
  }

  /// Si «Recuperar con fichero» ya está abierta (o a punto de abrirse): no se
  /// apila otra encima.
  bool _pushing = false;

  bool get _onRestoreScreen =>
      _pushing || ref.read(recoveryFileScreenOpenProvider) > 0;

  Future<void> _handle(RecoveryFileState state) async {
    final context = widget.navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final notifier = ref.read(recoveryFileProvider.notifier);
    // Mientras se restaura con un fichero, el que llega espera: cambiar no
    // puede parar esa restauración. Se ofrece al terminar.
    if (state.waiting != null &&
        !_asking &&
        !ref.read(recoveryFileRestoringProvider)) {
      _asking = true;
      try {
        final l10n = AppLocalizations.of(context);
        final switchFile = await showRegalosConfirm(
          context,
          title: l10n.recoverFileWaitingTitle,
          body: l10n.recoverFileWaitingBody,
          confirmLabel: l10n.recoverFileWaitingSwitch,
          cancelLabel: l10n.recoverFileWaitingKeep,
        );
        if (!mounted) {
          return;
        }
        if (switchFile) {
          notifier.acceptWaiting();
        } else {
          notifier.dismissWaiting();
        }
      } finally {
        _asking = false;
      }
      return;
    }
    final selection = state.selection;
    if (selection == null) {
      _handled = null;
      return;
    }
    if (selection.source != RecoveryFileSource.received ||
        identical(selection, _handled)) {
      return;
    }
    _handled = selection;
    // Con «Recuperar con fichero» abierta, es ella quien lo adopta.
    if (_onRestoreScreen) {
      return;
    }
    if (selection.failure != null || selection.hasFamily) {
      final l10n = AppLocalizations.of(context);
      final problem = selection.hasFamily
          ? const RecoveryFileProblem(RecoveryFileProblemKind.hasFamily)
          : RecoveryFileProblem(
              selection.failure == RecoveryFileFailure.newerVersion
                  ? RecoveryFileProblemKind.newerVersion
                  : RecoveryFileProblemKind.notRecoveryFile,
            );
      notifier.clear();
      // El diálogo de la casa (radio 8, entrada con escala y fundido), con un
      // solo botón.
      await showRegalosDialog<void>(
        context,
        avoidKeyboard: false,
        builder: (dialogContext) {
          final t = RegalosTokens.of(dialogContext);
          return RegalosDialogSurface(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    recoveryFileProblemTitle(l10n, problem),
                    style: t.styles.screenTitleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  recoveryFileProblemBody(l10n, problem),
                  style: t.styles.body,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  style: regalosDialogCancelStyle(t),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.actionClose),
                ),
              ],
            ),
          );
        },
      );
      return;
    }
    _pushing = true;
    unawaited(
      ref
          .read(routerProvider)
          .push<void>(AppRoutes.recoverFile)
          .whenComplete(() => _pushing = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RecoveryFileState>(recoveryFileProvider, (_, next) {
      unawaited(_handle(next));
    });
    ref.listen<bool>(recoveryFileRestoringProvider, (previous, restoring) {
      if (previous == true && !restoring) {
        final notifier = ref.read(recoveryFileProvider.notifier);
        final state = ref.read(recoveryFileProvider);
        if (state.selection == null && state.waiting != null) {
          // La restauración acabó (el fichero ya se soltó): el que esperaba ya
          // no tiene sentido en un móvil con lista.
          notifier.dismissWaiting();
        } else {
          unawaited(_handle(state));
        }
      }
    });
    return widget.child;
  }
}
