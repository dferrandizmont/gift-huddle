import 'package:intl/intl.dart';

import '../sync/model.dart';

/// Día y mes de una ocasión en corto: «24 dic».
String shortDayMonth(int month, int day, String locale) =>
    DateFormat.MMMd(locale).format(DateTime(2028, month, day));

/// Día y mes de una ocasión en largo: «6 de enero».
String longDayMonth(int month, int day, String locale) =>
    DateFormat.MMMMd(locale).format(DateTime(2028, month, day));

/// Fecha corta de un día concreto: «24 dic».
String shortDate(DateTime date, String locale) =>
    DateFormat.MMMd(locale).format(date);

/// Edad en años de quien nació en [birthYear], o `null` si no se sabe el año.
///
/// Si ya conoce el mes y el día, descuenta un año hasta el cumpleaños.
int? ageOf(Recipient recipient, DateTime now) {
  final year = recipient.birthYear;
  if (year == null) {
    return null;
  }
  var age = now.year - year;
  final month = recipient.birthMonth;
  final day = recipient.birthDay;
  if (month != null && day != null) {
    final birthdayPassed =
        now.month > month || (now.month == month && now.day >= day);
    if (!birthdayPassed) {
      age -= 1;
    }
  }
  return age < 0 ? null : age;
}
