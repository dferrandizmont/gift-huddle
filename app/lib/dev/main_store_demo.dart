// SOLO PARA DESARROLLO. Punto de entrada de las capturas de tienda y de la
// web: la app MÓVIL con una familia de muestra en memoria, sin red, sin PIN y
// sin asistente inicial. No lo importa nada de la app: se compila con
// `-t lib/dev/main_store_demo.dart` (ver README.md).
//
// `--dart-define=DEMO_LOCALE=es|ca|en` fija el idioma (y el de los datos); el
// tema sigue al del sistema (`adb shell cmd uimode night yes|no`).
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/licenses.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/storage_memory.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/settings/application/appearance_provider.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _lang = String.fromEnvironment('DEMO_LOCALE', defaultValue: 'es');

/// `--dart-define=DEMO_LOCK=true`: la app arranca bloqueada con un PIN de
/// muestra (para la captura de privacidad: la pantalla de bloqueo no enseña
/// ningún dato de la familia).
const bool _lock = bool.fromEnvironment('DEMO_LOCK');

int get _i => _lang == 'ca' ? 1 : (_lang == 'en' ? 2 : 0);

/// Quien regala: [es, ca, en].
const Map<String, List<String>> _giverNames = {
  'us': ['Nosotros', 'Nosaltres', 'Us'],
  'grand': ['Abuelos', 'Avis', 'Grandma'],
  'marta': ['Tía Marta', 'Tieta Marta', 'Aunt Marta'],
  'pere': ['Tío Pere', 'Oncle Pere', 'Uncle Pere'],
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'locale': _lang,
    AppearanceNotifier.themeModeKey: ThemeMode.system.name,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: familyRetry,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Sin servidor de sincronización: ninguna petición de red.
      syncHostProvider.overrideWithValue(''),
      secretStoreProvider.overrideWithValue(MemorySecretStore()),
      deviceKeysStoreProvider.overrideWithValue(
        DeviceKeysStore(MemorySecretStore(), enabled: true),
      ),
      fileStoreProvider.overrideWithValue(MemoryFileStore()),
    ],
  );
  await _seed(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const RegalosApp()),
  );
}

