import 'package:regalos/features/family/application/family_controller.dart'
    show ChangeSelfPersonResult;
import 'package:regalos/features/family/application/self_person_gate.dart';

/// «¿Quién eres?» de mentira: apunta las respuestas, sin tocar la familia.
class FakeGate implements SelfPersonGateActions {
  /// Lo respondido, en orden.
  final List<String> calls = [];

  @override
  Future<ChangeSelfPersonResult> choose(String personId) async {
    calls.add('choose:$personId');
    return ChangeSelfPersonResult.localOnly;
  }

  @override
  Future<String> notOnList(String name) async {
    calls.add('notOnList:$name');
    return 'nueva';
  }

  @override
  Future<String> nobody(String name) async {
    calls.add('nobody:$name');
    return 'nueva';
  }
}
