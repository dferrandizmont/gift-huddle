// Capacidad de los slots en la 1.0.6: 200 regalos por persona en el mismo
// slot de 128 KiB, el anuncio «cap» y la compatibilidad con la 1.0.5.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';

import 'fixtures/protected_envelope_v105.dart' as v105;
import 'protected_harness.dart';

/// Regalos como los de verdad: título, nota, enlace de tienda con su
/// identificador y su consulta, tienda, precio, ids aleatorios y marcas de
/// varios móviles a lo largo de meses.
class _Gifts {
  _Gifts(int seed) : _rnd = Random(seed);

  final Random _rnd;

  static const _words = [
    'bicicleta',
    'roja',
    'casco',
    'pequeño',
    'libro',
    'dinosaurios',
    'puzzle',
    'piezas',
    'castillo',
    'muñeca',
    'cocina',
    'madera',
    'pinturas',
    'acuarela',
    'cuaderno',
    'mochila',
    'colegio',
    'zapatillas',
    'talla',
    'azul',
    'verde',
    'chaqueta',
    'invierno',
    'guantes',
    'bufanda',
    'juego',
    'mesa',
    'cartas',
    'familia',
    'patinete',
    'luces',
    'linterna',
    'peluche',
    'oso',
    'gato',
    'perro',
    'tren',
    'vías',
    'coche',
    'teledirigido',
    'pilas',
    'auriculares',
    'música',
    'altavoz',
    'reloj',
    'despertador',
    'lámpara',
    'noche',
    'estrellas',
    'telescopio',
    'microscopio',
    'química',
    'experimentos',
    'magia',
    'disfraz',
    'pirata',
    'princesa',
    'astronauta',
    'balón',
    'fútbol',
    'baloncesto',
    'raqueta',
    'tenis',
    'piscina',
    'gafas',
    'bañador',
    'toalla',
    'playa',
    'cubo',
    'pala',
    'arena',
    'cometa',
    'viento',
    'que',
    'le',
    'gusta',
    'mucho',
    'para',
    'el',
    'la',
    'de',
    'con',
    'sin',
    'mirar',
    'antes',
    'si',
    'hay',
    'oferta',
    'pedir',
    'tienda',
    'centro',
    'comercial',
    'regalo',
    'Reyes',
    'cumpleaños',
    'Navidad',
    'abuela',
    'tío',
    'prima',
    'se',
    'lo',
    'dijo',
    'a',
    'en',
    'verano',
    'quiere',
    'otro',
    'igual',
    'pero',
    'más',
    'grande',
    'color',
    'no',
    'repetir',
  ];

  static const _stores = [
    'Amazon',
    'El Corte Inglés',
    'Decathlon',
    'Casa del Libro',
    'Imaginarium',
    'Juguettos',
    'Fnac',
    'Zara Kids',
    'IKEA',
    'Toys R Us',
    'Librería Aritz',
  ];

  String _pick(List<String> list) => list[_rnd.nextInt(list.length)];

