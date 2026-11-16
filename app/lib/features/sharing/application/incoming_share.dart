import 'dart:async';

import '../../../core/platform/link_source.dart';
import '../../../core/platform/document_exchange.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/envelope.dart';
import '../../../core/sync/recovery_file.dart' show isRecoveryFile;
import '../../family/domain/family_errors.dart';
import '../../sync/application/recovery_file_flow.dart';
import 'share_service.dart';

export '../../../core/platform/document_exchange.dart' show kIncomingChannel;

/// Lo que pasó al recibir un sobre desde fuera de la app.
sealed class IncomingShareEvent {
  const IncomingShareEvent();
}

/// Se importó un sobre.
final class IncomingImported extends IncomingShareEvent {
  /// Crea el evento.
  const IncomingImported(this.summary);

  /// Qué cambió.
  final ImportSummary summary;
}

/// No se pudo importar. [error] es una excepción tipada: `EnvelopeException`,
/// `NoFamilyException`, `ImportClockDriftException`...
final class IncomingFailed extends IncomingShareEvent {
  /// Crea el evento.
  const IncomingFailed(this.error);

  /// El error.
  final Object error;
}

/// El texto del sobre de un enlace `https://<host>/s#...`, o `null` si el
/// enlace no es de Gift Huddle.
String? shareTextFromUri(Uri uri) {
  if (uri.scheme != 'https' || uri.host != kShareHost || uri.path != '/s') {
    return null;
  }
  return uri.fragment.isEmpty ? null : uri.fragment;
}

/// Recibe sobres que llegan de fuera (fichero abierto desde otra app o
/// enlace) y los importa. El último resultado queda en el estado hasta que
/// la interfaz lo consume con [consume].
///
/// Antes del importador, un distribuidor por la magia «GHK» manda los ficheros
/// de recuperación (ADR 0008) a `recoveryFileProvider`, sin derivar ni ir a
/// la red; no generan [IncomingShareEvent].
class IncomingShareController extends Notifier<IncomingShareEvent?> {
  StreamSubscription<String>? _links;

  @override
  IncomingShareEvent? build() {
    final exchange = ref.read(documentExchangeProvider);
    ref.onDispose(() {
      exchange.stopReceiving();
      _links?.cancel();
    });
    unawaited(_start());
    return null;
  }

  Future<void> _start() async {
    final exchange = ref.read(documentExchangeProvider);
    // Ficheros de recuperación compartidos que quedaran de un cierre abrupto.
    unawaited(exchange.clearRecoveryShares());
    await exchange.startReceiving(_importBytes);
    try {
      _links = ref
          .read(linkSourceProvider)
          .links
          .listen(_onLink, onError: (Object _) {});
    } on MissingPluginException {
      // Sin plugin de enlaces.
    }
  }

  void _onLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) {
      return;
    }
    final text = shareTextFromUri(uri);
    if (text != null) {
      unawaited(
        _run(() => ref.read(shareServiceProvider).importFromText(text)),
      );
    }
  }

  Future<void> _importBytes(Uint8List bytes) {
    if (isRecoveryFile(bytes)) {
      return ref.read(recoveryFileProvider.notifier).receive(bytes);
    }
    return _run(
      () => ref.read(shareServiceProvider).importEnvelopeBytes(bytes),
    );
  }

  Future<void> _run(Future<ImportSummary> Function() import) async {
    try {
      state = IncomingImported(await import());
    } on Object catch (error) {
      state = IncomingFailed(error);
    }
  }

  /// La interfaz ya mostró el resultado.
  void consume() => state = null;
}

/// Receptor de sobres externos. Se lee una vez al arrancar (`main.dart`).
final incomingShareProvider =
    NotifierProvider<IncomingShareController, IncomingShareEvent?>(
      IncomingShareController.new,
    );
