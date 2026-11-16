import 'dart:async';

import '../../../core/platform/link_source.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  String? build() {
    ref.onDispose(() => _links?.cancel());
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
    return endpoint == null || initial == null
        ? null
        : inviteIdFromUri(initial, endpoint.invitationHost);
  }

  /// Mira un enlace; si es una invitación de este servidor, la guarda.
  void handleUri(String uri) {
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
