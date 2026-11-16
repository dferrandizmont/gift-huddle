import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cuenta los cambios que llegan de otro móvil (por sincronización o por un
/// sobre importado), a diferencia de los que hace el usuario aquí.
///
/// Las listas lo miran para animar distinto (§2.6 y norma 5 de
/// la guía de movimiento): lo que llega de fuera entra solo con
/// un fundido `soft`, sin desplegarse, sin rebote y sin celebración.
class RemoteChanges extends Notifier<int> {
  @override
  int build() => 0;

  /// Apunta que acaba de llegar un cambio de fuera.
  void bump() => state++;
}

/// El contador de cambios que llegan de fuera.
final remoteChangeProvider = NotifierProvider<RemoteChanges, int>(
  RemoteChanges.new,
);