  String _alnum(int n) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      List<int>.generate(n, (_) => chars.codeUnitAt(_rnd.nextInt(62))),
    );
  }

  String _digits(int n) =>
      List<String>.generate(n, (_) => '${_rnd.nextInt(10)}').join();

  String _phrase(int min, int max) {
    final n = min + _rnd.nextInt(max - min + 1);
    return List<String>.generate(n, (_) => _pick(_words)).join(' ');
  }

  String _slug(int words) =>
      List<String>.generate(words, (_) => _pick(_words)).join('-');

  /// Un id como los de la app (UUID v4).
  String uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Un id de móvil como los de la app (16 bytes en base64url).
  String deviceId() => _alnum(22);

  String _url(int long) {
    switch (_rnd.nextInt(4)) {
      case 0:
        return 'https://www.amazon.es/${_slug(3 + long)}/dp/B0${_alnum(8)}'
            '?ref=sr_1_${_rnd.nextInt(40)}&keywords=${_slug(2 + long)}'
            '&qid=17${_digits(8)}&sr=8-${_rnd.nextInt(30)}';
      case 1:
        return 'https://www.elcorteingles.es/juguetes/A${_digits(8)}-'
            '${_slug(3 + long)}/?color=${_pick(_words)}';
      case 2:
        return 'https://www.decathlon.es/es/p/${_slug(3 + long)}/_/'
            'R-p-${_digits(6)}?mc=${_digits(7)}&c=${_pick(_words)}';
      default:
        return 'https://www.casadellibro.com/libro-${_slug(4 + long)}/'
            '${_digits(13)}/${_digits(8)}';
    }
  }

  /// Los campos de un regalo, como `Gift.toFields` (sin `requestedBy`).
  Map<String, Object?> fields({
    required String giverId,
    required String occasionId,
    bool longText = false,
  }) {
    final price = 500 + _rnd.nextInt(15000);
    final bought = _rnd.nextInt(3) == 0;
    return <String, Object?>{
      'recipientId': 'nora',
      'title': _phrase(2, 6),
      'giverId': giverId,
      'occasionId': occasionId,
      'status': bought ? 'bought' : _pick(const ['idea', 'idea', 'planned']),
      'plannedCents': price,
      'actualCents': bought ? price - _rnd.nextInt(300) : null,
      'store': _pick(_stores),
      'url': _url(longText ? 4 : 0),
      'note': longText ? _phrase(55, 70) : _phrase(8, 30),
      'size': _rnd.nextInt(4) == 0 ? 'talla ${4 + _rnd.nextInt(10)}' : null,
      'requestedBy': null,
      'requestNote': _rnd.nextInt(5) == 0 ? _phrase(4, 14) : null,
      'surprise': true,
      'year': 2026,
    };
  }

  /// Un ámbito de Nora con [live] regalos y [dead] lápidas, escritos y
  /// editados por [writers] a lo largo de unos meses.
  FamilyDoc scope({
    required int live,
    required int dead,
    required List<String> writers,
    bool longText = false,
  }) {
    final givers = [for (var i = 0; i < 4; i++) uuid()];
    final occasions = [for (var i = 0; i < 3; i++) uuid()];
    var doc = FamilyDoc.empty(kListId);
    var at = 1000;
    HlcClock next() {
      at += 60000 + _rnd.nextInt(6 * 3600000);
      return clockOf(writers[_rnd.nextInt(writers.length)], at);
    }

    final ids = [for (var i = 0; i < live + dead; i++) uuid()];
    for (final id in ids) {
      doc = doc.set(next(), Collections.gifts, id, {
        ...fields(
          giverId: _pick(givers),
          occasionId: _pick(occasions),
          longText: longText,
        ),
        // Uno de cada cinco vino del común al activar la protección.
        if (_rnd.nextInt(5) == 0) kPublishSaltField: _alnum(22),
      });
      // Una de cada tres se edita después desde otro móvil.
      if (_rnd.nextInt(3) == 0) {
        doc = doc.set(next(), Collections.gifts, id, {
          'status': 'bought',
          'actualCents': 500 + _rnd.nextInt(15000),
        });
      }
    }
    for (final id in ids.take(dead)) {
      doc = doc.delete(next(), Collections.gifts, id);
    }
    return doc;
  }
}

