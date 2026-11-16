// Ayudas de las pruebas del ADR 0004: tres móviles (Aritz, Leo y Nora), con
// Nora como persona protegida.
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';

/// Lista de las pruebas.
const kListId = 'list-1';

/// Base de los relojes: el orden lo dan los milisegundos de cada prueba.
const kFuture = 4102444800000;

/// Las personas de las pruebas.
const kPeople = {'aritz', 'leo', 'nora'};

/// Reloj de [node] que empieza en [millis].
HlcClock clockOf(String node, int millis) => HlcClock(
  node: node,
  last: Hlc(millis: kFuture + millis, counter: 0, node: node),
);

/// Un móvil de prueba.
class Phone {
  Phone(this.id, this.self, this.keys);

  /// Id del móvil (el nodo de su reloj).
  final String id;

  /// Persona de «Yo».
  final String? self;

  /// Sus claves.
  final DeviceKeys keys;

  /// Crea el móvil con semillas fijas.
  static Future<Phone> create(String id, String? self, int seed) async => Phone(
    id,
    self,
    await DeviceKeys.fromSeedsForTesting(
      agreementSeed: List<int>.filled(32, seed),
      signingSeed: List<int>.filled(32, seed + 100),
      serviceCredential: List<int>.filled(32, seed + 200),
    ),
  );

  /// Su ficha del registro.
  Future<DeviceRecord> record({String? person, int seq = 1}) =>
      DeviceRecord.create(
        keys: keys,
        listId: kListId,
        deviceId: id,
        personId: person ?? self,
        seq: seq,
      );

  /// El registro visto desde este móvil.
  Future<RegistryView> viewOf(
    DeviceRegistry registry, {
    Set<String> people = kPeople,
  }) => registry.viewFor(
    me: id,
    mySigningKey: keys.publicKeys.signing,
    livePeople: people,
  );
}

/// Un registro con las fichas de [phones], avalados todos entre sí.
Future<DeviceRegistry> registryOf(List<Phone> phones) async {
  var registry = DeviceRegistry.empty(kListId);
  final records = <Phone, DeviceRecord>{};
  for (final phone in phones) {
    records[phone] = await phone.record();
    registry = await registry.withRecord(records[phone]!);
  }
  for (final by in phones) {
    for (final other in phones) {
      if (by == other) continue;
      registry = await registry.withVouch(
        await Vouch.create(
          keys: by.keys,
          voucher: records[by]!,
          record: records[other]!,
        ),
      );
    }
  }
  return registry;
}

/// Los tres móviles: Aritz y Leo pueden abrir las sorpresas de Nora; Nora no.
class Family {
  Family(this.aritz, this.leo, this.nora, this.key, this.registry, this._views);

  final Phone aritz;
  final Phone leo;
  final Phone nora;

  /// La clave de las sorpresas de Nora, época 1.
  final SurpriseKey key;

  /// El registro: los tres móviles, avalados entre sí.
  final DeviceRegistry registry;

  final Map<String, RegistryView> _views;

  /// El registro visto desde [phone].
  RegistryView viewOf(Phone phone) => _views[phone.id]!;

  /// El registro visto desde el móvil de Aritz.
  RegistryView get view => viewOf(aritz);

  /// Un conjunto verificado con [slots].
  Future<SlotSet> setOf(Iterable<SealedSlot> slots) async =>
      (await SlotSet.verified(slots, view: view)).$1;

  /// Llavero de Aritz y Leo.
  SurpriseKeyring get authorizedKeyring => SurpriseKeyring([key]);

  static Future<Family> create() async {
    final aritz = await Phone.create('aritz-phone', 'aritz', 1);
    final leo = await Phone.create('leo-phone', 'leo', 2);
    final nora = await Phone.create('nora-phone', 'nora', 3);
    final registry = await registryOf([aritz, leo, nora]);
    return Family(
      aritz,
      leo,
      nora,
      SurpriseKey(
        personId: 'nora',
        epoch: 1,
        bytes: List<int>.filled(32, 42),
        audience: const ['aritz-phone', 'leo-phone'],
      ),
      registry,
      {
        for (final phone in [aritz, leo, nora])
          phone.id: await phone.viewOf(registry),
      },
    );
  }
}

/// Campos de un regalo.
Map<String, Object?> giftFields(
  String recipientId,
  String title, {
  String? note,
  int year = 2026,
  int plannedCents = 1000,
}) => <String, Object?>{
  'recipientId': recipientId,
  'title': title,
  'note': note,
  'giverId': 'nosotros',
  'plannedCents': plannedCents,
  'status': 'idea',
  'surprise': true,
  'year': year,
};

/// Documento común con Aritz, Leo y Nora.
FamilyDoc commonWithPeople(HlcClock clock) {
  var doc = FamilyDoc.empty(kListId);
  var color = 0;
  for (final (id, name) in [
    ('aritz', 'Aritz'),
    ('leo', 'Leo'),
    ('nora', 'Nora'),
  ]) {
    doc = doc.set(clock, Collections.recipients, id, {
      'name': name,
      'colorIndex': color++,
      'archived': false,
    });
  }
  return doc.set(clock, Collections.givers, 'nosotros', {
    'name': 'Nosotros',
    'colorIndex': 0,
    'householdPays': true,
    'archived': false,
  });
}

/// Documento de ámbito con [titles] para Nora.
FamilyDoc scopeWith(HlcClock clock, List<String> titles) {
  var doc = FamilyDoc.empty(kListId);
  for (var i = 0; i < titles.length; i++) {
    doc = doc.set(
      clock,
      Collections.gifts,
      's$i',
      giftFields('nora', titles[i], note: 'Nota del regalo $i'),
    );
  }
  return doc;
}
