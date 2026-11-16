import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart' show kSlotBodyBytesForTesting;
import '../sync/v2_harness.dart';
import 'web_engine_support.dart';

Uint8List slot() {
  final out = BytesBuilder()
    ..add([0x47, 0x48, 0x53, 0x02])
    ..add(List.filled(29, 0));
  for (final id in [kV2List, 'nora', 'aritz-phone']) {
    out
      ..addByte(id.length)
      ..add(ascii.encode(id));
  }
  return (out..add(List.filled(kSlotBodyBytesForTesting, 0))).takeBytes();
}

void main() {
  // B7 (M1): la web solo recuerda lo que aprobó el anfitrión (el común del
  // checkpoint y los suelos de slots firmados), así que la protección se
  // publica antes de aprobar. Un slot que el servidor pone después de la
  // aprobación ya no cuenta: no estaba verificado. El testigo de slots desde
  // los suelos firmados se prueba en `pairing_v2_checkpoint_test.dart`.
  for (final protection in ['false policy', 'policy tombstone']) {
    for (final interrupted in [false, true]) {
      test(
        '$protection seen at finish survives disappearance before first sync; interrupted=$interrupted',
        () async {
          final h = WebHarness();
          addTearDown(h.close);
          await h.setup(
            enroll: false,
            beforeApprove: () async {
              if (protection == 'slot') {
                await h.publish(
                  slots: [
                    V2SlotChange(
                      personId: 'nora',
                      deviceId: 'aritz-phone',
                      data: slot(),
                    ),
                  ],
                );
              } else {
                var doc = h.phone.doc.set(
                  h.phone.clock,
                  Collections.policies,
                  'nora',
                  {'hideOwnGifts': false},
                );
                if (protection == 'policy tombstone') {
                  doc = doc.delete(h.phone.clock, Collections.policies, 'nora');
                }
                await h.publish(doc: doc);
              }
            },
          );
          // The saved enrollment snapshot is the only remaining witness.
          await h.publish(
            doc: FamilyDoc(
              listId: kV2List,
              collections: {
                for (final c in h.phone.doc.collections.entries)
                  if (c.key != Collections.policies) c.key: c.value,
              },
            ),
            slots: [
              const V2SlotChange(
                personId: 'nora',
                deviceId: 'aritz-phone',
                data: null,
              ),
            ],
          );
          if (interrupted) {
            h.worker.tamper = (method, uri, response) {
              if (uri.path.endsWith('/commit')) {
                throw StateError('cut after durable enrollment');
              }
              return response;
            };
            await expectLater(
              h.guest.enroll(h.vault, '123456'),
              throwsStateError,
            );
            expect((await h.store.read()).pending, isNotNull);
            h.worker.tamper = null;
            h.vault.lock();
            await h.vault.unlock('123456');
          } else {
            await h.guest.enroll(h.vault, '123456');
          }
          await h.engine.sync();
          expect(await h.queue.blockedPeople(), contains('nora'));
          final before = h.engine.candidate!;
          await h.engine.save(
            before,
            before.set(
              HlcClock(node: 'web', last: before.maxStamp),
              Collections.gifts,
              'new',
              {'recipientId': 'nora', 'title': 'Libro'},
            ),
          );
          await h.engine.sync();
          expect((await h.queue.entries()).single.setAside, isTrue);
          expect((await h.remote()).record(Collections.gifts, 'new'), isNull);
          expect(h.worker.calls['PUT common'], isNull);
        },
      );
    }
  }
}
