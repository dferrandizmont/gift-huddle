/// Hybrid logical clock (HLC) used to stamp every field of the family
/// document.
///
/// A stamp is three pieces: the wall clock in milliseconds, a counter that
/// breaks ties inside the same millisecond and the id of the device that
/// wrote the value. Two stamps are ordered by millis, then counter, then node
/// id, so the order never depends on the wall clock being right.
library;

import 'dart:math';

import 'package:clock/clock.dart';

/// Largest counter value. When it overflows the clock moves to the next
/// millisecond and the counter restarts at zero.
const int kMaxHlcCounter = 0xFFFF;

/// Number of characters of a node id.
const int kHlcNodeLength = 10;

/// Digits of the milliseconds of a stamp.
///
/// The text form pads the milliseconds to this length, so the text of two
/// stamps sorts the same way as the stamps themselves. A stamp with more
/// digits would break that order, so it is refused.
const int kMaxHlcMillisDigits = 15;

/// Longest node id accepted in a stamp.
///
/// The node id is free text that comes from another phone, so it cannot be
/// trusted to be short.
const int kMaxHlcNodeLength = 64;

/// How much ahead of the clock of this device a stamp of another device can
/// be before it is refused.
///
/// A phone with the wrong date, or a made up stamp, could push the clock of
/// this device years ahead and make the other phones lose their changes.
const Duration kMaxHlcDrift = Duration(days: 1);

/// Characters used to build a node id.
const String kHlcNodeAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// An immutable point of the hybrid logical clock.
class Hlc implements Comparable<Hlc> {
  /// Wall clock milliseconds when the value was written.
  final int millis;

  /// Tie breaker for two writes inside the same millisecond.
  final int counter;

  /// Id of the device that wrote the value.
  final String node;

  /// Creates a stamp. [counter] must be between 0 and [kMaxHlcCounter].
  const Hlc({required this.millis, required this.counter, required this.node});

  /// Orders by millis, then counter, then node id.
  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) {
      return millis < other.millis ? -1 : 1;
    }
    if (counter != other.counter) {
      return counter < other.counter ? -1 : 1;
    }
    return node.compareTo(other.node);
  }

  /// Whether this stamp is older than [other].
  bool operator <(Hlc other) => compareTo(other) < 0;

  /// Whether this stamp is newer than [other].
  bool operator >(Hlc other) => compareTo(other) > 0;

  /// Whether this stamp is older than or equal to [other].
  bool operator <=(Hlc other) => compareTo(other) <= 0;

  /// Whether this stamp is newer than or equal to [other].
  bool operator >=(Hlc other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          other.millis == millis &&
          other.counter == counter &&
          other.node == node;

  @override
  int get hashCode => Object.hash(millis, counter, node);

  /// Text form of the stamp: `millis-counter-node`.
  ///
  /// The text sorts the same way as [compareTo]: millis are padded to 15
  /// digits and the counter to 4 hexadecimal digits, so a plain text
  /// comparison gives the same order as the numeric one.
  ///
  /// A stamp with more than [kMaxHlcMillisDigits] digits cannot be read
  /// back: [parse] refuses it.
  String pack() =>
      '${millis.toString().padLeft(15, '0')}-'
      '${counter.toRadixString(16).padLeft(4, '0')}-'
      '$node';

  /// Reads a stamp written by [pack]. Throws [FormatException] when the text
  /// is not a valid stamp.
  ///
  /// The stamp comes from another phone, so it is checked: the milliseconds
  /// cannot be longer than [kMaxHlcMillisDigits], the counter cannot be
  /// bigger than [kMaxHlcCounter] and the node cannot be empty nor longer
  /// than [kMaxHlcNodeLength].
  static Hlc parse(String packed) {
    final firstDash = packed.indexOf('-');
    if (firstDash < 0) {
      throw FormatException(
        'Invalid HLC "$packed": expected "millis-counter-node"',
      );
    }
    final secondDash = packed.indexOf('-', firstDash + 1);
    if (secondDash < 0) {
      throw FormatException(
        'Invalid HLC "$packed": expected "millis-counter-node"',
      );
    }
    final millisPart = packed.substring(0, firstDash);
    final counterPart = packed.substring(firstDash + 1, secondDash);
    final node = packed.substring(secondDash + 1);
    if (millisPart.isEmpty || !_isDecimal(millisPart)) {
      throw FormatException(
        'Invalid HLC "$packed": millis must be a decimal number',
      );
    }
    if (millisPart.length > kMaxHlcMillisDigits) {
      throw FormatException(
        'Invalid HLC "$packed": millis cannot have more than '
        '$kMaxHlcMillisDigits digits',
      );
    }
    if (counterPart.isEmpty || !_isHexadecimal(counterPart)) {
      throw FormatException(
        'Invalid HLC "$packed": counter must be a hexadecimal number',
      );
    }
    final counter = int.tryParse(counterPart, radix: 16);
    if (counter == null || counter > kMaxHlcCounter) {
      throw FormatException(
        'Invalid HLC "$packed": the counter cannot be bigger than '
        '$kMaxHlcCounter',
      );
    }
    if (node.isEmpty) {
      throw FormatException('Invalid HLC "$packed": node must not be empty');
    }
    if (node.length > kMaxHlcNodeLength) {
      throw FormatException(
        'Invalid HLC "$packed": the node cannot be longer than '
        '$kMaxHlcNodeLength characters',
      );
    }
    return Hlc(millis: int.parse(millisPart), counter: counter, node: node);
  }

  static bool _isDecimal(String value) {
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) {
        return false;
      }
    }
    return true;
  }

  static bool _isHexadecimal(String value) {
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39;
      final isLower = code >= 0x61 && code <= 0x66;
      final isUpper = code >= 0x41 && code <= 0x46;
      if (!isDigit && !isLower && !isUpper) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => pack();
}

