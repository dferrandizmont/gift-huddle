import '../../../core/sync/model.dart';
import 'next_occasion.dart';

/// El orden de las ocasiones, el mismo en «Hoy», en «Ocasiones» del móvil y de
/// la tablet y en el tablero web: por los días que faltan, de menos a más (a
/// igual fecha, por nombre y luego por id), sin agrupar. Las que ya pasaron y
/// no se repiten no tienen próxima fecha: van al final, por nombre y luego por
/// id, si [includePassed], y se omiten si no. Las archivadas nunca salen.
List<Occasion> occasionsByDaysLeft(
  Iterable<Occasion> occasions,
  DateTime now, {
  bool includePassed = false,
}) {
  final upcoming = upcomingOccasionsFrom(occasions, now);
  final ordered = [for (final next in upcoming) next.occasion];
  if (!includePassed) {
    return ordered;
  }
  final seen = {for (final o in ordered) o.id};
  final passed =
      [
        for (final o in occasions)
          if (!o.archived && !seen.contains(o.id)) o,
      ]..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
  return [...ordered, ...passed];
}
