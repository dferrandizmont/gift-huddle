import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:regalos/core/motion/haptics.dart';

/// Una vibración pedida al servicio simulado.
class HapticCall {
  const HapticCall(this.level, this.after, {this.supersede = false});

  final HapticLevel level;
  final Duration after;
  final bool supersede;

  @override
  String toString() => '$level+${after.inMilliseconds}ms';
}

/// El servicio de vibraciones de las pruebas de pantalla: no suena, apunta lo
/// que se le pide (nivel y espera) sin temporizadores ni antirrebote.
class FakeHaptics extends Haptics {
  FakeHaptics() : super(enabled: () => true);

  /// Lo pedido, en orden.
  final List<HapticCall> calls = <HapticCall>[];

  /// Solo los niveles, en orden.
  List<HapticLevel> get levels => [for (final c in calls) c.level];

  @override
  void play(
    HapticLevel level, {
    Duration after = Duration.zero,
    bool supersede = false,
  }) => calls.add(HapticCall(level, after, supersede: supersede));

  /// Lo pedido como texto: `light+160` (nivel y espera en ms).
  List<String> get log => [
    for (final c in calls) '${c.level.name}+${c.after.inMilliseconds}',
  ];

  /// Se pasa a `screenTest(overrides:)` o a un `ProviderScope`.
  Override get provide => hapticsProvider.overrideWithValue(this);
}
