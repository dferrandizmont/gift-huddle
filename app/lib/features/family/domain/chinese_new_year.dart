import 'dart:math' as math;

/// Día del Año Nuevo Chino de cada año, de 2026 a 2040 (calendario
/// gregoriano, hora de China).
///
/// Es la tabla que manda: dentro de estos años no se calcula nada.
const Map<int, (int month, int day)> kChineseNewYearTable = {
  2026: (2, 17),
  2027: (2, 6),
  2028: (1, 26),
  2029: (2, 13),
  2030: (2, 3),
  2031: (1, 23),
  2032: (2, 11),
  2033: (1, 31),
  2034: (2, 19),
  2035: (2, 8),
  2036: (1, 28),
  2037: (2, 15),
  2038: (2, 4),
  2039: (1, 24),
  2040: (2, 12),
};

/// Primer y último año de la tabla.
const int kChineseNewYearFirstYear = 2026;
const int kChineseNewYearLastYear = 2040;

/// El día del Año Nuevo Chino de [year], solo fecha.
///
/// De 2026 a 2040 sale de [kChineseNewYearTable]; fuera de la tabla se
/// calcula con la luna nueva (ver [approximateChineseNewYear]).
DateTime chineseNewYearOf(int year) {
  final known = kChineseNewYearTable[year];
  if (known != null) {
    return DateTime(year, known.$1, known.$2);
  }
  return approximateChineseNewYear(year);
}

/// El próximo Año Nuevo Chino desde [today] (hoy cuenta).
DateTime nextChineseNewYear(DateTime today) {
  final start = DateTime(today.year, today.month, today.day);
  final thisYear = chineseNewYearOf(start.year);
  return thisYear.isBefore(start) ? chineseNewYearOf(start.year + 1) : thisYear;
}

/// Cálculo del Año Nuevo Chino de [year] para los años que no están en la
/// tabla: el día (hora de China) de la luna nueva que cae entre el 21 de enero
/// y el 20 de febrero.
///
/// Usa las fases de la luna de Jean Meeus (término principal y 23 de
/// periódicos): el error es de minutos, así que solo puede fallar un día si la
/// luna nueva cae a menos de unos minutos de la medianoche de China.
DateTime approximateChineseNewYear(int year) {
  // Una luna nueva por lunación: se prueba desde antes de enero.
  final firstK = ((year + (21 / 365.25) - 2000) * 12.3685).floor() - 2;
  for (var k = firstK; k < firstK + 5; k++) {
    final local = _newMoonChinaDate(k);
    if (local.year != year) {
      continue;
    }
    final afterStart =
        local.month == 2 || (local.month == 1 && local.day >= 21);
    final beforeEnd = local.month == 1 || (local.month == 2 && local.day <= 20);
    if (afterStart && beforeEnd) {
      return local;
    }
  }
  // No debería pasar: cada año tiene una luna nueva en esa ventana.
  return DateTime(year, 2, 1);
}

double _rad(double degrees) => degrees * math.pi / 180;

/// La fecha de China de la luna nueva número [k] (0 = la del 6 de enero de
/// 2000).
DateTime _newMoonChinaDate(int k) {
  final t = k / 1236.85;
  final t2 = t * t;
  final t3 = t2 * t;
  final t4 = t3 * t;
  var jde =
      2451550.09766 +
      29.530588861 * k +
      0.00015437 * t2 -
      0.000000150 * t3 +
      0.00000000073 * t4;
  final e = 1 - 0.002516 * t - 0.0000074 * t2;
  final m = _rad(2.5534 + 29.10535670 * k - 0.0000014 * t2 - 0.00000011 * t3);
  final mp = _rad(
    201.5643 +
        385.81693528 * k +
        0.0107582 * t2 +
        0.00001238 * t3 -
        0.000000058 * t4,
  );
  final f = _rad(
    160.7108 +
        390.67050284 * k -
        0.0016118 * t2 -
        0.00000227 * t3 +
        0.000000011 * t4,
  );
  final om = _rad(124.7746 - 1.56375588 * k + 0.0020672 * t2 + 0.00000215 * t3);
  double s(double x) => math.sin(x);
  jde +=
      -0.40720 * s(mp) +
      0.17241 * e * s(m) +
      0.01608 * s(2 * mp) +
      0.01039 * s(2 * f) +
      0.00739 * e * s(mp - m) -
      0.00514 * e * s(mp + m) +
      0.00208 * e * e * s(2 * m) -
      0.00111 * s(mp - 2 * f) -
      0.00057 * s(mp + 2 * f) +
      0.00056 * e * s(2 * mp + m) -
      0.00042 * s(3 * mp) +
      0.00042 * e * s(m + 2 * f) +
      0.00038 * e * s(m - 2 * f) -
      0.00024 * e * s(2 * mp - m) -
      0.00017 * s(om) -
      0.00007 * s(mp + 2 * m) +
      0.00004 * s(2 * mp - 2 * f) +
      0.00004 * s(3 * m) +
      0.00003 * s(mp + m - 2 * f) +
      0.00003 * s(2 * mp + 2 * f) -
      0.00003 * s(mp + m + 2 * f) +
      0.00003 * s(mp - m + 2 * f) -
      0.00002 * s(mp - m - 2 * f) -
      0.00002 * s(3 * mp + m) +
      0.00002 * s(4 * mp);
  // De tiempo terrestre a UTC (unos 70 s) y a la hora de China (UTC+8).
  const deltaT = 70 / 86400;
  final chinaJd = jde - deltaT + 8 / 24;
  final dayNumber = (chinaJd + 0.5).floor();
  // El día juliano 2440588 es el 1 de enero de 1970.
  final date = DateTime.utc(1970).add(Duration(days: dayNumber - 2440588));
  return DateTime(date.year, date.month, date.day);
}