Future<void> _seed(ProviderContainer container) async {
  final c = container.read(familyControllerProvider.notifier);
  await c.createFamily(deviceName: 'Demo');
  const people = <Recipient>[
    Recipient(
      id: 'aritz',
      name: 'Aritz',
      colorIndex: 0,
      birthMonth: 3,
      birthDay: 14,
      birthYear: 2019,
      archived: false,
    ),
    Recipient(
      id: 'nora',
      name: 'Nora',
      colorIndex: 4,
      birthMonth: 12,
      birthDay: 2,
      birthYear: 2022,
      archived: false,
    ),
    Recipient(
      id: 'leo',
      name: 'Leo',
      colorIndex: 3,
      birthMonth: 2,
      birthDay: 9,
      birthYear: 2024,
      archived: false,
    ),
  ];
  for (final p in people) {
    await c.upsertRecipient(p);
  }
  var color = 0;
  for (final e in _giverNames.entries) {
    await c.upsertGiver(
      Giver(
        id: e.key,
        name: e.value[_i],
        colorIndex: const [0, 4, 3, 1][color++],
        householdPays: e.key == 'us',
        archived: false,
      ),
    );
  }
  await c.seedDefaultOccasions('ES-CT');

  Gift gift(
    String id,
    String recipient,
    List<String> title, {
    String? giver,
    String? occasion,
    GiftStatus status = GiftStatus.idea,
    int? planned,
    int? actual,
    List<String>? store,
    bool surprise = false,
    RequestedBy? requestedBy,
  }) => Gift(
    id: id,
    recipientId: recipient,
    title: title[_i],
    giverId: giver,
    occasionId: occasion,
    status: status,
    rawStatus: status.name,
    plannedCents: planned,
    actualCents: actual,
    store: store?[_i],
    requestedBy: requestedBy,
    surprise: surprise,
    year: 2026,
  );

  const shop = ['Juguetería del barrio', 'Joguina del barri', 'Local toy shop'];
  const books = ['Librería', 'Llibreria', 'Bookshop'];

  final gifts = <Gift>[
    // Aritz
    gift(
      'g1',
      'aritz',
      ['Pijama de astronautas', 'Pijama d\'astronautes', 'Astronaut pyjamas'],
      giver: 'us',
      occasion: 'seed-tio',
      status: GiftStatus.arrived,
      planned: 2400,
      actual: 2250,
    ),
    gift(
      'g2',
      'aritz',
      [
        'Libro de dinosaurios con solapas',
        'Llibre de dinosaures amb solapes',
        'Dinosaur lift-the-flap book',
      ],
      giver: 'marta',
      occasion: 'seed-tio',
      status: GiftStatus.decided,
      planned: 1800,
      store: books,
    ),
    gift(
      'g3',
      'aritz',
      [
        'Kit para montar un robot',
        'Kit per muntar un robot',
        'Build-your-own robot kit',
      ],
      giver: 'us',
      occasion: 'seed-santa',
      status: GiftStatus.bought,
      planned: 5500,
      actual: 4999,
      requestedBy: const RequestedByRecipient('aritz'),
    ),
    gift(
      'g4',
      'aritz',
      ['Telescopio infantil', 'Telescopi infantil', 'Children\'s telescope'],
      giver: 'grand',
      occasion: 'seed-kings',
      status: GiftStatus.decided,
      planned: 18000,
      store: shop,
      surprise: true,
    ),
    gift(
      'g5',
      'aritz',
      ['Patinete plegable', 'Patinet plegable', 'Folding scooter'],
      occasion: 'seed-kings',
      planned: 4500,
      store: shop,
    ),
    // Nora
    gift(
      'g6',
      'nora',
      ['Puzle de 48 piezas', 'Puzle de 48 peces', '48-piece puzzle'],
      giver: 'grand',
      occasion: 'seed-santa',
      status: GiftStatus.decided,
      planned: 1900,
      store: shop,
    ),
    gift(
      'g7',
      'nora',
      ['Puzle de 48 piezas', 'Puzle de 48 peces', '48-piece puzzle'],
      giver: 'pere',
      occasion: 'seed-santa',
      planned: 2200,
    ),
    gift(
      'g8',
      'nora',
      ['El Principito', 'El petit príncep', 'The Little Prince'],
      giver: 'us',
      occasion: 'seed-santa',
      status: GiftStatus.wrapped,
      planned: 1299,
      actual: 6450,
    ),
    gift(
      'g9',
      'nora',
      ['Bloques magnéticos', 'Blocs magnètics', 'Magnetic building tiles'],
      giver: 'marta',
      occasion: 'birthday-nora',
      status: GiftStatus.bought,
      planned: 2800,
      actual: 2650,
    ),
    gift(
      'g10',
      'nora',
      ['Libro de cuentos', 'Llibre de contes', 'Storybook'],
      giver: 'pere',
      occasion: 'seed-kings',
      status: GiftStatus.delivered,
      planned: 2500,
      actual: 2500,
      store: books,
    ),
    // Leo
    gift(
      'g11',
      'leo',
      ['Tren de madera', 'Tren de fusta', 'Wooden train set'],
      giver: 'us',
      occasion: 'seed-santa',
      status: GiftStatus.bought,
      planned: 3100,
      actual: 2990,
    ),
    gift(
      'g12',
      'leo',
      ['Bloques de goma', 'Blocs de goma', 'Soft foam blocks'],
      giver: 'grand',
      occasion: 'seed-santa',
      planned: 2400,
    ),
    gift(
      'g13',
      'leo',
      ['Pelota con luces', 'Pilota amb llums', 'Light-up ball'],
      giver: 'marta',
      occasion: 'seed-kings',
      status: GiftStatus.decided,
      planned: 1500,
    ),
    // Más regalos para que los paneles de detalle de la tablet se vean llenos.
    gift(
      'g14',
      'aritz',
      [
        'Kit de experimentos de ciencia',
        'Kit d\'experiments de ciència',
        'Science experiment kit',
      ],
      giver: 'pere',
      occasion: 'seed-kings',
      status: GiftStatus.decided,
      planned: 3200,
      store: shop,
    ),
    gift(
      'g15',
      'aritz',
      ['Circuito de canicas', 'Circuit de bales', 'Marble run'],
      giver: 'marta',
      occasion: 'birthday-aritz',
      status: GiftStatus.bought,
      planned: 3900,
      actual: 3590,
      store: shop,
    ),
    gift(
      'g16',
      'aritz',
      [
        'Atlas ilustrado del mundo',
        'Atles il·lustrat del món',
        'Illustrated world atlas',
      ],
      giver: 'us',
      occasion: 'seed-kings',
      status: GiftStatus.wrapped,
      planned: 3500,
      actual: 3500,
      store: books,
    ),
    gift(
      'g17',
      'aritz',
      [
        'Juego de mesa cooperativo',
        'Joc de taula cooperatiu',
        'Cooperative board game',
      ],
      giver: 'grand',
      occasion: 'seed-tio',
      status: GiftStatus.arrived,
      planned: 2900,
      actual: 2750,
    ),
    gift(
      'g18',
      'nora',
      [
        'Caballete con pizarra',
        'Cavallet amb pissarra',
        'Easel with chalkboard',
      ],
      giver: 'us',
      occasion: 'birthday-nora',
      status: GiftStatus.decided,
      planned: 3600,
    ),
    gift(
      'g19',
      'nora',
      ['Microscopio infantil', 'Microscopi infantil', 'Children\'s microscope'],
      giver: 'grand',
      occasion: 'seed-kings',
      status: GiftStatus.decided,
      planned: 4200,
      store: shop,
    ),
    gift(
      'g20',
      'nora',
      ['Pinturas de dedos', 'Pintures de dits', 'Finger paints'],
      giver: 'pere',
      occasion: 'seed-tio',
      status: GiftStatus.arrived,
      planned: 1200,
      actual: 1090,
    ),
    gift(
      'g21',
      'nora',
      ['Plastilina y moldes', 'Plastilina i motlles', 'Modelling clay set'],
      giver: 'marta',
      occasion: 'seed-kings',
      planned: 2600,
    ),
    gift(
      'g22',
      'leo',
      [
        'Libro de tela con texturas',
        'Llibre de tela amb textures',
        'Textured cloth book',
      ],
      giver: 'marta',
      occasion: 'birthday-leo',
      status: GiftStatus.bought,
      planned: 1400,
      actual: 1350,
      store: books,
    ),
    gift(
      'g23',
      'leo',
      ['Cubo de actividades', 'Cub d\'activitats', 'Activity cube'],
      giver: 'us',
      occasion: 'seed-kings',
      status: GiftStatus.decided,
      planned: 3400,
      store: shop,
    ),
    gift(
      'g24',
      'leo',
      [
        'Arcoíris de madera apilable',
        'Arc de Sant Martí de fusta',
        'Wooden stacking rainbow',
      ],
      giver: 'pere',
      occasion: 'seed-santa',
      status: GiftStatus.arrived,
      planned: 2200,
      actual: 2050,
    ),
    gift(
      'g25',
      'leo',
      ['Xilófono de colores', 'Xilòfon de colors', 'Colourful xylophone'],
      giver: 'grand',
      occasion: 'seed-tio',
      status: GiftStatus.wrapped,
      planned: 1800,
      actual: 1800,
    ),
    gift(
      'g26',
      'leo',
      ['Pijama de dinosaurios', 'Pijama de dinosaures', 'Dinosaur pyjamas'],
      giver: 'us',
      occasion: 'birthday-leo',
      status: GiftStatus.delivered,
      planned: 2100,
      actual: 1950,
    ),
  ];
  for (final g in gifts) {
    await c.upsertGift(g);
  }
  final lock = container.read(lockControllerProvider.notifier);
  if (_lock) {
    await lock.setPin('2468');
    await lock.lockNow();
  } else {
    await lock.skipSetup();
  }
}
