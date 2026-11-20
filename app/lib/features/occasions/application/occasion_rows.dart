import '../../../core/sync/model.dart';
import '../../family/domain/occasion_order.dart';

/// El id de la fila «Presupuesto de la casa» entre las de Ocasiones: es el
/// segmento de su ruta (`/occasions/budget`).
const String kBudgetRowId = 'budget';

/// Las filas elegibles de Ocasiones, por orden de arriba abajo: el presupuesto
/// y las ocasiones por días que faltan (el orden de «Hoy»), sin grupos.
List<String> occasionRowIds(Iterable<Occasion> occasions, DateTime now) => [
  kBudgetRowId,
  for (final o in occasionsByDaysLeft(occasions, now, includePassed: true))
    o.id,
];

/// La próxima ocasión: la que se elige al entrar en Ocasiones con dos
/// paneles. `null` si no hay ninguna.
String? nextOccasionRowId(Iterable<Occasion> occasions, DateTime now) =>
    occasionsByDaysLeft(occasions, now, includePassed: true).firstOrNull?.id;
