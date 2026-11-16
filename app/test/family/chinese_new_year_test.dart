import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/domain/chinese_new_year.dart';

void main() {
  group('Año Nuevo Chino', () {
    test('la tabla cubre de 2026 a 2040 con las fechas conocidas', () {
      expect(kChineseNewYearTable.length, 15);
      expect(chineseNewYearOf(2026), DateTime(2026, 2, 17));
      expect(chineseNewYearOf(2027), DateTime(2027, 2, 6));
      expect(chineseNewYearOf(2028), DateTime(2028, 1, 26));
      expect(chineseNewYearOf(2034), DateTime(2034, 2, 19));
      expect(chineseNewYearOf(2040), DateTime(2040, 2, 12));
      for (
        var y = kChineseNewYearFirstYear;
        y <= kChineseNewYearLastYear;
        y++
      ) {
        final d = chineseNewYearOf(y);
        expect(d.year, y);
        // Siempre entre el 21 de enero y el 20 de febrero.
        expect(
          d.isBefore(DateTime(y, 1, 21)) || d.isAfter(DateTime(y, 2, 20)),
          isFalse,
          reason: '$y: $d',
        );
      }
    });

    test('el cálculo con la luna nueva coincide con la tabla', () {
      for (
        var y = kChineseNewYearFirstYear;
        y <= kChineseNewYearLastYear;
        y++
      ) {
        expect(
          approximateChineseNewYear(y),
          chineseNewYearOf(y),
          reason: 'año $y',
        );
      }
    });

    test('fuera de la tabla se calcula (2041 y 2025)', () {
      expect(chineseNewYearOf(2041), DateTime(2041, 2, 1));
      expect(chineseNewYearOf(2042), DateTime(2042, 1, 22));
      expect(chineseNewYearOf(2025), DateTime(2025, 1, 29));
    });

    test('la siguiente cuenta hoy y salta al año siguiente cuando pasa', () {
      expect(nextChineseNewYear(DateTime(2026, 11, 9)), DateTime(2027, 2, 6));
      expect(nextChineseNewYear(DateTime(2027, 2, 6)), DateTime(2027, 2, 6));
      expect(nextChineseNewYear(DateTime(2027, 2, 7)), DateTime(2028, 1, 26));
      expect(nextChineseNewYear(DateTime(2026, 1, 1)), DateTime(2026, 2, 17));
      expect(nextChineseNewYear(DateTime(2040, 3, 1)), DateTime(2041, 2, 1));
    });
  });
}
