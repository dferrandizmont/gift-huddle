import '../sync/model.dart' as data;
import '../theme/gift_status.dart' as visual;

/// Pasa del estado del modelo al de las casillas, que tienen los mismos seis
/// valores en el mismo orden.
extension GiftStatusVisual on data.GiftStatus {
  /// El mismo estado para los widgets de diseño.
  visual.GiftStatus get visualStatus => visual.GiftStatus.values[index];

  /// El siguiente estado; el último no avanza más.
  data.GiftStatus? get next => index + 1 < data.GiftStatus.values.length
      ? data.GiftStatus.values[index + 1]
      : null;
}
