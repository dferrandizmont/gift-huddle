import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_author.dart';

import 'protected_harness.dart' show Phone, kListId, kPeople, registryOf;

/// Deseos visibles (ADR 0010): alta, edición, retirada, fusión por campo,
/// permisos, topes y compatibilidad con móviles anteriores.
void main() {
  const future = 4102444800000;
  const people = kPeople;

  HlcClock clockOf(String node, int millis) => HlcClock(
    node: node,
    last: Hlc(millis: future + millis, counter: 0, node: node),
  );

  // Aritz y Nora (con dos móviles) tienen dispositivo; Leo no.
  final contexts = <String, WishContext>{};
  setUpAll(() async {
    final aritz = await Phone.create('aritz-phone', 'aritz', 1);
    final nora = await Phone.create('nora-phone', 'nora', 3);
    final noraTwo = await Phone.create('nora-two', 'nora', 4);
    final registry = await registryOf([aritz, nora, noraTwo]);
    Future<WishContext> ctx(Phone p) async {
      final view = await p.viewOf(registry);
      return WishContext.device(view: () => view, localKeys: p.keys);
    }

    contexts['aritz'] = await ctx(aritz);
    contexts['nora'] = await ctx(nora);
    contexts['nora2'] = await ctx(noraTwo);
  });

  WishContext as(String person) => contexts[person]!;

  FamilyDoc base() {
    var doc = FamilyDoc.empty(kListId);
    final c = clockOf('base', 0);
    for (final p in people) {
      doc = doc.set(c, Collections.recipients, p, {'name': p});
    }
    return doc;
  }

  SyncRecord rec(FamilyDoc d, String id) => d.record(Collections.wishes, id)!;

  const bike = VisibleWishPatch(title: 'Bicicleta', year: 2026);

  test(
    'borrar al destinatario vacía sus deseos, incluso tras una edición tardía',
    () {
      final own = as('nora');
      final other = as('aritz');
      final c = clockOf('before', 10);
      final before = base()
          .createOwnWish(c, own, bike, id: 'own')
          .doc
          .suggestVisibleWish(c, other, 'nora', bike, id: 'incoming')
          .doc
          .suggestVisibleWish(c, own, 'aritz', bike, id: 'outgoing')
          .doc;
      expect(
        before.removeWish(c, other, 'incoming').error,
        WishError.notWishOwner,
      );
      final deleted = before.deleteRecipientWithWishes(
        clockOf('delete', 20),
        'nora',
      );
      final lateClock = clockOf('late', 30);
      final late = before
          .editVisibleWish(
            lateClock,
            own,
            'own',
            const VisibleWishPatch(
              title: 'Bici azul',
              url: 'https://example.com/bici',
              description: 'Con luces',
            ),
          )
          .doc
          .createOwnWish(lateClock, own, bike, id: 'late')
          .doc;
      expect(
        rec(late, 'own').field('title')!.stamp,
        greaterThan(rec(deleted, 'own').field(kDeletedField)!.stamp),
      );
      for (final doc in [deleted, deleted.merge(late), late.merge(deleted)]) {
        final clean = doc.normalizedWishes();
        for (final id in ['own', 'incoming', if (doc != deleted) 'late']) {
          final wish = rec(clean, id);
          expect(wish.isDeleted, isTrue);
          expect(wish.hasTombstoneContent, isFalse);
          expect(validateWishRecord(wish), isNull);
        }
        expect(clean.wishesFor('nora'), isEmpty);
        expect(clean.wishesFor('aritz').single.id, 'outgoing');
        expect(clean.editVisibleWish(c, other, 'outgoing', bike).ok, isTrue);
        expect(clean.normalizedWishes(), same(clean));
      }
    },
  );

  group('alta', () {
    test('createOwnWish escribe solo en wishes, con autor y sin sugerir', () {
      final c = clockOf('n1', 10);
      final r = base().createOwnWish(
        c,
        as('nora'),
        const VisibleWishPatch(
          title: '  Bicicleta ',
          year: 2026,
          occasionId: 'navidad',
          size: '8 años',
          url: 'https://example.com/b',
          description: 'Roja',
        ),
        id: 'w1',
      );
      expect(r.ok, isTrue);
      expect(r.wishId, 'w1');
      final wish = Wish.fromRecord(rec(r.doc, 'w1'))!;
      expect(wish.title, 'Bicicleta');
      expect(wish.recipientId, 'nora');
      expect(wish.authorPersonId, 'nora');
      expect(wish.suggested, isFalse);
      expect(wish.occasionId, 'navidad');
      expect(wish.size, '8 años');
      expect(wish.url, 'https://example.com/b');
      expect(wish.description, 'Roja');
      // Solo cambió la colección de deseos.
      expect(r.doc.collections.keys.toSet(), {
        Collections.recipients,
        Collections.wishes,
      });
    });

    test('sin id propio genera uno aleatorio distinto cada vez', () {
      final c = clockOf('n1', 10);
      var doc = base();
      final ids = <String>{};
      for (var i = 0; i < 5; i++) {
        final r = doc.createOwnWish(c, as('nora'), bike);
        doc = r.doc;
        ids.add(r.wishId!);
      }
      expect(ids.length, 5);
    });

    test('suggestVisibleWish marca sugerido y conserva al autor', () {
      final r = base().suggestVisibleWish(
        clockOf('n1', 10),
        as('aritz'),
        'nora',
        bike,
        id: 'w1',
      );
      expect(r.ok, isTrue);
      final wish = Wish.fromRecord(rec(r.doc, 'w1'))!;
      expect(wish.recipientId, 'nora');
      expect(wish.authorPersonId, 'aritz');
      expect(wish.suggested, isTrue);
    });

    test('sugerirse a uno mismo, o a quien no existe, se rechaza', () {
      final doc = base();
      final c = clockOf('n1', 10);
      expect(
        doc.suggestVisibleWish(c, as('nora'), 'nora', bike).error,
        WishError.suggestionForSelf,
      );
      expect(
        doc.suggestVisibleWish(c, as('aritz'), 'nadie', bike).error,
        WishError.recipientHasNoDevice,
      );
      // Leo existe pero no tiene dispositivo: tampoco, y no se toca el reloj.
      final before = c.last;
      final leo = doc.suggestVisibleWish(c, as('aritz'), 'leo', bike);
      expect(leo.error, WishError.recipientHasNoDevice);
      expect(leo.doc, same(doc));
      expect(c.last, before);
    });

    test('título o año que faltan o no valen: invalidField sin escribir', () {
      final doc = base();
      final c = clockOf('n1', 10);
      final before = c.last;
      for (final patch in const [
        VisibleWishPatch(year: 2026),
        VisibleWishPatch(title: 'Algo'),
        VisibleWishPatch(title: '   ', year: 2026),
        VisibleWishPatch(title: 'x', year: 20),
        VisibleWishPatch(title: 'x', year: 2026, url: '  '),
      ]) {
        final r = doc.createOwnWish(c, as('nora'), patch);
        expect(r.error, WishError.invalidField);
        expect(r.doc, same(doc));
      }
      expect(c.last, before);
    });

    test('un id usado, también por una lápida, no se reutiliza', () {
      final c = clockOf('n1', 10);
      final a = as('nora');
      var doc = base().createOwnWish(c, a, bike, id: 'w1').doc;
      expect(doc.createOwnWish(c, a, bike, id: 'w1').error, WishError.idInUse);
      doc = doc.removeWish(c, a, 'w1').doc;
      expect(doc.createOwnWish(c, a, bike, id: 'w1').error, WishError.idInUse);
    });
  });

  group('lista positiva de campos', () {
    test('visibleFields no lleva precios, tienda, notas ni estado', () {
      final doc = base()
          .createOwnWish(
            clockOf('n1', 10),
            as('nora'),
            const VisibleWishPatch(
              title: 'Bicicleta',
              year: 2026,
              size: 'M',
              url: 'https://example.com',
              description: 'd',
              occasionId: 'navidad',
            ),
            id: 'w1',
          )
          .doc;
      final wish = Wish.fromRecord(rec(doc, 'w1'))!;
      final names = wish.visibleFields.keys.toSet();
      expect(names, {'id', ...Wish.fieldNames});
      for (final banned in [
        'plannedCents',
        'actualCents',
        'store',
        'note',
        'status',
        'giverId',
        'requestedBy',
        'requestNote',
        'surprise',
      ]) {
        expect(names, isNot(contains(banned)), reason: banned);
      }
      expect(Wish.fieldNames, isNot(contains('id')));
    });

    test('un registro con campos de más no los expone', () {
      final doc = base()
          .createOwnWish(clockOf('n1', 10), as('nora'), bike, id: 'w1')
          .doc
          .set(clockOf('n2', 20), Collections.wishes, 'w1', {
            'plannedCents': 5000,
            'store': 'Tienda',
            'note': 'secreto',
          });
      final wish = Wish.fromRecord(rec(doc, 'w1'))!;
      final json = canonicalJsonOf(wish.visibleFields);
      expect(json, isNot(contains('5000')));
      expect(json, isNot(contains('Tienda')));
      expect(json, isNot(contains('secreto')));
    });
  });

  group('edición', () {
    FamilyDoc own() => base()
        .createOwnWish(
          clockOf('n1', 10),
          as('nora'),
          const VisibleWishPatch(
            title: 'Bicicleta',
            year: 2026,
            size: 'M',
            url: 'https://example.com',
          ),
          id: 'w1',
        )
        .doc;

    test('P edita y solo cambian los campos tocados', () {
      final doc = own();
      final before = rec(doc, 'w1');
      final r = doc.editVisibleWish(
        clockOf('n1', 500),
        as('nora'),
        'w1',
        const VisibleWishPatch(title: 'Bici azul', size: 'M'),
      );
      expect(r.ok, isTrue);
      final after = rec(r.doc, 'w1');
      expect(after['title'], 'Bici azul');
      expect(
        after.field('title')!.stamp,
        greaterThan(before.field('title')!.stamp),
      );
      // Misma talla: conserva su marca; los demás campos, también.
      for (final name in ['size', 'url', 'year', 'recipientId']) {
        expect(after.field(name), before.field(name), reason: name);
      }
    });

    test('vaciar un campo opcional deja null con marca nueva', () {
      final r = own().editVisibleWish(
        clockOf('n1', 500),
        as('nora'),
        'w1',
        const VisibleWishPatch(clear: {WishField.url}),
      );
      expect(r.ok, isTrue);
      expect(rec(r.doc, 'w1')['url'], isNull);
      expect(Wish.fromRecord(rec(r.doc, 'w1'))!.url, isNull);
    });

    test('sin cambios devuelve el mismo documento y no mueve el reloj', () {
      final doc = own();
      final c = clockOf('n1', 500);
      final before = c.last;
      final r = doc.editVisibleWish(
        c,
        as('nora'),
        'w1',
        const VisibleWishPatch(title: 'Bicicleta'),
      );
      expect(r.ok, isTrue);
      expect(r.doc, same(doc));
      expect(c.last, before);
    });

    test(
      'quien sugirió, u otra persona, no edita: notWishOwner sin escribir',
      () {
        final doc = base()
            .suggestVisibleWish(
              clockOf('n1', 10),
              as('aritz'),
              'nora',
              bike,
              id: 'w1',
            )
            .doc;
        for (final who in ['aritz']) {
          final c = clockOf('n2', 500);
          final before = c.last;
          final r = doc.editVisibleWish(
            c,
            as(who),
            'w1',
            const VisibleWishPatch(title: 'Otra cosa'),
          );
          expect(r.error, WishError.notWishOwner);
          expect(r.doc, same(doc));
          expect(c.last, before, reason: 'sin marca del reloj');
          expect(r.doc.canonicalJson(), doc.canonicalJson());
        }
        // Nora sí puede.
        expect(
          doc
              .editVisibleWish(
                clockOf('n3', 500),
                as('nora'),
                'w1',
                const VisibleWishPatch(title: 'Mejor'),
              )
              .ok,
          isTrue,
        );
      },
    );

    test('no existe y quitado', () {
      final doc = own();
      final c = clockOf('n1', 500);
      expect(
        doc.editVisibleWish(c, as('nora'), 'zz', bike).error,
        WishError.wishNotFound,
      );
      final gone = doc.removeWish(c, as('nora'), 'w1').doc;
      expect(
        gone
            .editVisibleWish(
              c,
              as('nora'),
              'w1',
              const VisibleWishPatch(title: 'x'),
            )
            .error,
        WishError.wishRemoved,
      );
    });
  });

  group('retirada', () {
    test('solo P: quien sugirió recibe notWishOwner y no escribe', () {
      final doc = base()
          .suggestVisibleWish(
            clockOf('n1', 10),
            as('aritz'),
            'nora',
            bike,
            id: 'w1',
          )
          .doc;
      final c = clockOf('n2', 500);
      final before = c.last;
      final r = doc.removeWish(c, as('aritz'), 'w1');
      expect(r.error, WishError.notWishOwner);
      expect(r.doc, same(doc));
      expect(c.last, before);
      expect(doc.removeWish(c, as('nora'), 'w1').ok, isTrue);
    });

    test('la lápida es siempre la misma, sin contenido', () {
      final c = clockOf('n1', 10);
      final a = as('nora');
      final full = base()
          .createOwnWish(
            c,
            a,
            const VisibleWishPatch(
              title: 'Secreto de título',
              year: 2026,
              size: 'M',
              url: 'https://example.com/x',
              description: 'texto largo',
            ),
            id: 'w1',
          )
          .doc;
      final short = base().createOwnWish(c, a, bike, id: 'w1').doc;
      final t1 = full.removeWish(clockOf('n1', 500), a, 'w1').doc;
      final t2 = short.removeWish(clockOf('n1', 500), a, 'w1').doc;
      final r1 = rec(t1, 'w1');
      final r2 = rec(t2, 'w1');
      expect(r1.isDeleted, isTrue);
      expect(r1.hasTombstoneContent, isFalse);
      expect(r1.fields.keys.toSet(), r2.fields.keys.toSet());
      expect(r1.fields.keys.toSet(), {...Wish.fieldNames, kDeletedField});
      expect(t1.canonicalJson(), isNot(contains('Secreto')));
      expect(t1.canonicalJson(), isNot(contains('example.com')));
      expect(Wish.fromRecord(r1), isNull);
    });

    test('quitar dos veces no escribe la segunda', () {
      final a = as('nora');
      final doc = base()
          .createOwnWish(clockOf('n1', 10), a, bike, id: 'w1')
          .doc
          .removeWish(clockOf('n1', 20), a, 'w1')
          .doc;
      final c = clockOf('n1', 500);
      final before = c.last;
      final r = doc.removeWish(c, a, 'w1');
      expect(r.ok, isTrue);
      expect(r.doc, same(doc));
      expect(c.last, before);
    });
  });

  group('fusión', () {
    FamilyDoc seed() => base()
        .createOwnWish(
          clockOf('n0', 10),
          as('nora'),
          const VisibleWishPatch(
            title: 'Bicicleta',
            year: 2026,
            size: 'M',
            url: 'https://example.com',
          ),
          id: 'w1',
        )
        .doc;

    test('dos móviles de P editan campos distintos y se conserva todo', () {
      final s = seed();
      final a = s
          .editVisibleWish(
            clockOf('pa', 100),
            as('nora'),
            'w1',
            const VisibleWishPatch(title: 'Bici azul'),
          )
          .doc;
      final b = s
          .editVisibleWish(
            clockOf('pb', 200),
            as('nora'),
            'w1',
            const VisibleWishPatch(size: 'L'),
          )
          .doc;
      final ab = a.merge(b);
      expect(ab.canonicalJson(), b.merge(a).canonicalJson());
      final w = Wish.fromRecord(rec(ab, 'w1'))!;
      expect(w.title, 'Bici azul');
      expect(w.size, 'L');
    });

    test('mismo campo: gana la marca más nueva', () {
      final s = seed();
      final a = s
          .editVisibleWish(
            clockOf('pa', 100),
            as('nora'),
            'w1',
            const VisibleWishPatch(title: 'A'),
          )
          .doc;
      final b = s
          .editVisibleWish(
            clockOf('pb', 300),
            as('nora'),
            'w1',
            const VisibleWishPatch(title: 'B'),
          )
          .doc;
      expect(Wish.fromRecord(rec(a.merge(b), 'w1'))!.title, 'B');
      expect(Wish.fromRecord(rec(b.merge(a), 'w1'))!.title, 'B');
    });

    test('quitar gana a una edición concurrente, anterior o posterior', () {
      final s = seed();
      final removed = s.removeWish(clockOf('pa', 100), as('nora'), 'w1').doc;
      for (final millis in [50, 100, 900]) {
        final edited = s
            .editVisibleWish(
              clockOf('pb', millis),
              as('nora'),
              'w1',
              const VisibleWishPatch(title: 'Editado'),
            )
            .doc;
        for (final m in [removed.merge(edited), edited.merge(removed)]) {
          final r = rec(m, 'w1');
          expect(r.isDeleted, isTrue, reason: '$millis');
          expect(r.hasTombstoneContent, isFalse, reason: '$millis');
          expect(Wish.fromRecord(r), isNull);
        }
      }
    });

    test('conmutativa, asociativa e idempotente con tres réplicas', () {
      final s = seed();
      final a = s
          .editVisibleWish(
            clockOf('pa', 100),
            as('nora'),
            'w1',
            const VisibleWishPatch(title: 'A'),
          )
          .doc;
      final b = s
          .editVisibleWish(
            clockOf('pb', 200),
            as('nora'),
            'w1',
            const VisibleWishPatch(size: 'XL', description: 'd'),
          )
          .doc
          .suggestVisibleWish(
            clockOf('pb', 250),
            as('aritz'),
            'nora',
            const VisibleWishPatch(title: 'Libro', year: 2026),
            id: 'w2',
          )
          .doc;
      final c = s.removeWish(clockOf('pc', 150), as('nora'), 'w1').doc;
      String j(FamilyDoc d) => d.canonicalJson();
      expect(j(a.merge(b)), j(b.merge(a)));
      expect(j(a.merge(b).merge(c)), j(a.merge(b.merge(c))));
      expect(j(a.merge(c).merge(b)), j(c.merge(b).merge(a)));
      expect(j(a.merge(a)), j(a));
      final all = a.merge(b).merge(c);
      expect(j(all.merge(all)), j(all));
      expect(j(all.merge(a)), j(all));
    });

    test('un documento fusionado sobrevive a toJson y fromJson', () {
      final s = seed();
      final c = s.removeWish(clockOf('pc', 150), as('nora'), 'w1').doc;
      final back = FamilyDoc.fromJson(c.toJson());
      expect(back.canonicalJson(), c.canonicalJson());
    });
  });

  group('topes', () {
    test('200 deseos vivos por persona: el 201 da capReached', () {
      final c = clockOf('n1', 10);
      final a = as('nora');
      var doc = base();
      for (var i = 0; i < kMaxLiveWishesPerRecipient; i++) {
        final r = doc.createOwnWish(
          c,
          a,
          VisibleWishPatch(title: 'Deseo $i', year: 2026),
          id: 'w$i',
        );
        expect(r.ok, isTrue, reason: '$i');
        doc = r.doc;
      }
      final before = c.last;
      final over = doc.createOwnWish(c, a, bike);
      expect(over.error, WishError.capReached);
      expect(over.doc, same(doc));
      expect(c.last, before);
      // Leo no tiene dispositivo: no se le sugiere nada, y no mueve el reloj.
      final beforeLeo = c.last;
      final leo = doc.suggestVisibleWish(c, as('aritz'), 'leo', bike);
      expect(leo.error, WishError.recipientHasNoDevice);
      expect(leo.doc, same(doc));
      expect(c.last, beforeLeo);
      // Quitar uno libera hueco.
      doc = doc.removeWish(c, a, 'w0').doc;
      expect(doc.liveWishCount('nora'), kMaxLiveWishesPerRecipient - 1);
      expect(doc.createOwnWish(c, a, bike).ok, isTrue);
    });

    test(
      'dos altas sin conexión que pasan el tope se conservan y bloquean',
      () {
        final a = as('nora');
        var doc = base();
        final c = clockOf('n1', 10);
        for (var i = 0; i < kMaxLiveWishesPerRecipient - 1; i++) {
          doc = doc.createOwnWish(c, a, bike, id: 'w$i').doc;
        }
        final one = doc
            .createOwnWish(clockOf('pa', 100), a, bike, id: 'wa')
            .doc;
        final two = doc
            .createOwnWish(clockOf('pb', 100), a, bike, id: 'wb')
            .doc;
        final merged = one.merge(two);
        expect(merged.liveWishCount('nora'), kMaxLiveWishesPerRecipient + 1);
        expect(Wish.fromRecord(rec(merged, 'wa')), isNotNull);
        expect(Wish.fromRecord(rec(merged, 'wb')), isNotNull);
        expect(merged.createOwnWish(c, a, bike).error, WishError.capReached);
        // Al volver bajo el tope se puede crear otra vez.
        final fewer = merged
            .removeWish(c, a, 'wa')
            .doc
            .removeWish(c, a, 'wb')
            .doc;
        expect(fewer.createOwnWish(c, a, bike).ok, isTrue);
      },
    );

    // Mide el registro serializado (con marcas reales y campos vaciados como
    // [null, marca]) y no solo el texto de los campos.
    int bytesAfterCreate(String description) => wishRecordBytes(
      rec(
        base()
            .createOwnWish(
              clockOf('n1', 10),
              as('nora'),
              VisibleWishPatch(
                title: 'T',
                year: 2026,
                description: description,
              ),
              id: 'w1',
            )
            .doc,
        'w1',
      ),
    );

    test('alta: exactamente 1.900 bytes cabe y 1.901 no', () {
      final n = 1 + kMaxWishVisibleBytes - bytesAfterCreate('x');
      expect(bytesAfterCreate('x' * n), kMaxWishVisibleBytes);
      for (final (len, ok) in [(n, true), (n + 1, false)]) {
        final doc = base();
        final c = clockOf('n1', 10);
        final before = c.last;
        final r = doc.createOwnWish(
          c,
          as('nora'),
          VisibleWishPatch(title: 'T', year: 2026, description: 'x' * len),
          id: 'w1',
        );
        expect(r.ok, ok, reason: '$len');
        if (!ok) {
          expect(r.error, WishError.tooLarge);
          expect(r.doc, same(doc));
          expect(c.last, before);
        }
      }
    });

    test('los bytes son UTF-8: ñ pesa 2 y el emoji 4', () {
      final ascii = bytesAfterCreate('x' * 100);
      expect(bytesAfterCreate('ñ' * 100), ascii + 100);
      expect(bytesAfterCreate('\u{1F381}' * 100), ascii + 300);
      final doc = base();
      final c = clockOf('n1', 10);
      // 480 emojis = 1.920 bytes: no cabe aunque son solo 960 unidades.
      final r = doc.createOwnWish(
        c,
        as('nora'),
        VisibleWishPatch(
          title: 'T',
          year: 2026,
          description: '\u{1F381}' * 480,
        ),
      );
      expect(r.error, WishError.tooLarge);
      expect(r.doc, same(doc));
    });

    FamilyDoc withUrl() => base()
        .createOwnWish(
          clockOf('n1', 10),
          as('nora'),
          const VisibleWishPatch(
            title: 'T',
            year: 2026,
            url: 'https://example.com/a',
            description: 'x',
          ),
          id: 'w1',
        )
        .doc;

    int bytesAfterEdit(FamilyDoc doc, VisibleWishPatch patch) {
      final r = doc.editVisibleWish(
        clockOf('n1', 500),
        as('nora'),
        'w1',
        patch,
      );
      expect(r.ok, isTrue);
      return wishRecordBytes(rec(r.doc, 'w1'));
    }

    test('edición: exactamente 1.900 cabe y 1.901 no', () {
      final doc = withUrl();
      final probe = bytesAfterEdit(
        doc,
        VisibleWishPatch(description: 'y' * 10),
      );
      final n = 10 + kMaxWishVisibleBytes - probe;
      expect(
        bytesAfterEdit(doc, VisibleWishPatch(description: 'y' * n)),
        kMaxWishVisibleBytes,
      );
      final c = clockOf('n1', 500);
      final before = c.last;
      final r = doc.editVisibleWish(
        c,
        as('nora'),
        'w1',
        VisibleWishPatch(description: 'y' * (n + 1)),
      );
      expect(r.error, WishError.tooLarge);
      expect(r.doc, same(doc));
      expect(c.last, before);
    });

    test('edición que vacía un opcional cuenta el [null, marca] que queda', () {
      final doc = withUrl();
      const clearUrl = {WishField.url};
      final probe = bytesAfterEdit(
        doc,
        VisibleWishPatch(description: 'y' * 10, clear: clearUrl),
      );
      // El campo vaciado sigue en el registro como [null, marca].
      final cleared = doc
          .editVisibleWish(
            clockOf('n1', 500),
            as('nora'),
            'w1',
            const VisibleWishPatch(clear: clearUrl),
          )
          .doc;
      expect(canonicalJsonOf(cleared.toJson()), contains('"url":[null,'));
      final n = 10 + kMaxWishVisibleBytes - probe;
      expect(
        bytesAfterEdit(
          doc,
          VisibleWishPatch(description: 'y' * n, clear: clearUrl),
        ),
        kMaxWishVisibleBytes,
      );
      final c = clockOf('n1', 500);
      final before = c.last;
      final r = doc.editVisibleWish(
        c,
        as('nora'),
        'w1',
        VisibleWishPatch(description: 'y' * (n + 1), clear: clearUrl),
      );
      expect(r.error, WishError.tooLarge);
      expect(r.doc, same(doc));
      expect(c.last, before);
    });

    test('dos ediciones sin conexión que caben solas y no juntas: se '
        'conservan las dos y luego solo se admite lo que no agranda', () {
      final seed = base()
          .createOwnWish(
            clockOf('n0', 10),
            as('nora'),
            const VisibleWishPatch(title: 'T', year: 2026),
            id: 'w1',
          )
          .doc;
      final a = seed
          .editVisibleWish(
            clockOf('pa', 100),
            as('nora'),
            'w1',
            VisibleWishPatch(description: 'a' * 1000),
          )
          .doc;
      final b = seed
          .editVisibleWish(
            clockOf('pb', 200),
            as('nora2'),
            'w1',
            VisibleWishPatch(url: 'https://example.com/${'b' * 1000}'),
          )
          .doc;
      expect(wishRecordBytes(rec(a, 'w1')), lessThan(kMaxWishVisibleBytes));
      expect(wishRecordBytes(rec(b, 'w1')), lessThan(kMaxWishVisibleBytes));
      final merged = a.merge(b);
      expect(
        wishRecordBytes(rec(merged, 'w1')),
        greaterThan(kMaxWishVisibleBytes),
      );
      final w = Wish.fromRecord(rec(merged, 'w1'))!;
      expect(w.description, 'a' * 1000);
      expect(w.url, startsWith('https://example.com/bbb'));
      expect(merged.canonicalJson(), b.merge(a).canonicalJson());

      final c = clockOf('n1', 900);
      final before = c.last;
      final grow = merged.editVisibleWish(
        c,
        as('nora'),
        'w1',
        const VisibleWishPatch(size: 'M'),
      );
      expect(grow.error, WishError.tooLarge);
      expect(grow.doc, same(merged));
      expect(c.last, before);
      // Guardar texto del mismo tamaño se admite aunque no quepa.
      final sameSize = merged.editVisibleWish(
        c,
        as('nora'),
        'w1',
        VisibleWishPatch(description: 'b' * 1000),
      );
      expect(sameSize.ok, isTrue);
      expect(Wish.fromRecord(rec(sameSize.doc, 'w1'))!.description, 'b' * 1000);
      // Encoger sí se admite, aunque aún no quepa; y quitar siempre.
      final shrink = merged.editVisibleWish(
        c,
        as('nora'),
        'w1',
        const VisibleWishPatch(description: 'a'),
      );
      expect(shrink.ok, isTrue);
      expect(shrink.doc.removeWish(c, as('nora'), 'w1').ok, isTrue);
    });
  });

  group('forma del registro', () {
    FamilyDoc withExtras() => base()
        .createOwnWish(
          clockOf('n1', 10),
          as('nora'),
          const VisibleWishPatch(title: 'Bicicleta', year: 2026),
          id: 'w1',
        )
        .doc
        .set(clockOf('x', 20), Collections.wishes, 'w1', {
          'plannedCents': 5000,
          'store': 'Tienda',
          'note': 'secreto',
        });

    Map<String, Object?> rawWish(FamilyDoc d, String id) =>
        (((d.toJson()['c']! as Map)[Collections.wishes]) as Map)[id]!
            as Map<String, Object?>;

    final allowed = {...Wish.fieldNames, 'deleted'};

    test('validateWishRecord: vivo, lápida, de más, sin campos, mal tipo', () {
      final ok = base()
          .createOwnWish(clockOf('n1', 10), as('nora'), bike, id: 'w1')
          .doc;
      expect(validateWishRecord(rec(ok, 'w1')), isNull);
      final gone = ok.removeWish(clockOf('n1', 20), as('nora'), 'w1').doc;
      expect(validateWishRecord(rec(gone, 'w1')), isNull);
      expect(
        validateWishRecord(rec(withExtras(), 'w1')),
        WishRecordProblem.unknownField,
      );
      final c = clockOf('z', 30);
      FamilyDoc raw(Map<String, Object?> f) =>
          FamilyDoc.empty(kListId).set(c, Collections.wishes, 'w9', f);
      expect(
        validateWishRecord(rec(raw({'title': 'x', 'year': 2026}), 'w9')),
        WishRecordProblem.missingField,
      );
      expect(
        validateWishRecord(
          rec(
            raw({
              'recipientId': 'nora',
              'authorPersonId': 'nora',
              'suggested': 'no',
              'title': 'x',
              'year': 2026,
            }),
            'w9',
          ),
        ),
        WishRecordProblem.wrongType,
      );
      expect(
        validateWishRecord(
          SyncRecord(
            id: 'w9',
            fields: {
              'deleted': FieldValue(value: true, stamp: c.now()),
              'title': FieldValue(value: 'queda', stamp: c.now()),
            },
          ),
        ),
        WishRecordProblem.tombstoneHasContent,
      );
    });

    test('editar un registro con campos de más los quita (JSON en bruto)', () {
      final doc = withExtras();
      expect(rawWish(doc, 'w1').keys, contains('plannedCents'));
      final r = doc.editVisibleWish(
        clockOf('n1', 500),
        as('nora'),
        'w1',
        const VisibleWishPatch(title: 'Bici azul'),
      );
      expect(r.ok, isTrue);
      expect(allowed.containsAll(rawWish(r.doc, 'w1').keys), isTrue);
      expect(canonicalJsonOf(r.doc.toJson()), isNot(contains('Tienda')));
      expect(canonicalJsonOf(r.doc.toJson()), isNot(contains('secreto')));
      expect(validateWishRecord(rec(r.doc, 'w1')), isNull);
      // Aunque no cambie nada visible, se limpia sin mover el reloj.
      final c = clockOf('n1', 500);
      final before = c.last;
      final noop = doc.editVisibleWish(
        c,
        as('nora'),
        'w1',
        const VisibleWishPatch(title: 'Bicicleta'),
      );
      expect(c.last, before);
      expect(allowed.containsAll(rawWish(noop.doc, 'w1').keys), isTrue);
    });

    test('la lápida tiene una sola forma, también tras fusionar', () {
      final plain = base()
          .createOwnWish(clockOf('n1', 10), as('nora'), bike, id: 'w1')
          .doc
          .removeWish(clockOf('n1', 20), as('nora'), 'w1')
          .doc;
      final fromExtras = withExtras()
          .removeWish(clockOf('n1', 30), as('nora'), 'w1')
          .doc;
      expect(rawWish(fromExtras, 'w1').keys.toSet(), allowed);
      expect(
        rawWish(fromExtras, 'w1').keys.toSet(),
        rawWish(plain, 'w1').keys.toSet(),
      );
      expect(validateWishRecord(rec(fromExtras, 'w1')), isNull);
      // Un móvil que aún tenga los campos de más los vuelve a traer al
      // fusionar; normalizar en la frontera los quita otra vez.
      final merged = fromExtras.merge(withExtras());
      expect(rawWish(merged, 'w1').keys, contains('store'));
      expect(rec(merged, 'w1').isDeleted, isTrue);
      expect(rec(merged, 'w1').hasTombstoneContent, isFalse);
      final clean = merged.normalizedWishes();
      expect(rawWish(clean, 'w1').keys.toSet(), allowed);
      expect(clean.normalizedWishes(), same(clean));
      expect(
        withExtras().merge(fromExtras).normalizedWishes().canonicalJson(),
        clean.canonicalJson(),
      );
    });

    test('lápidas incompletas: se completan con la marca de la lápida', () {
      final deletedOnly = FamilyDoc.empty(kListId)
          .set(clockOf('x', 100), Collections.wishes, 'w1', {'deleted': true});
      expect(
        validateWishRecord(rec(deletedOnly, 'w1')),
        WishRecordProblem.missingField,
      );
      final stamp = rec(deletedOnly, 'w1').field('deleted')!.stamp;
      final partial = FamilyDoc.empty(kListId).set(
        clockOf('y', 200),
        Collections.wishes,
        'w1',
        {'deleted': true, 'title': null, 'url': null, 'junk': null},
      );
      for (final doc in [deletedOnly, partial]) {
        final clean = doc.normalizedWishes();
        final r = rec(clean, 'w1');
        expect(r.fields.keys.toSet(), allowed);
        expect(validateWishRecord(r), isNull);
        expect(r.isDeleted, isTrue);
        expect(r.hasTombstoneContent, isFalse);
        expect(clean.normalizedWishes(), same(clean));
      }
      // Los nombres que faltaban llevan la marca de la propia lápida.
      final r = rec(deletedOnly.normalizedWishes(), 'w1');
      for (final name in Wish.fieldNames) {
        expect(r.field(name)!.stamp, stamp, reason: name);
        expect(r.field(name)!.value, isNull);
      }
      // Los nombres que ya estaban conservan su marca; el desconocido se va.
      final p = rec(partial.normalizedWishes(), 'w1');
      expect(p.field('title')!.stamp, rec(partial, 'w1').field('title')!.stamp);
      expect(p.fields.containsKey('junk'), isFalse);
    });

    test(
      'quitar un deseo ya quitado pero incompleto lo completa sin reloj',
      () {
        final doc = FamilyDoc.empty(
          kListId,
        ).set(clockOf('x', 100), Collections.wishes, 'w1', {'deleted': true});
        final c = clockOf('n1', 500);
        final before = c.last;
        final r = doc.removeWish(c, as('nora'), 'w1');
        expect(r.ok, isTrue);
        expect(
          r.doc.record(Collections.wishes, 'w1')!.fields.keys.toSet(),
          allowed,
        );
        expect(c.last, before);
      },
    );

    test('normalizar tras fusionar es conmutativo e idempotente', () {
      final a = FamilyDoc.empty(kListId)
          .set(clockOf('x', 100), Collections.wishes, 'w1', {'deleted': true});
      final b = FamilyDoc.empty(kListId).set(
        clockOf('y', 200),
        Collections.wishes,
        'w1',
        {'deleted': true, 'title': null, 'store': null},
      );
      final live = withExtras();
      for (final (x, y) in [(a, b), (a, live), (b, live)]) {
        final xy = x.merge(y).normalizedWishes();
        final yx = y.merge(x).normalizedWishes();
        expect(xy.canonicalJson(), yx.canonicalJson());
        expect(xy.normalizedWishes().canonicalJson(), xy.canonicalJson());
        expect(validateWishRecord(rec(xy, 'w1')), isNull);
      }
    });

    int copyOf(String title, {String? url}) =>
        wishCopyBytes(title: title, url: url);

    test('lo que copiará el plan: 1.200 bytes caben y 1.201 no', () {
      expect(copyOf('T' * 1198), kMaxWishCopyBytes);
      final doc = base();
      final c = clockOf('n1', 10);
      final ok = doc.createOwnWish(
        c,
        as('nora'),
        VisibleWishPatch(title: 'T' * 1198, year: 2026),
        id: 'w1',
      );
      expect(ok.ok, isTrue);
      // Título + enlace suman lo mismo.
      expect(copyOf('T' * 598, url: 'u' * 598), kMaxWishCopyBytes);
      expect(
        doc
            .createOwnWish(
              c,
              as('nora'),
              VisibleWishPatch(title: 'T' * 598, year: 2026, url: 'u' * 598),
            )
            .ok,
        isTrue,
      );
      final before = c.last;
      final over = doc.createOwnWish(
        c,
        as('nora'),
        VisibleWishPatch(title: 'T' * 1199, year: 2026),
      );
      expect(over.error, WishError.tooLarge);
      expect(over.doc, same(doc));
      expect(c.last, before);
      // La descripción no se copia: no cuenta.
      expect(
        doc
            .createOwnWish(
              c,
              as('nora'),
              VisibleWishPatch(
                title: 'T' * 1198,
                year: 2026,
                description: 'd' * 300,
              ),
            )
            .ok,
        isTrue,
      );
      final before2 = c.last;
      // Una edición que pasa de 1.200 se rechaza sin tocar el reloj.
      final edit = ok.doc.editVisibleWish(
        c,
        as('nora'),
        'w1',
        const VisibleWishPatch(url: 'https://example.com'),
      );
      expect(edit.error, WishError.tooLarge);
      expect(edit.doc, same(ok.doc));
      expect(c.last, before2);
    });

    test(
      'un plan mínimo con lo máximo copiado cabe en el registro secreto',
      () {
        final c = clockOf('n1', 10);
        final id = 'a' * 36;
        final copied = {'title': 'T' * 598, 'size': 's' * 3, 'url': 'u' * 590};
        expect(
          wishCopyBytes(
            title: copied['title'],
            size: copied['size'],
            url: copied['url'],
          ),
          lessThanOrEqualTo(kMaxWishCopyBytes),
        );
        final plan = FamilyDoc.empty(kListId).set(c, 'wishPlans', id, {
          'planId': id,
          'recipientId': id,
          'sourceWishId': id,
          'claimantPersonId': id,
          'status': 'purchased',
          ...copied,
        });
        expect(
          wishRecordBytes(plan.record('wishPlans', id)!),
          lessThanOrEqualTo(1900),
        );
      },
    );
  });

  group('compatibilidad', () {
    test('la lápida de un deseo sobrevive a fusiones, scrubbed y JSON', () {
      final a = as('nora');
      final removed = base()
          .createOwnWish(clockOf('n1', 10), a, bike, id: 'w1')
          .doc
          .removeWish(clockOf('n1', 20), a, 'w1')
          .doc;
      // Un fichero viejo, anterior a la retirada, no lo resucita.
      final old = base()
          .createOwnWish(clockOf('n1', 10), a, bike, id: 'w1')
          .doc;
      for (final m in [removed.merge(old), old.merge(removed)]) {
        expect(rec(m, 'w1').isDeleted, isTrue);
        expect(
          m.scrubbed().record(Collections.wishes, 'w1')!.isDeleted,
          isTrue,
        );
        expect(Wish.fromRecord(rec(m, 'w1')), isNull);
      }
      expect(
        FamilyDoc.fromJson(removed.toJson())
            .record(Collections.wishes, 'w1')!
            .isDeleted,
        isTrue,
      );
    });

    test('una colección desconocida sobrevive a la ida y vuelta (1.0.6)', () {
      final a = as('nora');
      final withWishes = base()
          .createOwnWish(clockOf('n1', 10), a, bike, id: 'w1')
          .doc;
      // Un 1.0.6 no conoce `wishes`: la trata como una colección más. Con una
      // fusión genérica, tras editar sus propios regalos, la conserva.
      final old106 = FamilyDoc.fromJson(withWishes.toJson())
          .set(clockOf('old', 100), Collections.gifts, 'g1', {
            'recipientId': 'aritz',
            'title': 'Libro',
            'status': 'idea',
            'surprise': false,
            'year': 2026,
          });
      final back = withWishes.merge(old106).merge(withWishes);
      expect(back.record(Collections.wishes, 'w1'), isNotNull);
      expect(
        rec(back, 'w1').fields,
        rec(withWishes, 'w1').fields,
        reason: 'ni un campo ni una marca cambian',
      );
      expect(back.record(Collections.gifts, 'g1'), isNotNull);
      final json = FamilyDoc.fromJson(back.toJson());
      expect(json.canonicalJson(), back.canonicalJson());
    });

    test('Wish.fromRecord ignora un registro incompleto', () {
      final doc = base().set(clockOf('x', 10), Collections.wishes, 'w1', {
        'title': 'Sin dueño',
        'year': 2026,
      });
      expect(Wish.fromRecord(rec(doc, 'w1')), isNull);
    });
  });
}
