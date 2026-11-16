import '../../../core/sync/model.dart';
import 'chinese_new_year.dart';

/// La próxima ocasión, con su fecha y los días que faltan.
class NextOccasion {
  /// Crea la próxima ocasión.
  const NextOccasion({
    required this.occasion,
    required this.date,
    required this.days,
  });

  /// La ocasión.
  final Occasion occasion;

  /// El día en que cae (solo fecha).
  final DateTime date;

  /// Días que faltan: 0 si es hoy.
  final int days;

  @override
  String toString() => 'NextOccasion(${occasion.name}, $date, $days days)';
}

/// El día [day] de [month] de [year]; el 29 de febrero cae el 28 en los años
/// que no son bisiestos.
DateTime _dateOf(int year, int month, int day) {
  if (month == 2 && day == 29 && !_isLeap(year)) {
    return DateTime(year, 2, 28);
  }
  return DateTime(year, month, day);
}

bool _isLeap(int year) => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// El día en que cae [occasion] en [year]: el del Año Nuevo Chino cambia cada
/// año; el resto repite el día y el mes guardados.
DateTime _dateIn(Occasion occasion, int year) =>
    occasion.kind == OccasionKind.chineseNewYear
    ? chineseNewYearOf(year)
    : _dateOf(year, occasion.month, occasion.day);

/// El día y el mes en que cae [occasion] la próxima vez desde [now]; si ya
/// pasó o no tiene fecha válida, los guardados.
///
/// Es lo que se enseña como fecha: el Año Nuevo Chino se mueve cada año y el
/// mes y el día guardados solo son los de cuando se creó.
({int month, int day}) occasionDayMonth(Occasion occasion, DateTime now) {
  final date = nextDateOf(occasion, now);
  return date == null
      ? (month: occasion.month, day: occasion.day)
      : (month: date.month, day: date.day);
}

/// Próxima fecha de [occasion] desde [today] (hoy cuenta), o `null` si ya
/// pasó y no se repite o si su fecha no es válida.
DateTime? nextDateOf(Occasion occasion, DateTime today) {
  if (occasion.month < 1 ||
      occasion.month > 12 ||
      occasion.day < 1 ||
      occasion.day > 31) {
    return null;
  }
  final start = DateTime(today.year, today.month, today.day);
  if (occasion.recurring) {
    var date = _dateIn(occasion, today.year);
    if (date.isBefore(start)) {
      date = _dateIn(occasion, today.year + 1);
    }
    return date;
  }
  final year = occasion.year;
  if (year == null) {
    return null;
  }
  final date = _dateIn(occasion, year);
  return date.isBefore(start) ? null : date;
}

/// La ocasión más cercana de [occasions] desde [now], sin contar las
/// archivadas.
NextOccasion? nextOccasionFrom(Iterable<Occasion> occasions, DateTime now) {
  final all = upcomingOccasionsFrom(occasions, now);
  return all.isEmpty ? null : all.first;
}

/// Las próximas ocasiones de [occasions] desde [now], de la más cercana a la
/// más lejana (a igual fecha, por nombre), sin las archivadas ni las que ya
/// pasaron y no se repiten.
List<NextOccasion> upcomingOccasionsFrom(
  Iterable<Occasion> occasions,
  DateTime now,
) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final list = <NextOccasion>[];
  for (final occasion in occasions) {
    if (occasion.archived) {
      continue;
    }
    final date = nextDateOf(occasion, now);
    if (date == null) {
      continue;
    }
    final days = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(today).inDays;
    list.add(NextOccasion(occasion: occasion, date: date, days: days));
  }
  list.sort((a, b) {
    final byDays = a.days.compareTo(b.days);
    if (byDays != 0) {
      return byDays;
    }
    final byName = a.occasion.name.toLowerCase().compareTo(
      b.occasion.name.toLowerCase(),
    );
    // Las de serie no guardan nombre: a igual fecha, el orden es estable.
    return byName != 0 ? byName : a.occasion.id.compareTo(b.occasion.id);
  });

  return list;
}