void main() {
  late Family family;
  setUp(() async => family = await Family.create());

  const on = PolicyState(hideOwnGifts: true, rev: 1);
  const room = kSlotPlainBytes - 4;

  Future<SealedSlot> seal(Phone phone, FamilyDoc doc, {int revision = 1}) =>
      SealedSlot.seal(
        writerKeys: phone.keys,
        writer: phone.id,
        revision: revision,
        key: family.key,
        policy: on,
        doc: doc,
      );

  Future<OpenedSlot> open(SealedSlot slot, Phone writer) => slot.open(
    expectedListId: kListId,
    key: family.key,
    signingKey: writer.keys.publicKeys.signing,
  );

  /// Lo que haría un móvil con la 1.0.5 al recibir [slot].
  Future<v105.OpenedSlot> openAs105(SealedSlot slot, Phone writer) =>
      v105.SealedSlot.parse(slot.bytes).open(
        expectedListId: kListId,
        key: family.key,
        signingKey: writer.keys.publicKeys.signing,
      );

  Future<SealedSlot> sealAs105(Phone phone, FamilyDoc doc) async =>
      SealedSlot.parse(
        (await v105.SealedSlot.seal(
          writerKeys: phone.keys,
          writer: phone.id,
          revision: 1,
          key: family.key,
          policy: on,
          doc: doc,
        )).bytes,
      );

  FamilyDoc simple(int n, {String prefix = 'g', String node = 'aritz-phone'}) {
    var doc = FamilyDoc.empty(kListId);
    final clock = clockOf(node, 1000);
    for (var i = 0; i < n; i++) {
      doc = doc.set(
        clock,
        Collections.gifts,
        '$prefix${i.toString().padLeft(3, '0')}',
        giftFields('nora', 'Regalo $prefix$i', note: 'Nota $i'),
      );
    }
    return doc;
  }

  group('medida: 200 regalos realistas', () {
    test('caben comprimidos y rellenos en 128 KiB con más de un 20 % de '
        'margen, con lápidas y nueve escritores', () async {
      final gifts = _Gifts(2026);
      final writers = [for (var i = 0; i < 9; i++) gifts.deviceId()];
      final doc = gifts.scope(
        live: kMaxSurpriseGifts,
        dead: 100,
        writers: writers,
      );
      final seen = {
        for (final w in writers) w: SlotVersion(1, kFuture + 99999),
      };
      for (final r in doc.collections[Collections.gifts]!.values) {
        if (!r.isDeleted) {
          expect(
            surpriseRecordBytes(r),
            lessThanOrEqualTo(kMaxSurpriseGiftBytes),
          );
        }
      }
      final usage = slotUsage(doc, seen: seen);
      final json = doc.toJson().toString().length;
      // ignore: avoid_print
      print(
        'Medida 1.0.6: $kMaxSurpriseGifts regalos realistas + 100 lápidas + '
        '9 escritores: ${(usage * room).round()} B comprimidos de $room '
        '(${(usage * 100).toStringAsFixed(1)} %; JSON ~${json ~/ 1024} KiB)',
      );
      expect(usage, lessThanOrEqualTo(0.8));
      expect(scopeFitsInSlot(doc, 'nora', seen: seen), isTrue);
      final slot = await seal(family.aritz, doc);
      final opened = await open(SealedSlot.parse(slot.bytes), family.aritz);
      expect(liveSurpriseGifts(opened.doc), kMaxSurpriseGifts);
      expect(opened.cap, kSlotCapacity);
      // El tamaño del slot no cambia con la capacidad.
      expect(
        slot.bytes.length,
        (await seal(family.aritz, simple(1))).bytes.length,
      );
    });

    test('con notas y enlaces largos también caben los 232 del tope, o se '
        'queda fuera lo que no cabe sin bloquear la publicación', () async {
      final gifts = _Gifts(7);
      final doc = gifts.scope(
        live: kMaxSlotGifts,
        dead: 40,
        writers: [for (var i = 0; i < 3; i++) gifts.deviceId()],
        longText: true,
      );
      final usage = slotUsage(doc);
      // ignore: avoid_print
      print(
        'Medida 1.0.6 (textos largos): $kMaxSlotGifts regalos: '
        '${(usage * room).round()} B de $room '
        '(${(usage * 100).toStringAsFixed(1)} %)',
      );
      final (sealed, leftOut) = fitScopeToSlot(doc, 'nora');
      expect(liveSurpriseGifts(sealed) + leftOut.length, kMaxSlotGifts);
      final opened = await open(await seal(family.aritz, sealed), family.aritz);
      expect(liveSurpriseGifts(opened.doc), liveSurpriseGifts(sealed));
    });
  });

  group('cupo de la interfaz', () {
    test('desde la interfaz caben 200: el 201 da un error claro', () {
      final clock = clockOf('aritz-phone', 1000);
      var doc = FamilyDoc.empty(kListId);
      for (var i = 0; i < kMaxSurpriseGifts; i++) {
        doc = addSurpriseGift(doc, clock, 'g$i', giftFields('nora', 'R$i'));
      }
      expect(kMaxSurpriseGifts, 200);
      expect(kMaxReconcileGifts, kMaxSlotGifts - kMaxSurpriseGifts);
      expect(
        () => addSurpriseGift(doc, clock, 'gx', giftFields('nora', 'Rx')),
        throwsA(
          isA<SurpriseCapacityException>().having((e) => e.count, 'count', 201),
        ),
      );
    });

    test('regalos incomprimibles al tope de tamaño: se sella lo que cabe, '
        'el resto queda fuera', () async {
      final rnd = Random(11);
      var doc = FamilyDoc.empty(kListId);
      final clock = clockOf('aritz-phone', 1000);
      const total = 160;
      for (var i = 0; i < total; i++) {
        final id = 'g${i.toString().padLeft(3, '0')}';
        doc = doc.set(clock, Collections.gifts, id, giftFields('nora', 'T'));
        final record = doc.record(Collections.gifts, id)!;
        final rest = kMaxSurpriseGiftBytes - surpriseRecordBytes(record) - 4;
        doc = doc.set(clock, Collections.gifts, id, {
          'note': String.fromCharCodes(
            List<int>.generate(rest, (_) => 0x21 + rnd.nextInt(90)),
          ).replaceAll('"', 'x').replaceAll(r'\', 'y'),
        });
      }
      expect(scopeFitsInSlot(doc, 'nora'), isFalse);
      expect(slotUsage(doc), greaterThan(1));
      final (sealed, leftOut) = fitScopeToSlot(doc, 'nora');
      final kept = liveSurpriseGifts(sealed);
      // Siempre caben al menos los que caben en el formato de la 1.0.5.
      expect(kept, greaterThanOrEqualTo(kLegacySlotGifts));
      expect(kept, lessThan(total));
      expect(leftOut, hasLength(total - kept));
      // Es el mayor número que cabe: uno más ya no.
      expect(leftOut.first, 'g${kept.toString().padLeft(3, '0')}');
      final (more, _) = fitScopeToSlot(doc, 'nora', maxLive: kept + 1);
      expect(liveSurpriseGifts(more), kept);
      final opened = await open(await seal(family.aritz, sealed), family.aritz);
      expect(liveSurpriseGifts(opened.doc), kept);
    });
  });

  group('compatibilidad con la 1.0.5', () {
    test('un 1.0.5 abre lo que sella esta versión con 64 regalos o menos y '
        'no mira «cap»', () async {
      final slot = await seal(family.aritz, simple(kLegacySlotGifts));
      final opened = await openAs105(slot, family.aritz);
      expect(liveSurpriseGifts(opened.doc), kLegacySlotGifts);
    });

    test('un slot de 65 regalos no lo abre un 1.0.5 (por eso solo se sella '
        'si todos anuncian «cap» 2)', () async {
      final slot = await seal(family.aritz, simple(kLegacySlotGifts + 1));
      await expectLater(
        openAs105(slot, family.aritz),
        throwsA(isA<v105.SlotFormatException>()),
      );
      expect(
        liveSurpriseGifts((await open(slot, family.aritz)).doc),
        kLegacySlotGifts + 1,
      );
    });

    test('un slot de un 1.0.5 se abre con «cap» 1', () async {
      final slot = await sealAs105(family.leo, simple(40, node: 'leo-phone'));
      final opened = await open(slot, family.leo);
      expect(opened.cap, 1);
      expect(liveSurpriseGifts(opened.doc), 40);
    });
  });

  group('regla «todos anuncian»', () {
    OpenedSlot part(int cap) => OpenedSlot(
      header: SlotHeader(
        listId: kListId,
        personId: 'nora',
        epoch: 1,
        writer: 'leo-phone',
        revision: 1,
        policy: on,
        kid: family.key.kid,
      ),
      doc: FamilyDoc.empty(kListId),
      seen: const {},
      cap: cap,
    );

    test('slotGiftLimitFor', () {
      expect(slotGiftLimitFor(const []), kMaxSlotGifts);
      expect(slotGiftLimitFor([part(2), part(2)]), kMaxSlotGifts);
      expect(slotGiftLimitFor([part(2), part(3)]), kMaxSlotGifts);
      expect(slotGiftLimitFor([part(2), part(1)]), kLegacySlotGifts);
      expect(slotGiftLimitFor([part(2), null]), kLegacySlotGifts);
    });

    Future<PublishedSlot> publish(SlotSet slots, FamilyDoc doc) async {
      final opened = (await openScope(
        personId: 'nora',
        slots: slots,
        keyring: family.authorizedKeyring,
        view: family.viewOf(family.aritz),
      ))!;
      return publishScope(
        slots: slots,
        opened: opened,
        view: family.viewOf(family.aritz),
        writerKeys: family.aritz.keys,
        keyring: family.authorizedKeyring,
        policy: on,
        doc: opened.doc.merge(doc),
        nowMillis: kFuture + 5000,
      );
    }

    test('con Leo en la 1.0.5 se sellan 64 y el resto queda en local; '
        'cuando Leo actualiza, entra todo', () async {
      final mine = simple(100, prefix: 'a');
      final leo105 = await sealAs105(family.leo, simple(10, prefix: 'l'));
      final legacy = await publish(await family.setOf([leo105]), mine);
      expect(liveSurpriseGifts(legacy.sealed), kLegacySlotGifts);
      expect(legacy.leftOut, hasLength(110 - kLegacySlotGifts));
      expect(liveSurpriseGifts(legacy.scope), 110);
      // Lo que se publicó lo abre el móvil de Leo con la 1.0.5.
      expect(
        liveSurpriseGifts((await openAs105(legacy.slot, family.aritz)).doc),
        kLegacySlotGifts,
      );

      final leo106 = await seal(
        family.leo,
        simple(10, prefix: 'l', node: 'leo-phone'),
        revision: 2,
      );
      final current = await publish(await family.setOf([leo106]), legacy.scope);
      expect(current.leftOut, isEmpty);
      expect(liveSurpriseGifts(current.sealed), 110);
    });

    test('un escritor con derecho que aún no ha publicado cuenta como un '
        '1.0.5', () async {
      final published = await publish(SlotSet.empty, simple(100));
      expect(liveSurpriseGifts(published.sealed), kLegacySlotGifts);
      expect(published.leftOut, hasLength(100 - kLegacySlotGifts));
    });
  });
}
