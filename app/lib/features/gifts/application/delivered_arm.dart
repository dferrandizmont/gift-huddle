import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cuánto vale un armado de «entregado».
const Duration kDeliveredArmWindow = Duration(seconds: 3);

/// Qué regalos acaba de entregar el usuario (la casilla, el selector o el
/// editor), para que su fila dé luz (§1+.3 de
/// la guía de movimiento). Un cambio que llega por sincronización
/// no pasa por aquí y no hace nada.
///
/// No es un estado que se observe: se consulta desde `didUpdateWidget` de la
/// fila, y ahí no se puede cambiar un proveedor. Por eso guarda el mapa en un
/// campo.
class DeliveredArms {
  final Map<String, DateTime> _armed = <String, DateTime>{};

  /// Arma el regalo [giftId] justo antes de guardar el cambio.
  void arm(String giftId) => _armed[giftId] = clock.now();

  /// Si [giftId] sigue armado, y lo desarma.
  bool consume(String giftId) {
    final at = _armed.remove(giftId);
    return at != null && clock.now().difference(at) <= kDeliveredArmWindow;
  }
}

/// Dónde se arma el «entregado» de un regalo.
final deliveredArmsProvider = Provider<DeliveredArms>((ref) => DeliveredArms());
