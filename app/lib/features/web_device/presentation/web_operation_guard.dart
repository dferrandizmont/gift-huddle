import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../application/web_app_provider.dart';
import '../application/web_sync_engine.dart' show WebOperationException;

/// Convierte una [WebOperationException] que nadie recogió (una acción que la
/// web no hace y que aún se pudo disparar) en un aviso claro, en vez de un
/// error crudo. Cualquier otro error sigue su camino.
///
/// Solo actúa en la web. Se engancha a los errores de los controladores de
/// eventos (`FlutterError.onError`) y a los asíncronos sin recoger
/// (`PlatformDispatcher.onError`) mientras está montado, y los deja como
/// estaban al desmontarse.
class WebOperationGuard extends ConsumerStatefulWidget {
  /// Crea la guarda.
  const WebOperationGuard({super.key, required this.child});

  /// La app.
  final Widget child;

  @override
  ConsumerState<WebOperationGuard> createState() => _WebOperationGuardState();
}

class _WebOperationGuardState extends ConsumerState<WebOperationGuard> {
  FlutterExceptionHandler? _previousFlutter;
  ErrorCallback? _previousPlatform;
  bool _hooked = false;

  void _hook() {
    if (_hooked) return;
    _hooked = true;
    _previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!_handle(details.exception)) _previousFlutter?.call(details);
    };
    _previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_handle(error)) return true;
      return _previousPlatform?.call(error, stack) ?? false;
    };
  }

  void _unhook() {
    if (!_hooked) return;
    _hooked = false;
    FlutterError.onError = _previousFlutter;
    PlatformDispatcher.instance.onError = _previousPlatform;
  }

  bool _handle(Object error) {
    if (error is! WebOperationException || !mounted) return false;
    final l10n = AppLocalizations.of(context);
    showRegalosSnackBar(
      context,
      SnackBar(content: Text(l10n.webOperationUnavailable)),
    );
    return true;
  }

  @override
  void dispose() {
    _unhook();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(webAppProvider)) {
      _hook();
    } else {
      _unhook();
    }
    return widget.child;
  }
}
