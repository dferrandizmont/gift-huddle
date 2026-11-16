import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../family/application/family_controller.dart';

/// El estado de la familia ahora mismo.
///
/// `familyControllerProvider.future` puede devolver el valor anterior cuando el
/// estado acaba de cambiar en el mismo instante; el valor ya publicado manda.
Future<FamilyState> familySnapshot(Ref ref) async {
  final current = ref.read(familyControllerProvider).value;
  return current ?? await ref.read(familyControllerProvider.future);
}
