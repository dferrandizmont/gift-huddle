import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart' show AppRoutes, routerProvider;
import '../../../app/root_navigator.dart' show rootNavigatorObserver;
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
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
  bool _retryScheduled = false;
  bool _storageErrorShown = false;

  @override
  void initState() {
    super.initState();
    rootNavigatorObserver.addListener(_retryWhenReady);
    // Un fichero que llegó antes de montar la interfaz (arranque en frío).
    _retryWhenReady();
  }

  @override
  void dispose() {
    rootNavigatorObserver.removeListener(_retryWhenReady);
    super.dispose();
  }

  /// Un único intento por señal de familia, fichero o navegador. La ausencia
  /// del navegador no vuelve a programarlo: el fichero sigue pendiente.
  void _retryWhenReady() {
    if (_retryScheduled) return;
    _retryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryScheduled = false;
      if (mounted) unawaited(_handle(ref.read(recoveryFileProvider)));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Solo hasta que la pantalla se monte. La vida de la pantalla la señala
  /// su contador: un refresh del router puede dejar pendiente el Future de
  /// push incluso después de volver atrás.
  bool _pushing = false;

  bool get _onRestoreScreen =>
      _pushing || ref.read(recoveryFileScreenOpenProvider) > 0;

  Future<void> _handle(RecoveryFileState state) async {
    final context = widget.navigatorKey.currentContext;
    if (state.selection == null && state.waiting == null) {
      _handled = null;
      return;
    }
    final family = ref.read(familyControllerProvider);
    // Esperar el resultado evita que la redirección inicial retire la ruta.
    if (family.isLoading || context == null) return;
    if (family.hasError) {
      if (_storageErrorShown) return;
      _storageErrorShown = true;
      final l10n = AppLocalizations.of(context);
      final retry = await showRegalosConfirm(
        context,
        title: l10n.recoveryFileProblemStorageTitle,
        body: l10n.recoveryFileProblemStorageBody,
        confirmLabel: l10n.recoveryRetry,
        cancelLabel: l10n.actionClose,
      );
      if (mounted && retry) {
        _storageErrorShown = false;
        ref.invalidate(familyControllerProvider);
      }
      // No asumir móvil vacío ni perder el fichero ante un error de lectura.
      return;
    }
    if (_asking) return;
    final notifier = ref.read(recoveryFileProvider.notifier);
    // Mientras se restaura con un fichero, el que llega espera: cambiar no
    // puede parar esa restauración. Se ofrece al terminar.
    if (state.waiting != null &&
        !_asking &&
        !ref.read(recoveryFileRestoringProvider)) {
      if (ref.read(recoveryFileScreenOpenProvider) == 0) {
        // Sin recuperación visible no hay una decisión que conservar. El
        // último fichero recibido pasa a ser el actual y abre su pantalla.
        notifier.acceptWaiting();
        _retryWhenReady();
        return;
      }
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
        _retryWhenReady();
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
    // Un fallo al recibir no es una familia confirmada. La carga correcta
    // (también tras «Reintentar») permite decidir sin perder el fichero.
    final hasFamily =
        selection.hasFamily == true || family.requireValue.hasFamily;
    if (selection.failure != null || hasFamily) {
      final l10n = AppLocalizations.of(context);
      final problem = hasFamily
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
      ref.read(routerProvider).push<void>(AppRoutes.recoverFile).whenComplete(
        () {
          _pushing = false;
          if (mounted) _retryWhenReady();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(familyControllerProvider, (_, next) {
      if (!next.hasError) _storageErrorShown = false;
      _retryWhenReady();
    });
    ref.listen<RecoveryFileState>(recoveryFileProvider, (_, next) {
      _retryWhenReady();
    });
    ref.listen<int>(recoveryFileScreenOpenProvider, (_, screens) {
      if (screens > 0) _pushing = false;
      _retryWhenReady();
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
