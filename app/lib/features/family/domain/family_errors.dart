import '../../../core/sync/model.dart';

/// Se pide algo que necesita una familia y todavía no hay ninguna.
class NoFamilyException implements Exception {
  /// Crea el error.
  const NoFamilyException();

  @override
  String toString() => 'NoFamilyException: todavía no hay familia';
}

/// Se quiere crear una familia y este móvil ya tiene una con datos.
class FamilyAlreadyExistsException implements Exception {
  /// Crea el error.
  const FamilyAlreadyExistsException();

  @override
  String toString() => 'FamilyAlreadyExistsException';
}

/// Unirse a otra familia sustituiría la que este móvil ya tiene con datos.
///
/// La interfaz pide confirmación y repite con `replace: true`.
class FamilyConflictException implements Exception {
  /// Crea el error.
  const FamilyConflictException({required this.existingListId});

  /// Lista que se perdería.
  final String existingListId;

  @override
  String toString() =>
      'FamilyConflictException: ya hay la lista $existingListId';
}

/// Este móvil ya está en v2 y ha leído un QR (o una invitación) de v1, que
/// lleva la clave de la familia: no se usa (revisión de la fase 2b, hallazgo
/// 13). El otro móvil tiene que actualizarse y enseñar el QR nuevo.
class V1PairingOnV2Exception implements Exception {
  /// Crea el error.
  const V1PairingOnV2Exception();

  @override
  String toString() => 'V1PairingOnV2Exception';
}

/// El otro móvil tiene el reloj demasiado adelantado (más de un día): sus
/// cambios dejarían fechas imposibles. Se rechaza el sobre.
class ImportClockDriftException implements Exception {
  /// Crea el error.
  const ImportClockDriftException({required this.ahead});

  /// Cuánto va adelantado.
  final Duration ahead;

  @override
  String toString() =>
      'ImportClockDriftException: el otro móvil va ${ahead.inHours} h adelantado';
}

/// De qué móvil de la familia es dueña una persona.
enum DevicePersonOwner {
  /// De este: es «Yo» (`FamilyIdentity.selfRecipientId`).
  thisDevice,

  /// De otro móvil conectado de la familia.
  otherDevice,
}

/// Se quiere archivar o eliminar a una persona que es dueña de un móvil de la
/// familia (`FamilyState.isDevicePerson`). No se escribe nada.
class DevicePersonException implements Exception {
  /// Crea el error.
  const DevicePersonException({required this.recipientId, required this.owner});

  /// La persona.
  final String recipientId;

  /// De qué móvil es dueña.
  final DevicePersonOwner owner;

  @override
  String toString() =>
      'DevicePersonException: $recipientId es la persona de '
      '${owner == DevicePersonOwner.thisDevice ? 'este móvil' : 'otro móvil'}';
}

/// A protected gift can use this person after a separate public giver add.
class GiverPersonNeedsPublicAdd implements Exception {
  const GiverPersonNeedsPublicAdd(this.personId);

  final String personId;
}

/// The outcome of writing a gift assignment. A protected gift that needs a
/// separate public add throws [GiverPersonNeedsPublicAdd].
enum GiftWriteResult {
  saved,
  giftDeleted,
  giftUnavailable,
  recipientUnavailable,
  invalidPair,
  giverUnavailable,
  giverArchived,
  giverPersonUnavailable,
  giverPersonArchived,
}

/// Lo que cambió al mezclar un documento recibido.
class ImportSummary {
  /// Crea el resumen.
  const ImportSummary({
    this.giftsAdded = 0,
    this.giftsChanged = 0,
    this.giftsDeleted = 0,
    this.docChanged = false,
  });

  /// Compara las vistas de antes y después de mezclar.
  factory ImportSummary.between(
    FamilyView before,
    FamilyView after, {
    required bool docChanged,
  }) {
    final oldGifts = {for (final g in before.gifts) g.id: g};
    final newGifts = {for (final g in after.gifts) g.id: g};
    var added = 0;
    var changed = 0;
    var deleted = 0;
    for (final entry in newGifts.entries) {
      final old = oldGifts[entry.key];
      if (old == null) {
        added++;
      } else if (old != entry.value) {
        changed++;
      }
    }
    for (final id in oldGifts.keys) {
      if (!newGifts.containsKey(id)) {
        deleted++;
      }
    }
    return ImportSummary(
      giftsAdded: added,
      giftsChanged: changed,
      giftsDeleted: deleted,
      docChanged: docChanged,
    );
  }

  /// Regalos nuevos.
  final int giftsAdded;

  /// Regalos que han cambiado.
  final int giftsChanged;

  /// Regalos borrados.
  final int giftsDeleted;

  /// Si el documento cambió en algo (también personas, ocasiones...).
  final bool docChanged;

  @override
  String toString() =>
      'ImportSummary(+$giftsAdded ~$giftsChanged -$giftsDeleted, '
      'docChanged: $docChanged)';
}
