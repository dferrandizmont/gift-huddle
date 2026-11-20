import 'dart:async';
import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/link_source.dart';
import '../data/sync_config.dart';
import 'invite_link.dart';

/// Recibe los enlaces `https://<host>/i#<inviteId>` que abren la app (App
/// Link). El estado es el id de la invitación hasta que la interfaz abre la
/// pantalla y llama a [consume].
///
/// Sin servidor configurado no hace nada. El filtro de intents del manifest
/// de Android sigue comentado hasta tener dominio.
class IncomingInviteController extends Notifier<String?> {
  StreamSubscription<String>? _links;
  final _launchEvents = <String>{};
  bool _initialPending = false;
  String? _initialFingerprint;

  // Retain only a digest until the one stream copy arrives, never the URL.
  String _fingerprint(String uri) =>
      base64Encode(const DartSha256().hashSync(utf8.encode(uri)).bytes);

  @override
  String? build() {
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      _links?.cancel();
    });
    final endpoint = ref.read(syncEndpointProvider);
    if (endpoint != null) {
      try {
        _links = ref
            .read(linkSourceProvider)
            .links
            .listen((uri) => handleUri(uri), onError: (Object _) {});
      } on MissingPluginException {
        // Sin plugin de enlaces (pruebas, escritorio).
      }
    }
    final initial = ref.read(linkSourceProvider).takeInitialLink();
    if (initial is Future<String?>) {
      _initialPending = true;
      unawaited(
        initial.then(
          (uri) {
            if (disposed) return;
            _initialPending = false;
            if (uri != null) {
              final fingerprint = _fingerprint(uri);
              if (!_launchEvents.contains(fingerprint)) {
                _initialFingerprint = fingerprint;
                handleUri(uri, initial: true);
              }
            }
            _launchEvents.clear();
          },
          onError: (Object _) {
            _initialPending = false;
            _launchEvents.clear();
          },
        ),
      );
      return null;
    }
    return endpoint == null || initial == null
        ? null
        : inviteIdFromUri(initial, endpoint.invitationHost);
  }

  /// Mira un enlace; si es una invitación de este servidor, la guarda.
  void handleUri(String uri, {bool initial = false}) {
    // iOS can replay the launch activity via both the initial API and stream,
    // in either order. Later taps of the same invitation must still work.
    if (!initial) {
      final fingerprint = _fingerprint(uri);
      if (_initialPending) _launchEvents.add(fingerprint);
      if (fingerprint == _initialFingerprint) {
        _initialFingerprint = null;
        return;
      }
    }
    final endpoint = ref.read(syncEndpointProvider);
    if (endpoint == null) {
      return;
    }
    final id = inviteIdFromUri(uri, endpoint.invitationHost);
    if (id != null) {
      state = id;
    }
  }

  /// La interfaz ya abrió la pantalla.
  void consume() => state = null;
}

/// Enlaces de invitación que abren la app. Se lee una vez al arrancar
/// (`main.dart`).
final incomingInviteProvider =
    NotifierProvider<IncomingInviteController, String?>(
      IncomingInviteController.new,
    );
