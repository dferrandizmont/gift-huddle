import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/family/data/storage.dart';

/// Marca de que esta instalación ya ha arrancado alguna vez: un fichero vacío
/// entre los ficheros privados de la app (Application Support), junto al
/// documento cifrado.
///
/// Se borra al desinstalar la app y, como todo lo que escribe
/// `FileStore.writeAtomic`, **no entra en las copias de seguridad de iOS**:
/// al restaurar una copia falta, igual que el documento, y el arranque se
/// trata como el primero tras instalar. Si falta es el primer arranque tras
/// instalar (o tras actualizar desde una versión que aún no la ponía).
/// «Borrar todo» la conserva.
const String kInstallMarkerFileName = 'install.started';

/// La marca de las versiones anteriores, en las preferencias. Las
/// preferencias (`NSUserDefaults`) sí viajan en las copias de seguridad de
/// iOS, así que al restaurar una copia en el mismo iPhone la marca volvía y
/// las claves y el PIN viejos del llavero reaparecían. Ya solo se lee para
/// migrar: si está, se crea el fichero y se quita.
const String kLegacyInstallMarkerKey = 'install.started';

/// El fichero del documento cifrado de la familia (el de `FamilyStore`). Se
/// borra al desinstalar: si existe, la app ya se estaba usando.
const String kFamilyDocFileName = 'family.doc';

/// Primer arranque tras instalar en iPhone: vacía el almacén seguro.
///
/// El llavero de iOS sobrevive a desinstalar la app, así que al reinstalarla
/// seguirían ahí la clave de la familia, la identidad y el PIN de la
/// instalación anterior. Aquí se borran antes de que nada los lea, para que
/// una instalación nueva empiece de cero (política de privacidad, apartado 6).
///
/// - Solo en iOS. En Android el almacén seguro va en los datos de la app
///   (cifrado con una clave del Keystore), que se borran al desinstalar, y la
///   app no entra en copias de seguridad ni en traspasos a otro móvil.
/// - La marca es el fichero [kInstallMarkerFileName], que no viaja en las
///   copias de seguridad: restaurar una copia cuenta como instalar de nuevo.
/// - Si falta el fichero pero está la marca antigua de las preferencias
///   ([kLegacyInstallMarkerKey]), es una actualización: no se toca nada, se
///   crea el fichero y se quita la preferencia, para que no viaje en las
///   copias que se hagan desde ahora.
/// - Si falta la marca pero ya hay un documento guardado, no es una
///   instalación nueva sino una actualización desde una versión anterior a la
///   marca: no se toca nada y solo se pone la marca. Sin esto, actualizar
///   borraría la lista.
/// - Nunca impide arrancar: si algo falla no se pone la marca y se reintenta
///   en el siguiente arranque.
///
/// Devuelve `true` si ha vaciado el almacén seguro.
Future<bool> clearKeychainOnFreshInstall({
  required SharedPreferences prefs,
  required FileStore files,
  required Future<void> Function() wipeSecureStorage,
  bool? isIOS,
}) async {
  try {
    final legacy = prefs.getBool(kLegacyInstallMarkerKey) ?? false;
    if (await files.read(kInstallMarkerFileName) != null) {
      if (legacy) {
        // Quedó de una migración a medias.
        await prefs.remove(kLegacyInstallMarkerKey);
      }
      return false;
    }
    if (legacy) {
      // Actualización desde una versión con la marca en las preferencias.
      // Primero el fichero: si falla, la preferencia sigue y se reintenta.
      await files.writeAtomic(kInstallMarkerFileName, Uint8List(0));
      await prefs.remove(kLegacyInstallMarkerKey);
      return false;
    }
    final ios =
        isIOS ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
    var wiped = false;
    if (ios && await files.read(kFamilyDocFileName) == null) {
      await wipeSecureStorage();
      wiped = true;
    }
    await files.writeAtomic(kInstallMarkerFileName, Uint8List(0));
    return wiped;
  } on Object {
    return false;
  }
}