/// Thrown when a stamp of another device is too far ahead of the clock.
///
/// The clock does not move when this is thrown: the stamp is simply ignored.
class HlcDriftException implements Exception {
  /// The stamp that was refused.
  final Hlc remote;

  /// How much ahead of the clock of this device the stamp was.
  final Duration lead;

  /// Creates the exception.
  const HlcDriftException({required this.remote, required this.lead});

  @override
  String toString() =>
      'HlcDriftException(${remote.pack()} is ${lead.inSeconds}s ahead of '
      'the clock)';
}

/// The hybrid logical clock of one device.
///
/// It never goes backwards, even if the wall clock of the device does, and
/// [receive] pulls it forward when another device sends a newer stamp.
class HlcClock {
  /// Id of this device, used as the third part of every stamp.
  final String node;

  Hlc _last;

  /// Creates a clock for [node]. [last] sets the state the clock resumes
  /// from, useful to keep it in sync with the stored document.
  HlcClock({required this.node, Hlc? last})
    : _last = last ?? Hlc(millis: 0, counter: 0, node: node);

  /// The last stamp written by this clock.
  Hlc get last => _last;

  /// Returns a stamp that is strictly newer than every stamp of this clock.
  Hlc now() {
    final physical = clock.now().millisecondsSinceEpoch;
    int millis;
    int counter;
    if (physical > _last.millis) {
      millis = physical;
      counter = 0;
    } else {
      millis = _last.millis;
      counter = _last.counter + 1;
      if (counter > kMaxHlcCounter) {
        millis += 1;
        counter = 0;
      }
    }
    _last = Hlc(millis: millis, counter: counter, node: node);
    return _last;
  }

  /// Takes a stamp written by another device and moves this clock forward so
  /// that the next [now] is newer than [remote].
  ///
  /// Throws [HlcDriftException] when the stamp is more than [kMaxHlcDrift]
  /// ahead of the clock of this device. In that case the clock does not move:
  /// a phone with the wrong date cannot push this one years ahead.
  void receive(Hlc remote) {
    final physical = clock.now().millisecondsSinceEpoch;
    final limit = physical + kMaxHlcDrift.inMilliseconds;
    if (remote.millis > limit) {
      throw HlcDriftException(
        remote: remote,
        lead: Duration(milliseconds: remote.millis - physical),
      );
    }
    final last = _last;
    var millis = max(physical, max(last.millis, remote.millis));
    int counter;
    if (millis == last.millis && millis == remote.millis) {
      counter = max(last.counter, remote.counter) + 1;
    } else if (millis == last.millis) {
      counter = last.counter + 1;
    } else if (millis == remote.millis) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }
    if (counter > kMaxHlcCounter) {
      millis += 1;
      counter = 0;
    }
    _last = Hlc(millis: millis, counter: counter, node: node);
  }

  /// A new random node id: ten characters of `[a-z0-9]`.
  static String newNode() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < kHlcNodeLength; i++) {
      buffer.write(kHlcNodeAlphabet[random.nextInt(kHlcNodeAlphabet.length)]);
    }
    return buffer.toString();
  }
}
