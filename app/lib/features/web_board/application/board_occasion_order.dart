import '../../../core/sync/model.dart';
import '../../family/domain/occasion_order.dart';

/// El orden de las ocasiones de la tira del tablero: el mismo que «Hoy» y
/// «Ocasiones» ([occasionsByDaysLeft], que es donde vive).
List<Occasion> boardOccasionOrder(
  Iterable<Occasion> occasions,
  DateTime now, {
  bool includePassed = false,
}) => occasionsByDaysLeft(occasions, now, includePassed: includePassed);
