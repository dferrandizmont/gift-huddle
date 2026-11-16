import '../../../core/sync/model.dart';
import '../../family/application/gift_logic.dart';

/// El id de la fila «Presupuesto de la casa» entre las de Ocasiones: es el
/// segmento de su ruta (`/occasions/budget`).
const String kBudgetRowId = 'budget';

/// Las filas elegibles de Ocasiones, por orden de arriba abajo: el presupuesto,
/// las fiestas y los cumpleaños (cada grupo por próxima fecha).
List<String> occasionRowIds(Iterable<Occasion> occasions, DateTime now) {
  final ordered = occasionsByNextDate(occasions, now);
  return [
    kBudgetRowId,
    for (final o in ordered)
      if (o.kind != OccasionKind.birthday) o.id,
    for (final o in ordered)
      if (o.kind == OccasionKind.birthday) o.id,
  ];
}

/// La próxima ocasión: la que se elige al entrar en Ocasiones con dos
/// paneles. `null` si no hay ninguna.
String? nextOccasionRowId(Iterable<Occasion> occasions, DateTime now) =>
    occasionsByNextDate(occasions, now).firstOrNull?.id;
