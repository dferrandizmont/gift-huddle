import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/occasion_names.dart';
import 'package:regalos/features/family/presentation/family_texts.dart';
import 'package:regalos/l10n/app_localizations_ca.dart';
import 'package:regalos/l10n/app_localizations_en.dart';
import 'package:regalos/l10n/app_localizations_es.dart';

import '../helpers/memory_stores.dart';

Occasion _occasion(OccasionKind kind, String name, {String? recipientId}) =>
    Occasion(
      id: 'o-${kind.name}',
      kind: kind,
      rawKind: kind.name,
      name: name,
      month: 12,
      day: 25,
      recurring: true,
      recipientId: recipientId,
      archived: false,
    );

void main() {
  final es = AppLocalizationsEs();
  final ca = AppLocalizationsCa();
  final en = AppLocalizationsEn();

  group('ocasiones de serie: el nombre no viaja traducido', () {
    test(
      'el marcador sale del nombre de su tipo en el idioma de cada móvil',
      () {
        final santa = _occasion(OccasionKind.santa, kSeedOccasionName);
        expect(occasionTitle(es, santa), 'Navidad');
        expect(occasionTitle(ca, santa), 'Nadal');
        expect(occasionTitle(en, santa), 'Christmas');
        final kings = _occasion(OccasionKind.kings, kSeedOccasionName);
        expect(occasionTitle(es, kings), 'Reyes');
        expect(occasionTitle(en, kings), 'Three Kings');
        final tio = _occasion(OccasionKind.tio, kSeedOccasionName);
        expect(occasionTitle(ca, tio), 'Tió');
      },
    );

    test('el cumpleaños sale de la persona', () {
      final b = _occasion(
        OccasionKind.birthday,
        kSeedOccasionName,
        recipientId: 'nora',
      );
      expect(occasionTitle(es, b, personName: 'Nora'), 'Cumpleaños de Nora');
      expect(occasionTitle(ca, b, personName: 'Nora'), 'Aniversari de Nora');
      expect(occasionTitle(en, b, personName: 'Nora'), "Nora's birthday");
      // Sin la persona (borrada) no se inventa un nombre.
      expect(occasionTitle(es, b), 'Cumpleaños');
    });

    test('compatibilidad: el nombre traducido que guardaron las versiones anteriores '
        'cuenta como de serie, en cualquiera de los tres idiomas', () {
      for (final stored in ['Navidad', 'Nadal', 'Christmas']) {
        final o = _occasion(OccasionKind.santa, stored);
        expect(hasSeedOccasionName(o), isTrue, reason: stored);
        expect(occasionTitle(es, o), 'Navidad', reason: stored);
        expect(occasionTitle(ca, o), 'Nadal', reason: stored);
      }
      for (final stored in [
        'Cumpleaños de Nora',
        'Aniversari de Nora',
        "Nora's birthday",
      ]) {
        final o = _occasion(OccasionKind.birthday, stored, recipientId: 'nora');
        expect(occasionTitle(en, o, personName: 'Nora'), "Nora's birthday");
      }
    });

    test('si el usuario la renombró, se respeta tal cual', () {
      final renamed = _occasion(
        OccasionKind.santa,
        'Navidad en casa de la abuela',
      );
      expect(hasSeedOccasionName(renamed), isFalse);
      expect(occasionTitle(en, renamed), 'Navidad en casa de la abuela');
      final b = _occasion(
        OccasionKind.birthday,
        'La fiesta de Nora',
        recipientId: 'nora',
      );
      expect(occasionTitle(es, b, personName: 'Nora'), 'La fiesta de Nora');
      // Las «Otra» siempre llevan el nombre que se les puso.
      final custom = _occasion(OccasionKind.custom, 'Comunión');
      expect(occasionTitle(ca, custom), 'Comunión');
    });

    test('un tipo con su nombre en otro idioma también se traduce', () {
      final wedding = _occasion(OccasionKind.wedding, 'Wedding');
      expect(occasionTitle(es, wedding), es.occasionKindWedding);
    });
  });

  group('al sembrar', () {
    late FakePhone phone;

    setUp(() async {
      phone = FakePhone();
      addTearDown(phone.container.dispose);
    });

    test('las de serie y los cumpleaños no guardan nombre', () async {
      final c = phone.container.read(familyControllerProvider.notifier);
      await c.createFamily(deviceName: 'Móvil');
      await c.upsertRecipient(
        Recipient(
          id: 'nora',
          name: 'Nora',
          colorIndex: 0,
          birthMonth: 3,
          birthDay: 14,
          archived: false,
        ),
      );
      await c.seedDefaultOccasions('ES-CT');
      await c.ensureBirthdayOccasions();
      final state = await phone.container.read(familyControllerProvider.future);
      final seeded = state.view.occasions;
      expect(
        seeded.map((o) => o.id),
        containsAll(['seed-tio', 'seed-santa', 'seed-kings', 'birthday-nora']),
      );
      expect(seeded.map((o) => o.name).toSet(), {kSeedOccasionName});
    });
  });
}
