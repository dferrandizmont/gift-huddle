/// Los seis estados de un regalo, en orden de avance.
///
/// Es la vista visual del estado: el modelo de datos lo mapeará a su propio
/// tipo. Los nombres no se guardan en ningún sitio.
enum GiftStatus {
  idea,
  decided,
  bought,
  arrived,
  wrapped,
  delivered;

  /// Fracción del círculo que se rellena en la casilla (0, 0, ¼, ½, ¾, 1).
  double get fill => switch (this) {
    GiftStatus.idea || GiftStatus.decided => 0,
    GiftStatus.bought => 0.25,
    GiftStatus.arrived => 0.5,
    GiftStatus.wrapped => 0.75,
    GiftStatus.delivered => 1,
  };
}
