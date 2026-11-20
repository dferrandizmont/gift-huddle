// SOLO PARA DESARROLLO. Punto de entrada de la versión web de demostración:
// la app en modo web, con la familia de muestra en memoria, sin red, sin
// puerta y sin PIN. No lo importa nada de la app: se compila con
// `-t lib/dev/main_demo.dart` (ver README.md).
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/licenses.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/storage_memory.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Personas de relleno (nombres inventados) y regalos de cada una.
const int _extraPeople = 12;

/// Con `--dart-define=DEMO_LARGE=true`, la lista larga (8 regalos por
/// persona) para medir el rendimiento; sin él, una familia del tamaño de la
/// real: unos 30 regalos, la primera persona de relleno con 10.
const bool _large = bool.fromEnvironment('DEMO_LARGE');

const List<String> _extraNames = [
  'Irene',
  'Marc',
  'Júlia',
  'Óscar',
  'Carla',
  'Hugo',
  'Elena',
  'Bruno',
  'Alba',
  'Teo',
  'Marina',
  'Iker',
];

const List<String> _giftTitles = [
  'Mochila de excursión',
  'Auriculares inalámbricos',
  'Juego de mesa',
  'Bufanda de lana',
  'Libro de recetas',
  'Taza térmica',
  'Puzle de 1000 piezas',
  'Lámpara de lectura',
  'Entradas de teatro',
  'Set de acuarelas',
];

int _giftsFor(int i) => _large ? 8 : (i == 0 ? 10 : (i < 6 ? 2 : 1));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  // Solo los ajustes (idioma, tema) van al almacenamiento del navegador.
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: familyRetry,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Sin servidor de sincronización: ninguna petición de red.
      syncHostProvider.overrideWithValue(''),
      secretStoreProvider.overrideWithValue(MemorySecretStore()),
      // Sin claves de móvil (la web real tampoco las tiene): un guardado de
      // memoria vacío en vez del que lanza en la web.
      deviceKeysStoreProvider.overrideWithValue(
        DeviceKeysStore(MemorySecretStore(), enabled: true),
      ),
      fileStoreProvider.overrideWithValue(MemoryFileStore()),
      webAppProvider.overrideWithValue(true),
      webGateActionsProvider.overrideWithValue(_DemoGateActions()),
      webDeviceStateProvider.overrideWithValue(
        const WebDeviceState(
          status: WebSyncStatus.confirmed,
          hasRoots: true,
          setAsideChanges: 0,
          persistenceDenied: false,
        ),
      ),
    ],
  );
  await _seed(container);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RegalosApp(webSession: true),
    ),
  );
}

