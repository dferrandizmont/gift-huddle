/// La frontera del documento común para los deseos (ADR 0010, 1.0.7).
///
/// Por aquí pasa todo común que entra (sincronización, fichero, recuperación)
/// o sale (subida, sobre, intercambio): lo privado de los planes no cabe en
/// él, y los deseos tienen una única forma.
///
/// Dart puro, sin Flutter.
library;

import 'family_doc.dart';
import 'model.dart';
import 'wish.dart';

/// Campos que solo existen en un plan del bloque secreto: el enlace con el
/// deseo, quien lo coge y lo que apunta quien regala. Nunca van en el
/// documento común.
const Set<String> kWishPlanOnlyFields = {
  'sourceWishId',
  'claimantPersonId',
  'purchaseUrl',
  'giverNote',
};

/// La frontera del documento común para los deseos.
extension WishBoundary on FamilyDoc {
  /// Este documento tal como puede entrar o salir como común:
  ///
  /// - sin colecciones privadas reservadas (`wishPlans`);
  /// - sin registros que lleven campos de plan (`sourceWishId`, ...) en
  ///   ninguna colección;
  /// - con los deseos en su única forma ([FamilyDoc.normalizedWishes]) y sin
  ///   los que no pasan [validateWishRecord].
  ///
  /// Devuelve el mismo documento si no hay nada que cambiar, así que es
  /// barato en cada frontera. No toca el documento local de nadie.
  FamilyDoc wishBoundary() {
    final normalized = normalizedWishes();
    var changed = !identical(normalized, this);
    final out = <String, Map<String, SyncRecord>>{};
    for (final entry in normalized.collections.entries) {
      final name = entry.key;
      if (name == ScopeCollections.wishPlans) {
        changed = true;
        continue;
      }
      final records = entry.value;
      Map<String, SyncRecord>? kept;
      for (final e in records.entries) {
        final record = e.value;
        final bad = name == Collections.wishes
            ? validateWishRecord(record) != null
            : record.fields.keys.any(kWishPlanOnlyFields.contains);
        if (bad) {
          kept ??= {...records};
          kept.remove(e.key);
        }
      }
      if (kept != null) changed = true;
      out[name] = kept ?? records;
    }
    if (!changed) return this;
    return FamilyDoc(listId: listId, collections: out);
  }
}
