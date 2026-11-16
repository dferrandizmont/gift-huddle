import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/hlc.dart';

/// A clock the test moves by hand.
class StepClock {
  StepClock(this._now);

  DateTime _now;

  /// The current time.
  DateTime call() => _now;

  /// Moves the clock forward.
  void advance(Duration duration) => _now = _now.add(duration);

  /// Moves the clock backwards.
  void rewind(Duration duration) => _now = _now.subtract(duration);

  /// Sets the clock to an exact time.
  void setTo(DateTime time) => _now = time;
}

/// A random node id without dashes.
String randomNode(Random random) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final length = 1 + random.nextInt(10);
  return String.fromCharCodes(
    List<int>.generate(
      length,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ),
  );
}

void main() {
  final base = DateTime.utc(2026, 11, 9, 10);

  group('marca', () {
    test('ordena por milisegundos, contador y nodo', () {
      const a = Hlc(millis: 10, counter: 0, node: 'a');
      const b = Hlc(millis: 10, counter: 1, node: 'a');
      const c = Hlc(millis: 11, counter: 0, node: 'a');
      const d = Hlc(millis: 10, counter: 0, node: 'b');

      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(c), lessThan(0));
      expect(a.compareTo(d), lessThan(0));
      expect(d.compareTo(a), greaterThan(0));
      expect(a.compareTo(a), 0);
      expect(b > a, isTrue);
      expect(c > b, isTrue);
    });

    test('dos marcas con el mismo valor son iguales', () {
      const a = Hlc(millis: 10, counter: 3, node: 'abc');
      const b = Hlc(millis: 10, counter: 3, node: 'abc');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == const Hlc(millis: 10, counter: 4, node: 'abc'), isFalse);
    });

    test('el texto ordena igual que la comparación', () {
      final random = Random(20261109);
      for (var i = 0; i < 1000; i++) {
        final a = Hlc(
          millis: random.nextInt(1 << 20) << 20 | random.nextInt(1 << 20),
          counter: random.nextInt(0x10000),
          node: randomNode(random),
        );
        final b = Hlc(
          millis: random.nextInt(1 << 20) << 20 | random.nextInt(1 << 20),
          counter: random.nextInt(0x10000),
          node: randomNode(random),
        );
        expect(
          a.compareTo(b).sign,
          equals(a.pack().compareTo(b.pack()).sign),
          reason: 'a=$a b=$b',
        );
      }
    });

    test('el texto ordena igual con guiones en el nodo y 15 dígitos', () {
      const nodes = <String>[
        'a',
        'a-b',
        'ab',
        'a-b-c',
        'a-',
        'b',
        'aaaa',
        'z9',
      ];
      const millis = <int>[
        0,
        1,
        999999999999999,
        100000000000000,
        1760000000000,
      ];
      for (final nodeA in nodes) {
        for (final nodeB in nodes) {
          for (final millisA in millis) {
            for (final millisB in millis) {
              final a = Hlc(millis: millisA, counter: 0, node: nodeA);
              final b = Hlc(millis: millisB, counter: 0, node: nodeB);
              expect(
                a.compareTo(b).sign,
                equals(a.pack().compareTo(b.pack()).sign),
                reason: 'a=$a b=$b',
              );
            }
          }
        }
      }
    });

    test('un nodo con guiones se vuelve a leer igual', () {
      const stamp = Hlc(millis: 42, counter: 16, node: 'a-b');
      expect(Hlc.parse(stamp.pack()), equals(stamp));
    });

    test('el texto se vuelve a leer igual', () {
      final random = Random(7);
      for (var i = 0; i < 1000; i++) {
        final stamp = Hlc(
          millis: random.nextInt(1 << 20) << 20 | random.nextInt(1 << 20),
          counter: random.nextInt(0x10000),
          node: randomNode(random),
        );
        expect(Hlc.parse(stamp.pack()), equals(stamp));
      }
    });

    test('el texto lleva milisegundos y contador de tamaño fijo', () {
      const stamp = Hlc(millis: 42, counter: 16, node: 'abc');
      expect(stamp.pack(), equals('000000000000042-0010-abc'));
    });

    test('un texto inválido se rechaza', () {
      expect(() => Hlc.parse('nada'), throwsFormatException);
      expect(() => Hlc.parse('12-abc'), throwsFormatException);
      expect(() => Hlc.parse('12-zz-node'), throwsFormatException);
      expect(() => Hlc.parse('ab-1-node'), throwsFormatException);
      expect(() => Hlc.parse('12-1-'), throwsFormatException);
    });

    test('una marca con demasiados milisegundos se rechaza', () {
      expect(() => Hlc.parse('1234567890123456-0-n'), throwsFormatException);
    });

    test('una marca con el contador demasiado grande se rechaza', () {
      expect(() => Hlc.parse('12-10000-n'), throwsFormatException);
    });

    test('una marca con el nodo vacío o demasiado largo se rechaza', () {
      expect(() => Hlc.parse('12-0-'), throwsFormatException);
      expect(
        () => Hlc.parse('12-0-${'a' * (kMaxHlcNodeLength + 1)}'),
        throwsFormatException,
      );
    });

    test('una marca con el nodo más largo de lo permitido se lee', () {
      final node = 'a' * kMaxHlcNodeLength;
      final stamp = Hlc(millis: 42, counter: 0, node: node);
      expect(Hlc.parse(stamp.pack()), equals(stamp));
    });
  });

  group('reloj', () {
    test('avanza con el reloj del sistema', () {
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock.fixed(base), () {
        final first = clock.now();
        expect(first.millis, equals(base.millisecondsSinceEpoch));
        expect(first.counter, equals(0));
        final second = clock.now();
        expect(second > first, isTrue);
        expect(second.millis, equals(first.millis));
        expect(second.counter, equals(1));
      });
    });

    test('sigue creciendo cuando el reloj del sistema retrocede', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        final first = clock.now();
        source.rewind(const Duration(hours: 2));
        final second = clock.now();
        expect(second > first, isTrue);
        expect(second.millis, equals(first.millis));
        expect(second.counter, equals(first.counter + 1));
        source.rewind(const Duration(days: 30));
        final third = clock.now();
        expect(third > second, isTrue);
      });
    });

    test('el reloj físico manda cuando va por delante', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        clock.now();
        source.advance(const Duration(minutes: 5));
        final stamp = clock.now();
        expect(stamp.millis, equals(base.millisecondsSinceEpoch + 300000));
        expect(stamp.counter, equals(0));
      });
    });

    test('recibe una marca remota una hora por delante', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        final local = clock.now();
        final remote = Hlc(
          millis: base.millisecondsSinceEpoch + 3600000,
          counter: 0,
          node: 'bbbb',
        );
        clock.receive(remote);
        final next = clock.now();
        expect(next > remote, isTrue);
        expect(next > local, isTrue);
        expect(next.millis, equals(remote.millis));
      });
    });

    test('recibir una marca remota antigua no atrasa el reloj', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        final local = clock.now();
        final remote = Hlc(
          millis: base.millisecondsSinceEpoch - 3600000,
          counter: 0,
          node: 'bbbb',
        );
        clock.receive(remote);
        final next = clock.now();
        expect(next > local, isTrue);
        expect(next.millis, equals(local.millis));
      });
    });

    test('el contador se desborda al millisegundo siguiente', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        for (var i = 0; i < 65536; i++) {
          clock.now();
        }
        expect(clock.last.counter, equals(0xFFFF));
        final overflow = clock.now();
        expect(overflow.millis, equals(base.millisecondsSinceEpoch + 1));
        expect(overflow.counter, equals(0));
      });
    });

    test('el contador se desborda también al recibir', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        clock.receive(
          Hlc(
            millis: base.millisecondsSinceEpoch,
            counter: 0xFFFF,
            node: 'bbbb',
          ),
        );
        expect(clock.last.millis, equals(base.millisecondsSinceEpoch + 1));
        expect(clock.last.counter, equals(0));
      });
    });

    test('una marca remota demasiado adelantada se rechaza', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        final local = clock.now();
        final tenYears = const Duration(days: 3650);
        final remote = Hlc(
          millis: base.millisecondsSinceEpoch + tenYears.inMilliseconds,
          counter: 0,
          node: 'bbbb',
        );

        expect(
          () => clock.receive(remote),
          throwsA(
            isA<HlcDriftException>().having(
              (error) => error.lead,
              'lead',
              equals(tenYears),
            ),
          ),
        );

        // El reloj no se mueve: la marca hostil no envenena el reloj.
        expect(clock.last, equals(local));
        expect(clock.now().millis, equals(local.millis));
      });
    });

    test('una marca remota dentro de la deriva sí se acepta', () {
      final source = StepClock(base);
      final clock = HlcClock(node: 'aaaa');
      withClock(Clock(source.call), () {
        final remote = Hlc(
          millis: base.millisecondsSinceEpoch + kMaxHlcDrift.inMilliseconds,
          counter: 0,
          node: 'bbbb',
        );
        clock.receive(remote);
        expect(clock.last.millis, equals(remote.millis));
      });
    });

    test('el nodo nuevo son diez caracteres al azar', () {
      final node = HlcClock.newNode();
      expect(node.length, equals(10));
      expect(RegExp(r'^[a-z0-9]{10}$').hasMatch(node), isTrue);
      expect(HlcClock.newNode(), isNot(equals(node)));
    });
  });
}
