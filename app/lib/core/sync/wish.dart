/// Deseos visibles (ADR 0010, 1.0.7): lo que una persona apunta para sí o le
/// sugieren con «Visible para ...». Viven en `Collections.wishes` del
/// documento común, aparte de los regalos: no llevan precios, tienda, notas
/// ni estado, y lo que hagan los demás con ellos no se escribe aquí.
///
/// Dart puro, sin Flutter. Los permisos se aplican en esta API (no en la
/// pantalla): solo P, la persona destinataria, edita o quita; quien sugiere
/// solo crea.
library;

import 'dart:convert';
import 'dart:math';

import 'family_doc.dart';
import 'hlc.dart';
import 'model.dart';
import 'device_keys.dart' show kSyncIdPattern;
import 'wish_author.dart';

/// Deseos vivos como máximo por persona destinataria.
const int kMaxLiveWishesPerRecipient = 200;

/// Bytes UTF-8 como máximo del registro de un deseo tal como se serializa
/// (con sus marcas y los campos vaciados), medido por [wishRecordBytes].
const int kMaxWishVisibleBytes = 1900;

/// Bytes UTF-8 como máximo de lo que el plan del bloque secreto copiará de un
/// deseo: `title`, `size` y `url` (cada uno como texto JSON, con sus comillas
/// y escapes), medido por [wishCopyBytes].
///
/// Un plan mínimo lleva además `planId`, `recipientId`, `sourceWishId`,
/// `claimantPersonId` y `status`, cada campo con su marca. Con ids de 36
/// caracteres y marcas de 31 el plan, sin lo copiado, ocupa unos 590 bytes
/// serializado; con 1.200 copiados quedan unos 100 bytes de margen bajo los
/// 1.900 del registro secreto (la prueba `wish_model_test` lo comprueba).
const int kMaxWishCopyBytes = 1200;

/// Los bytes UTF-8 de [title], [size] y [url] como los copiará un plan.
int wishCopyBytes({String? title, String? size, String? url}) => [
  title,
  size,
  url,
].whereType<String>().fold(0, (n, s) => n + utf8.encode(jsonEncode(s)).length);

int _recordCopyBytes(SyncRecord r) => wishCopyBytes(
  title: r['title'] is String ? r['title'] as String : null,
  size: r['size'] is String ? r['size'] as String : null,
  url: r['url'] is String ? r['url'] as String : null,
);

/// Los campos visibles de un deseo.
enum WishField {
  /// Qué se desea (obligatorio).
  title,

  /// Año al que pertenece (obligatorio).
  year,

  /// Ocasión.
  occasionId,

  /// Talla o edad.
  size,

  /// Enlace.
  url,

  /// Descripción.
  description,
}

/// Por qué una operación sobre un deseo no se hizo. No escribe nada.
enum WishError {
  /// Solo la persona destinataria edita o quita su deseo.
  notWishOwner,

  /// No existe ese deseo.
  wishNotFound,

  /// El deseo ya se quitó.
  wishRemoved,

  /// La persona destinataria no existe (o está borrada).
  recipientUnavailable,

  /// Una persona no se sugiere deseos a sí misma: usa `createOwnWish`.
  suggestionForSelf,

  /// Ya hay 200 deseos vivos para esa persona.
  capReached,

  /// Los campos visibles pasarían de 1.900 bytes.
  tooLarge,

  /// Falta el título o el año, o un valor no vale.
  invalidField,

  /// Ese id ya se usó (también por un deseo quitado: no se reutiliza).
  idInUse,

  /// Este dispositivo no puede escribir deseos ([WishWrite.authorError] dice
  /// por qué).
  authorRefused,

  /// Solo se sugiere un deseo a una persona que tiene algún dispositivo en
  /// el registro (sin móvil, como Leo, no hay a quién enseñárselo).
  recipientHasNoDevice,
}

/// El resultado de una operación: el documento nuevo o un error tipado.
final class WishWrite {
  const WishWrite._(this.doc, this.error, this.wishId, [this.authorError]);

  /// El documento resultante (el mismo, sin cambios, si hay [error]).
  final FamilyDoc doc;

