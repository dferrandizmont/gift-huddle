import 'package:flutter_test/flutter_test.dart';

import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/presentation/family_texts.dart';
import 'package:regalos/l10n/app_localizations.dart';
import 'package:regalos/l10n/app_localizations_ca.dart';
import 'package:regalos/l10n/app_localizations_en.dart';
import 'package:regalos/l10n/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();
  final ca = AppLocalizationsCa();
  final en = AppLocalizationsEn();

  test('es: muestra el nombre de serie en el idioma activo', () {
    expect(giverDisplayName(es, es.giverUs), es.giverUs);
    expect(giverDisplayName(es, ca.giverUs), es.giverUs);
    expect(giverDisplayName(es, en.giverUs), es.giverUs);
  });

  test('ca: muestra el nombre de serie en el idioma activo', () {
    expect(giverDisplayName(ca, es.giverUs), ca.giverUs);
    expect(giverDisplayName(ca, ca.giverUs), ca.giverUs);
    expect(giverDisplayName(ca, en.giverUs), ca.giverUs);
  });

  test('en: muestra el nombre de serie en el idioma activo', () {
    expect(giverDisplayName(en, es.giverUs), en.giverUs);
    expect(giverDisplayName(en, ca.giverUs), en.giverUs);
    expect(giverDisplayName(en, en.giverUs), en.giverUs);
  });

  test('un regalo renombrado conserva su nombre', () {
    expect(giverDisplayName(es, 'Los tíos'), 'Los tíos');
    expect(giverDisplayName(ca, 'Los tíos'), 'Los tíos');
  });

  test('un nombre ajeno se muestra tal cual', () {
    expect(giverDisplayName(es, 'Aritz'), 'Aritz');
    expect(giverDisplayName(en, 'Nora'), 'Nora');
  });

  group('sugerencias del onboarding', () {
    // Las tres sugerencias de quién regala que ofrece el onboarding.
    test('cada sugerencia se traduce al idioma activo desde cualquiera de los tres', () {
      final suggestions = <String Function(AppLocalizations)>[
        (l) => l.obGiverGrandparents,
        (l) => l.obGiverUncles,
        (l) => l.obGiverFriends,
      ];
      final locales = <AppLocalizations>[es, ca, en];
      for (final suggestion in suggestions) {
        for (final active in locales) {
          for (final stored in locales) {
            expect(
              giverDisplayName(active, suggestion(stored)),
              suggestion(active),
              reason:
                  'guardado como «${suggestion(stored)}», activo ${active.localeName}',
            );
          }
        }
      }
    });

    test('abuelos, tíos y amigos en los tres idiomas', () {
      expect(giverDisplayName(en, 'Abuelos'), 'Grandparents');
      expect(giverDisplayName(ca, 'Abuelos'), 'Avis');
      expect(giverDisplayName(es, 'Grandparents'), 'Abuelos');
      expect(giverDisplayName(es, 'Tíos'), 'Tíos');
      expect(giverDisplayName(ca, 'Tíos'), 'Oncles');
      expect(giverDisplayName(en, 'Oncles'), 'Aunts and uncles');
      expect(giverDisplayName(es, 'Amics'), 'Amigos');
      expect(giverDisplayName(en, 'Amigos'), 'Friends');
    });

    test('una sugerencia con espacios alrededor también se traduce', () {
      expect(giverDisplayName(en, '  Abuelos '), 'Grandparents');
    });

    test('la cadena vacía se devuelve tal cual', () {
      expect(giverDisplayName(es, ''), '');
      expect(giverDisplayName(en, ''), '');
    });

    test('solo espacios se devuelve tal cual, sin traducir ni recortar', () {
      expect(giverDisplayName(es, '   '), '   ');
      expect(giverDisplayName(en, '   '), '   ');
    });
  });

  group('giverNameFor', () {
    test('sin quién regala sale «Sin asignar» en el idioma activo', () {
      expect(giverNameFor(es, null), es.giverUnassigned);
      expect(giverNameFor(en, null), en.giverUnassigned);
    });

    test('un quién regala con el nombre de serie sale traducido', () {
      const giver = Giver(
        id: 'us',
        name: 'Nosotros',
        colorIndex: 0,
        householdPays: true,
        archived: false,
      );
      expect(giverNameFor(en, giver), 'Us');
      expect(giverNameFor(ca, giver), 'Nosaltres');
    });
  });
}