/// La misma familia que `seedSample` de las pruebas, con personas de relleno.
Future<void> _seed(ProviderContainer container) async {
  final c = container.read(familyControllerProvider.notifier);
  await c.createFamily(deviceName: 'Demo');
  final people = <Recipient>[
    const Recipient(
      id: 'aritz',
      name: 'Aritz',
      colorIndex: 0,
      birthMonth: 3,
      birthDay: 14,
      birthYear: 2019,
      archived: false,
    ),
    const Recipient(
      id: 'nora',
      name: 'Nora',
      colorIndex: 4,
      birthMonth: 6,
      birthDay: 12,
      birthYear: 2022,
      archived: false,
    ),
    const Recipient(
      id: 'leo',
      name: 'Leo',
      colorIndex: 3,
      birthMonth: 8,
      birthDay: 3,
      birthYear: 2024,
      archived: false,
    ),
    for (var i = 0; i < _extraPeople; i++)
      Recipient(
        id: 'extra$i',
        name: _extraNames[i],
        colorIndex: i,
        archived: false,
      ),
  ];
  for (final p in people) {
    await c.upsertRecipient(p);
  }
  const givers = <Giver>[
    Giver(
      id: 'us',
      name: 'Nosotros',
      colorIndex: 0,
      householdPays: true,
      archived: false,
    ),
    Giver(
      id: 'yayos',
      name: 'Yayos de Terrassa',
      colorIndex: 4,
      householdPays: false,
      archived: false,
    ),
    Giver(
      id: 'avis',
      name: 'Avis de Girona',
      colorIndex: 3,
      householdPays: false,
      archived: false,
    ),
    Giver(
      id: 'marta',
      name: 'Tía Marta y Jordi',
      colorIndex: 1,
      householdPays: false,
      archived: false,
    ),
    Giver(
      id: 'pere',
      name: 'Tío Pere',
      colorIndex: 2,
      householdPays: false,
      archived: false,
    ),
    Giver(
      id: 'anna',
      name: 'Padrina Anna',
      colorIndex: 5,
      householdPays: false,
      archived: false,
    ),
  ];
  for (final g in givers) {
    await c.upsertGiver(g);
  }
  await c.seedDefaultOccasions('ES-CT');
  // Presupuestos de muestra: uno holgado, uno justo y uno que se pasa.
  await c.setOccasionBudget('seed-kings', 25000);
  await c.setOccasionBudget('seed-santa', 10000);
  await c.setOccasionBudget('seed-tio', 2000);

  Gift gift(
    String id,
    String recipient,
    String title, {
    String? giver,
    String? occasion,
    GiftStatus status = GiftStatus.idea,
    int? planned,
    int? actual,
    String? store,
    bool surprise = false,
    RequestedBy? requestedBy,
  }) => Gift(
    id: id,
    recipientId: recipient,
    title: title,
    giverId: giver,
    occasionId: occasion,
    status: status,
    rawStatus: status.name,
    plannedCents: planned,
    actualCents: actual,
    store: store,
    requestedBy: requestedBy,
    surprise: surprise,
    year: 2026,
  );

  final gifts = <Gift>[
    gift(
      'g1',
      'aritz',
      'Pijama de astronautas, talla 8',
      giver: 'us',
      occasion: 'seed-tio',
      status: GiftStatus.arrived,
      planned: 2400,
    ),
    gift(
      'g2',
      'aritz',
      'Libro de dinosaurios con solapas',
      giver: 'marta',
      occasion: 'seed-tio',
      planned: 1800,
      store: 'Librería',
    ),
    gift(
      'g3',
      'aritz',
      'Estación de bomberos de bloques',
      giver: 'us',
      occasion: 'seed-kings',
      status: GiftStatus.bought,
      planned: 5500,
      actual: 4999,
      requestedBy: const RequestedByRecipient('aritz'),
    ),
    gift(
      'g4',
      'aritz',
      'Bici de 20" con cambios',
      giver: 'yayos',
      occasion: 'seed-kings',
      status: GiftStatus.decided,
      planned: 18000,
      store: 'Decathlon',
      surprise: true,
    ),
    gift(
      'g5',
      'aritz',
      'Patinete',
      occasion: 'seed-kings',
      store: 'Juguetería del barrio',
    ),
    gift(
      'g6',
      'nora',
      'Puzle de 48 piezas',
      giver: 'avis',
      occasion: 'seed-santa',
      status: GiftStatus.decided,
      planned: 1900,
      store: 'Juguetería del barrio',
    ),
    gift(
      'g7',
      'nora',
      'Puzle de 48 piezas',
      giver: 'anna',
      occasion: 'seed-kings',
      planned: 3000,
    ),
    gift(
      'g8',
      'nora',
      'Cocinita de madera',
      giver: 'us',
      occasion: 'seed-santa',
      status: GiftStatus.wrapped,
      planned: 6450,
    ),
    gift(
      'g9',
      'leo',
      'Tren de madera',
      giver: 'us',
      occasion: 'seed-kings',
      status: GiftStatus.bought,
      planned: 3100,
    ),
    gift(
      'g10',
      'nora',
      'Libro de cuentos',
      giver: 'pere',
      occasion: 'seed-kings',
      status: GiftStatus.delivered,
      planned: 2500,
      actual: 2500,
    ),
  ];
  // Lista larga para medir el rendimiento: regalos inventados de las personas
  // de relleno.
  for (var i = 0; i < _extraPeople; i++) {
    for (var j = 0; j < _giftsFor(i); j++) {
      gifts.add(
        gift(
          'x${i}_$j',
          'extra$i',
          _giftTitles[(i + j) % _giftTitles.length],
          giver: const ['us', 'yayos', 'avis', 'marta', 'pere', 'anna'][j % 6],
          occasion: j.isEven ? 'seed-kings' : 'seed-santa',
          status: GiftStatus.values[(i + j) % GiftStatus.values.length],
          planned: 1000 + 250 * j,
        ),
      );
    }
  }
  for (final g in gifts) {
    await c.upsertGift(g);
  }
  await container.read(lockControllerProvider.notifier).skipSetup();
}

/// Acciones de la puerta que no hacen nada: aquí no hay puerta.
class _DemoGateActions implements WebGateActions {
  @override
  Future<void> restartPairing() async {}
  @override
  Future<void> submitPin(String pin) async {}
  @override
  Future<void> choosePin(String pin) async {}
  @override
  Future<void> useHere() async {}
  @override
  Future<void> retry() async {}
  @override
  Future<void> reconnect() async {}
  @override
  Future<void> eraseComputer() async {}
  @override
  Future<void> lock() async {}
  @override
  Future<WebPinChangeResult> changePin(String current, String next) async =>
      WebPinChangeResult.failed;
  @override
  Future<void> forgetComputer() async {}
}