  /// Qué falló, o null.
  final WishError? error;

  /// Con [WishError.authorRefused], por qué.
  final WishAuthorError? authorError;

  /// El id del deseo creado, editado o quitado.
  final String? wishId;

  /// Si se hizo.
  bool get ok => error == null;
}

/// Cambios a los campos visibles de un deseo. Tipo propio: no es un
/// `Gift` ni sus campos.
final class VisibleWishPatch {
  /// Crea un parche. Un campo null no se toca; para vaciar un campo
  /// opcional, [clear].
  const VisibleWishPatch({
    this.title,
    this.year,
    this.occasionId,
    this.size,
    this.url,
    this.description,
    this.clear = const {},
  });

  /// Nuevo título.
  final String? title;

  /// Nuevo año.
  final int? year;

  /// Nueva ocasión.
  final String? occasionId;

  /// Nueva talla o edad.
  final String? size;

  /// Nuevo enlace.
  final String? url;

  /// Nueva descripción.
  final String? description;

  /// Campos opcionales que se vacían (`occasionId`, `size`, `url`,
  /// `description`).
  final Set<WishField> clear;
}

/// Un deseo visible.
class Wish {
  /// Crea un deseo.
  const Wish({
    required this.id,
    required this.recipientId,
    required this.authorPersonId,
    required this.suggested,
    required this.title,
    required this.year,
    this.occasionId,
    this.size,
    this.url,
    this.description,
  });

  /// Id del deseo (aleatorio, nunca se reutiliza).
  final String id;

  /// La persona a la que le gustaría.
  final String recipientId;

  /// Quién lo creó: la propia persona o quien lo sugirió.
  final String authorPersonId;

  /// Si lo creó alguien que no es [recipientId].
  final bool suggested;

  /// Qué se desea.
  final String title;

  /// Año.
  final int year;

  /// Ocasión.
  final String? occasionId;

  /// Talla o edad.
  final String? size;

  /// Enlace.
  final String? url;

  /// Descripción.
  final String? description;

  /// Los nombres de los campos que forman un deseo: la lista **positiva**.
  /// Nada que no esté aquí sale de un deseo, aunque el registro lo tenga.
  static const List<String> fieldNames = [
    'recipientId',
    'authorPersonId',
    'suggested',
    'title',
    'year',
    'occasionId',
    'size',
    'url',
    'description',
  ];

  /// El deseo de [record], o null si es una lápida o le falta algo.
  static Wish? fromRecord(SyncRecord record) {
    if (record.isDeleted) return null;
    final recipientId = _str(record['recipientId']);
    final author = _str(record['authorPersonId']);
    final suggested = record['suggested'];
    final title = _str(record['title']);
    final year = record['year'];
    if (recipientId == null ||
        author == null ||
        suggested is! bool ||
        title == null ||
        year is! int) {
      return null;
    }
    return Wish(
      id: record.id,
      recipientId: recipientId,
      authorPersonId: author,
      suggested: suggested,
      title: title,
      year: year,
      occasionId: _str(record['occasionId']),
      size: _str(record['size']),
      url: _str(record['url']),
      description: _str(record['description']),
    );
  }

  /// Los campos visibles, con el id: solo la lista positiva y sin nulos.
  /// Es lo que se mide contra [kMaxWishVisibleBytes].
  Map<String, Object?> get visibleFields => <String, Object?>{
    'id': id,
    'recipientId': recipientId,
    'authorPersonId': authorPersonId,
    'suggested': suggested,
    'title': title,
    'year': year,
    if (occasionId != null) 'occasionId': occasionId,
    if (size != null) 'size': size,
    if (url != null) 'url': url,
    if (description != null) 'description': description,
  };

  @override
  bool operator ==(Object other) =>
      other is Wish &&
      canonicalJsonOf(other.visibleFields) == canonicalJsonOf(visibleFields);

  @override
  int get hashCode => canonicalJsonOf(visibleFields).hashCode;
}

String? _str(Object? v) => v is String ? v : null;

