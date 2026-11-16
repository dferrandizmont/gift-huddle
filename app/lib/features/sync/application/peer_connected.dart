import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// El móvil que leyó el QR de emparejar de este acaba de entrar.
@immutable
class PeerConnected {
  /// Crea el aviso. [name] es el nombre del otro móvil, si se sabe.
  const PeerConnected({this.name});

  /// Nombre del otro móvil, o `null`.
  final String? name;
}

/// Aviso pendiente de «Se ha conectado otro móvil» en el móvil que enseñó el
/// QR: el QR no avisa de que lo han leído, así que quien lo enseñó se entera
/// cuando la sincronización ve la primera copia del otro. El estado es el
/// aviso hasta que la interfaz lo muestra y llama a [consume].
class PeerConnectedController extends Notifier<PeerConnected?> {
  @override
  PeerConnected? build() => null;

  /// Ha entrado otro móvil; [name] es su nombre, si se sabe.
  void announce(String? name) {
    final clean = name?.trim() ?? '';
    state = PeerConnected(name: clean.isEmpty ? null : clean);
  }

  /// La interfaz ya lo ha mostrado.
  void consume() => state = null;
}

/// El aviso pendiente de que ha entrado otro móvil.
final peerConnectedProvider =
    NotifierProvider<PeerConnectedController, PeerConnected?>(
      PeerConnectedController.new,
    );
