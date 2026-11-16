import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/fresh_install.dart';
import '../../../core/platform/document_exchange.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/reparto_view_provider.dart';
import '../../family/data/secure_wipe.dart';
import '../../family/data/generation_store.dart';
import '../../family/data/generation_storage.dart';
import '../../family/data/recovery_store.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/family_store.dart';
import '../../sync/application/recovery_providers.dart';
import '../../sync/application/app_sync_v2_local.dart'
    show v2FamilyLockProvider;
import '../../family/data/storage_providers.dart';
import '../../family/data/storage.dart' show ListableFileStore;
import '../../lock/application/lock_controller.dart';
import '../../sync/application/sync_controller.dart';
import '../../sync/data/sync_config.dart';
import '../../sync/invites/invite_guest.dart';
import '../../sync/invites/invite_host.dart';
import 'appearance_provider.dart';
import 'locale_provider.dart';

/// «Borrar todo» de Ajustes: deja este móvil como recién instalado.
///
/// Son dos pasos, para que la pantalla pueda preguntar entre uno y otro si el
/// servidor no responde:
///
/// 1. [eraseServerCopy]: lo mismo que «Dejar de sincronizar». En v2, con
///    otros móviles en la familia, este sale de ella (revoca su credencial y
///    retira sus slots) y la lista sigue para los demás; si es el último, se
///    borra del servidor. Puede fallar sin red.
/// 2. [eraseLocal]: borra todo lo de este móvil y la app vuelve al primer
///    uso.
///
/// Los demás móviles de la familia conservan su copia y siguen sincronizando
/// entre ellos (en v1, el siguiente vuelve a subir la lista).
class EraseAll {
  /// Crea el borrado sobre los providers de la app.
  EraseAll(this._ref);

  final Ref _ref;

  /// Si puede haber una copia de la lista en el servidor: la app tiene
  /// servidor de sincronización y hay una familia en este móvil.
  ///
  /// No se sabe si este móvil llegó a subirla (con un solo móvil no sube
  /// nada, salvo al invitar), así que se pide el borrado siempre: el servidor
  /// contesta igual si no la tiene.
  bool get hasServerCopy =>
      _ref.read(syncTransportProvider) != null &&
      (_ref.read(familyStateProvider)?.hasFamily ?? false);

  /// Saca este móvil de la sincronización de la familia (y, si es el último,
  /// borra del servidor la copia cifrada, sus identificadores y sus
  /// invitaciones) y apaga la sincronización. No hace nada si
  /// [hasServerCopy] es `false`.
  ///
  /// Lanza `SyncTransportException` si el servidor no responde; entonces
  /// nada cambia (la sincronización sigue como estaba) y se puede repetir.
  Future<void> eraseServerCopy() async {
    if (!hasServerCopy) {
      return;
    }
    await _ref.read(syncControllerProvider.notifier).stopSyncing();
  }

  /// Borra todo lo que hay en este móvil: la lista cifrada, la identidad y
  /// las claves de la familia, las claves del móvil y de sorpresas, el PIN y
  /// la configuración del bloqueo, las preferencias y los ficheros `.regalos`
  /// exportados. Al acabar no hay familia y la app vuelve al primer uso.
  ///
  /// Primero la lista y sus claves, que es lo que importa. Todo se intenta
  /// entero aunque un paso falle (el almacén seguro o el disco pueden
  /// fallar), y al final se lanza el primer error, si lo hubo. Pase lo que
  /// pase, el almacén seguro se barre entero y el documento cifrado se borra.
  Future<void> eraseLocal() async {
    Object? failure;
    StackTrace? failureStack;
    Future<bool> step(Future<void> Function() action) async {
      try {
        await action();
        return true;
      } on Object catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
        return false;
      }
    }

    final sync = _ref.read(syncControllerProvider.notifier);
    await step(sync.suspendForRecovery);
    final familyReset = await step(() async {
      await _ref.read(v2FamilyLockProvider).run(() async {
        final secrets = _ref.read(secretStoreProvider);
        final files = _ref.read(fileStoreProvider);
        final isolatedFiles =
            files is ListableFileStore &&
            (await files.listNames()).any(
              (name) =>
                  name.startsWith('generation.') ||
                  name.startsWith('recovery.read.'),
            );
        if (await secrets.read(generationDirectoryKey) != null ||
            await files.read(recoveryJournalFile) != null ||
            isolatedFiles ||
            await secrets.read('family.transferred') == 'true') {
          await _ref.read(generationStoreProvider).eraseAllConfirmed();
          _ref.invalidate(familyStoreProvider);
          _ref.invalidate(deviceKeysStoreProvider);
          _ref.invalidate(recoveryStoreProvider);
          _ref.invalidate(recoveryApplicationProvider);
          _ref.invalidate(familyControllerProvider);
        } else {
          await _ref.read(familyControllerProvider.notifier).resetLocalData();
        }
      });
    });
    sync.finishRecoveryClaim();
    final lockReset = await step(
      () => _ref.read(lockControllerProvider.notifier).reset(),
    );
    // Por si queda en el almacén seguro alguna clave que esta versión no
    // conoce (de otra anterior), o las que no se pudieron borrar una a una.
    await step(() => _ref.read(secureStorageWipeProvider)());
    // Si el borrado de la familia se quedó a medias, el documento cifrado
    // sigue en el disco: se borra aquí (si ya no está, no pasa nada).
    await step(() => _ref.read(fileStoreProvider).delete(kFamilyDocFileName));
    await step(_erasePreferences);

    // Lo que estaba en memoria se vuelve a leer de las preferencias, ya
    // vacías: tema, idioma, vista de Reparto e invitaciones.
    _ref
      ..invalidate(inviteHostProvider)
      ..invalidate(inviteGuestProvider)
      ..invalidate(appearanceProvider)
      ..invalidate(localeProvider)
      ..invalidate(repartoViewProvider)
      ..invalidate(yearFilterProvider);

    // Lo último, lo que toca el disco: los ficheros exportados.
    await step(() => _ref.read(documentExchangeProvider).clearExports());

    // Si la familia o el bloqueo no se pudieron borrar por su camino, siguen
    // en memoria: se vuelven a leer del almacén, ya barrido, y la app queda
    // sin familia y sin PIN.
    if (!familyReset) {
      _ref.invalidate(familyControllerProvider);
    }
    if (!lockReset) {
      _ref.invalidate(lockControllerProvider);
    }

    final error = failure;
    if (error != null) {
      Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
    }
  }

  /// Quita todas las preferencias. La marca de instalación no está aquí: es
  /// el fichero [kInstallMarkerFileName], que este borrado no toca. Sin ella,
  /// el siguiente arranque en iPhone se tomaría por el primero tras instalar
  /// y vaciaría el llavero.
  Future<void> _erasePreferences() async {
    final prefs = _ref.read(sharedPreferencesProvider);
    for (final key in prefs.getKeys().toList()) {
      await prefs.remove(key);
    }
  }
}

/// «Borrar todo». Las pruebas lo sustituyen si hace falta.
final eraseAllProvider = Provider<EraseAll>(EraseAll.new);