final Random _random = Random.secure();
const String _idAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// Un id nuevo y aleatorio de deseo.
String newWishId() {
  final b = StringBuffer('w');
  for (var i = 0; i < 16; i++) {
    b.write(_idAlphabet[_random.nextInt(_idAlphabet.length)]);
  }
  return b.toString();
}

String? _clean(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Los nombres de campo que puede llevar un registro de deseo: la lista
/// positiva más `deleted`.
final Set<String> _allowedNames = {...Wish.fieldNames, kDeletedField};

/// Bytes UTF-8 del registro [record] tal como se serializa en el documento
/// (`{"id":{"campo":[valor,"marca"]}}` en JSON canónico), con sus marcas
/// reales y los campos vaciados como `[null, marca]`.
int wishRecordBytes(SyncRecord record) {
  final fields = <String, Object?>{
    for (final e in record.fields.entries)
      e.key: <Object?>[e.value.value, e.value.stamp.pack()],
  };
  return utf8
      .encode(canonicalJsonOf(<String, Object?>{record.id: fields}))
      .length;
}

/// Qué está mal en la forma de un registro de `wishes`.
enum WishRecordProblem {
  /// Lleva un campo que no está en la lista positiva (ni es `deleted`).
  unknownField,

  /// Falta un campo obligatorio de un deseo vivo.
  missingField,

  /// Un campo tiene un tipo que no es el suyo.
  wrongType,

  /// Una lápida conserva contenido o no tiene `deleted: true`.
  tombstoneHasContent,
}

/// Comprueba la forma de un registro de la colección `wishes`: solo la lista
/// positiva de campos (más `deleted`). Una lápida es `deleted: true` con todo
/// lo demás vacío. Devuelve null si está bien. Pensada para las fronteras del
/// documento común (red, ficheros, recuperación). El tamaño no se comprueba
/// aquí: dos ediciones sin conexión que caben solas pueden pasar juntas del
/// tope y la fusión las conserva ([wishRecordBytes]).
WishRecordProblem? validateWishRecord(SyncRecord record) {
  if (record.fields.keys.any((name) => !_allowedNames.contains(name))) {
    return WishRecordProblem.unknownField;
  }
  if (record.isDeleted) {
    final empty = record.fields.entries.every(
      (e) => e.key == kDeletedField || e.value.value == null,
    );
    if (!empty) return WishRecordProblem.tombstoneHasContent;
    // Una sola forma: `deleted` y los nueve nombres, todos presentes.
    return record.fields.keys.toSet().length == _allowedNames.length
        ? null
        : WishRecordProblem.missingField;
  }
  final deleted = record[kDeletedField];
  if (deleted != null && deleted != false) {
    return WishRecordProblem.wrongType;
  }
  for (final name in const [
    'recipientId',
    'authorPersonId',
    'suggested',
    'title',
    'year',
  ]) {
    if (record[name] == null) return WishRecordProblem.missingField;
  }
  if (record['recipientId'] is! String ||
      record['authorPersonId'] is! String ||
      record['suggested'] is! bool ||
      record['title'] is! String ||
      (record['title'] as String).trim().isEmpty ||
      record['year'] is! int) {
    return WishRecordProblem.wrongType;
  }
  for (final name in const ['occasionId', 'size', 'url', 'description']) {
    final v = record[name];
    if (v != null && v is! String) return WishRecordProblem.wrongType;
  }
  return null;
}

/// Operaciones de deseos sobre el documento común. Las escrituras de un
/// deseo individual devuelven un [WishWrite]; con error no cambian el reloj
/// y devuelven el mismo documento.
///
/// En cada escritura individual, el autor se resuelve con el [WishContext]
/// (este dispositivo y el registro actual de la lista de este documento).
extension WishOperations on FamilyDoc {
  /// Los deseos vivos de [recipientId].
  List<Wish> wishesFor(String recipientId) => [
    for (final record in (collections[Collections.wishes] ?? const {}).values)
      if (Wish.fromRecord(record) case final Wish wish
          when wish.recipientId == recipientId)
        wish,
  ];

  /// Cuántos deseos vivos tiene [recipientId], también los que no se
  /// entienden del todo (un móvil nuevo podría escribir más campos).
  int liveWishCount(String recipientId) =>
      (collections[Collections.wishes] ?? const <String, SyncRecord>{}).values
          .where((r) => !r.isDeleted && r['recipientId'] == recipientId)
          .length;

  /// Cascada para el borrado autorizado de una persona de la lista.
  FamilyDoc deleteRecipientWithWishes(HlcClock clock, String recipientId) =>
      delete(
        clock,
        Collections.recipients,
        recipientId,
      ).tombstoneWishesForDeletedRecipients();

  /// Vacía los deseos de destinatarios con lápida, también los que llegan
  /// tarde de otro móvil. La lápida del destinatario da la marca de borrado.
  FamilyDoc tombstoneWishesForDeletedRecipients() {
    final wishes = collections[Collections.wishes];
    if (wishes == null) return this;
    Map<String, SyncRecord>? next;
    for (final entry in wishes.entries) {
      final record = entry.value;
      final recipient = record['recipientId'];
      if (record.isDeleted || recipient is! String) continue;
      final deletion = this
          .record(Collections.recipients, recipient)
          ?.field(kDeletedField);
      if (deletion == null || deletion.value != true) continue;
      final stamp = deletion.stamp;
      (next ??= {...wishes})[entry.key] = SyncRecord(
        id: record.id,
        fields: {
          kDeletedField: deletion,
          for (final name in Wish.fieldNames)
            name: FieldValue(
              value: null,
              stamp: switch (record.field(name)?.stamp) {
                final Hlc edit when edit > stamp => edit,
                _ => stamp,
              },
            ),
        },
      );
    }
    return next == null ? this : _withWishes(next);
  }

  /// Este documento con cada registro de `wishes` en su única forma.
  ///
  /// - Vivo: sin los campos que no están en la lista positiva (ni son
  ///   `deleted`).
  /// - Si su destinatario es una lápida, el deseo también. Esto cubre los
  ///   que llegan de otro móvil después de borrar a la persona.
  /// - Lápida: exactamente `deleted: true` y los nueve nombres como
  ///   `[null, marca]`; los que faltan se rellenan con la marca de la propia
  ///   lápida (`deleted`), y los de más se quitan.
  ///
  /// **Quita a propósito lo que esta versión no conoce**: el corte de versión
  /// de la 1.0.7 impide sincronizar con móviles anteriores o posteriores, así
  /// que un campo desconocido solo puede venir de una app modificada o de un
  /// fichero manipulado. Se devuelve el mismo documento si no hay nada que
  /// cambiar. Hay que llamarlo tras fusionar en las fronteras (una fusión
  /// genérica vuelve a traer los nombres que otro móvil aún tenga); es una
  /// función del documento fusionado, así que dos móviles con los mismos
  /// datos llegan al mismo resultado.
  FamilyDoc normalizedWishes() {
    final cascaded = tombstoneWishesForDeletedRecipients();
    final wishes = cascaded.collections[Collections.wishes];
    if (wishes == null) return cascaded;
    var changed = false;
    final next = <String, SyncRecord>{};
    for (final e in wishes.entries) {
      final record = e.value;
      final tombstone = record.isDeleted;
      final complete =
          !tombstone ||
          _allowedNames.every((name) => record.fields.containsKey(name));
      if (complete && record.fields.keys.every(_allowedNames.contains)) {
        next[e.key] = record;
        continue;
      }
      changed = true;
      final deletedStamp = record.fields[kDeletedField]?.stamp;
      next[e.key] = SyncRecord(
        id: record.id,
        fields: {
          for (final f in record.fields.entries)
            if (_allowedNames.contains(f.key)) f.key: f.value,
          if (tombstone && deletedStamp != null)
            for (final name in _allowedNames)
              if (!record.fields.containsKey(name))
                name: FieldValue(value: null, stamp: deletedStamp),
        },
      );
    }
    return changed ? cascaded._withWishes(next) : cascaded;
  }

  FamilyDoc _withWishes(Map<String, SyncRecord> wishes) => FamilyDoc(
    listId: listId,
    collections: {...collections, Collections.wishes: wishes},
  );

  /// [ctx] (este dispositivo) apunta un deseo para sí. Solo escribe en
  /// `wishes`.
  WishWrite createOwnWish(
    HlcClock clock,
    WishContext ctx,
    VisibleWishPatch patch, {
    String? id,
  }) {
    final author = ctx.resolve(listId);
    if (!author.ok) return _refused(author.error!);
    return _create(clock, author.author!, author.author!.personId, patch, id);
  }

  /// Este dispositivo sugiere un deseo visible para [recipientId] (otra
  /// persona, que tenga algún dispositivo en el registro). Desde entonces
  /// solo [recipientId] lo edita o lo quita.
  WishWrite suggestVisibleWish(
    HlcClock clock,
    WishContext ctx,
    String recipientId,
    VisibleWishPatch patch, {
    String? id,
  }) {
    final author = ctx.resolve(listId);
    if (!author.ok) return _refused(author.error!);
    if (recipientId == author.author!.personId) {
      return WishWrite._(this, WishError.suggestionForSelf, null);
    }
    if (!ctx.hasDevice(recipientId)) {
      return WishWrite._(this, WishError.recipientHasNoDevice, null);
    }
    return _create(clock, author.author!, recipientId, patch, id);
  }

  /// Este dispositivo cambia campos visibles del deseo [wishId]. Solo su
  /// destinataria. Los campos que no cambian conservan su marca. Un registro
  /// con campos de más (`plannedCents`, `store`, `note`...) los pierde al
  /// editarlo (decisión: se quitan, no se rechaza). Si el resultado pasa de
  /// [kMaxWishVisibleBytes] solo se admite una edición que no lo agrande.
  WishWrite editVisibleWish(
    HlcClock clock,
    WishContext ctx,
    String wishId,
    VisibleWishPatch patch,
  ) {
    final author = ctx.resolve(listId);
    if (!author.ok) return _refused(author.error!);
    final record = this.record(Collections.wishes, wishId);
    if (record == null) return WishWrite._(this, WishError.wishNotFound, null);
    if (record.isDeleted) {
      return WishWrite._(this, WishError.wishRemoved, wishId);
    }
    if (record['recipientId'] != author.author!.personId) {
      return WishWrite._(this, WishError.notWishOwner, wishId);
    }
    if (Wish.fromRecord(record) == null) {
      return WishWrite._(this, WishError.invalidField, wishId);
    }
    final changes = _changesOf(patch, creating: false);
    if (changes == null) {
      return WishWrite._(this, WishError.invalidField, wishId);
    }
    // Se prueba con una copia del reloj para medir el registro con sus marcas
    // reales antes de mover el de verdad.
    final scratch = HlcClock(node: clock.node, last: clock.last);
    final trial = setChanged(
      scratch,
      Collections.wishes,
      wishId,
      changes,
    ).normalizedWishes();
    final trialRecord = trial.record(Collections.wishes, wishId)!;
    final currentBytes = wishRecordBytes(
      normalizedWishes().record(Collections.wishes, wishId)!,
    );
    final bytes = wishRecordBytes(trialRecord);
    // Si ya pasa del tope (dos ediciones sin conexión fusionadas), se admite
    // lo que no agranda: guardar igual o más corto.
    if (bytes > kMaxWishVisibleBytes && bytes > currentBytes) {
      return WishWrite._(this, WishError.tooLarge, wishId);
    }
    final copy = _recordCopyBytes(trialRecord);
    final currentCopy = _recordCopyBytes(
      normalizedWishes().record(Collections.wishes, wishId)!,
    );
    if (copy > kMaxWishCopyBytes && copy > currentCopy) {
      return WishWrite._(this, WishError.tooLarge, wishId);
    }
    final next = setChanged(
      clock,
      Collections.wishes,
      wishId,
      changes,
    ).normalizedWishes();
    return WishWrite._(identical(next, this) ? this : next, null, wishId);
  }

  /// Este dispositivo quita el deseo [wishId]. Solo su destinataria. Escribe
  /// siempre la misma lápida mínima (los nueve campos vacíos y `deleted`,
  /// sin ningún nombre de más) y no se compacta nunca. Quitar uno ya quitado
  /// no hace nada.
  WishWrite removeWish(HlcClock clock, WishContext ctx, String wishId) {
    final author = ctx.resolve(listId);
    if (!author.ok) return _refused(author.error!);
    final record = this.record(Collections.wishes, wishId);
    if (record == null) return WishWrite._(this, WishError.wishNotFound, null);
    if (record.isDeleted) {
      // Una lápida vacía no dice de quién era: quitar dos veces es inocuo.
      return WishWrite._(normalizedWishes(), null, wishId);
    }
    if (record['recipientId'] != author.author!.personId) {
      return WishWrite._(this, WishError.notWishOwner, wishId);
    }
    final next = set(clock, Collections.wishes, wishId, <String, Object?>{
      for (final name in Wish.fieldNames) name: null,
      kDeletedField: true,
    }).normalizedWishes();
    return WishWrite._(next, null, wishId);
  }

  WishWrite _refused(WishAuthorError error) =>
      WishWrite._(this, WishError.authorRefused, null, error);

  WishWrite _create(
    HlcClock clock,
    WishAuthor author,
    String recipientId,
    VisibleWishPatch patch,
    String? explicitId,
  ) {
    final recipient = record(Collections.recipients, recipientId);
    if (recipient == null || recipient.isDeleted) {
      return WishWrite._(this, WishError.recipientUnavailable, null);
    }
    final changes = _changesOf(patch, creating: true);
    if (changes == null) return WishWrite._(this, WishError.invalidField, null);
    final wishes = collections[Collections.wishes] ?? const {};
    String id;
    if (explicitId != null) {
      if (!kSyncIdPattern.hasMatch(explicitId)) {
        return WishWrite._(this, WishError.invalidField, null);
      }
      if (wishes.containsKey(explicitId)) {
        return WishWrite._(this, WishError.idInUse, explicitId);
      }
      id = explicitId;
    } else {
      do {
        id = newWishId();
      } while (wishes.containsKey(id));
    }
    if (liveWishCount(recipientId) >= kMaxLiveWishesPerRecipient) {
      return WishWrite._(this, WishError.capReached, null);
    }
    final fields = <String, Object?>{
      'recipientId': recipientId,
      'authorPersonId': author.personId,
      'suggested': author.personId != recipientId,
      for (final entry in changes.entries)
        if (entry.value != null) entry.key: entry.value,
    };
    final scratch = HlcClock(node: clock.node, last: clock.last);
    final trial = set(scratch, Collections.wishes, id, fields);
    final trialRecord = trial.record(Collections.wishes, id)!;
    if (wishRecordBytes(trialRecord) > kMaxWishVisibleBytes ||
        _recordCopyBytes(trialRecord) > kMaxWishCopyBytes) {
      return WishWrite._(this, WishError.tooLarge, null);
    }
    return WishWrite._(set(clock, Collections.wishes, id, fields), null, id);
  }
}

/// Los cambios del parche como campos del registro, o null si no valen.
Map<String, Object?>? _changesOf(
  VisibleWishPatch patch, {
  required bool creating,
}) {
  final out = <String, Object?>{};
  final title = _clean(patch.title);
  if (patch.title != null) {
    if (title == null) return null;
    out['title'] = title;
  } else if (creating) {
    return null;
  }
  if (patch.year != null) {
    if (patch.year! < 1900 || patch.year! > 9999) return null;
    out['year'] = patch.year;
  } else if (creating) {
    return null;
  }
  final optional = <WishField, String?>{
    WishField.occasionId: patch.occasionId,
    WishField.size: patch.size,
    WishField.url: patch.url,
    WishField.description: patch.description,
  };
  for (final entry in optional.entries) {
    final cleaned = _clean(entry.value);
    if (entry.value != null && cleaned == null) return null;
    if (cleaned != null) out[entry.key.name] = cleaned;
    if (patch.clear.contains(entry.key)) {
      if (cleaned != null) return null;
      out[entry.key.name] = null;
    }
  }
  if (patch.clear.contains(WishField.title) ||
      patch.clear.contains(WishField.year)) {
    return null;
  }
  return out;
}
