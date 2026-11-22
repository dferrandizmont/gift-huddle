import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/platform/link_source.dart';
import 'app/app.dart';
import 'app/fresh_install.dart';
import 'app/licenses.dart';
import 'app/web_bootstrap.dart';
import 'core/prefs/shared_preferences_provider.dart';
import 'features/family/application/family_controller.dart';
import 'features/family/data/secure_wipe.dart';
import 'features/family/data/storage_providers.dart';
import 'features/sharing/application/incoming_share.dart';
import 'features/sync/application/sync_controller.dart';
import 'features/sync/data/sync_routes.dart';
import 'features/sync/invites/incoming_invite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  final prefs = await SharedPreferences.getInstance();
  // El host de reserva que funcionó se recuerda 30 minutos entre arranques.
  SyncRoutes.useStore(PrefsSyncRouteStore(prefs));
  if (kIsWeb) {
    runApp(WebBootstrap(preferences: prefs));
    return;
  }
  final container = ProviderContainer(
    retry: familyRetry,
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // iPhone, primer arranque tras instalar: el llavero sobrevive a
  // desinstalar la app y se vacía aquí, antes de que nada lea una clave.
  await clearKeychainOnFreshInstall(
    prefs: prefs,
    files: container.read(fileStoreProvider),
    wipeSecureStorage: container.read(secureStorageWipeProvider),
  );
  container.read(linkSourceProvider);
  // Empieza a escuchar los ficheros .regalos y enlaces que abren la app.
  container.read(incomingShareProvider);
  // Empieza a escuchar los enlaces de invitación a distancia.
  container.read(incomingInviteProvider);
  // Arranca la sincronización (si hay servidor configurado y familia).
  container.read(syncControllerProvider);
  runApp(
    UncontrolledProviderScope(container: container, child: const RegalosApp()),
  );
}
