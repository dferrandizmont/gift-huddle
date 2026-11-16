import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ruta de la licencia de Tabler Icons dentro de los assets.
const String kTablerLicenseAsset = 'assets/icons/tabler/LICENSE';

/// Ruta de la licencia OFL de Inter dentro de los assets.
const String kInterLicenseAsset = 'assets/fonts/inter/LICENSE.txt';

/// Ruta de la licencia MIT de la lista de palabras de BIP-39 (código de
/// recuperación, ADR 0004).
const String kBip39LicenseAsset = 'assets/recovery/LICENSE';

/// Añade al registro de licencias (la pantalla de licencias de Flutter) las
/// de lo que la app lleva y Flutter no conoce: los iconos de Tabler, la
/// fuente Inter y la lista de palabras de BIP-39.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(kTablerLicenseAsset);
    yield LicenseEntryWithLineBreaks(<String>['Tabler Icons'], text);
  });
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(kInterLicenseAsset);
    yield LicenseEntryWithLineBreaks(<String>['Inter'], text);
  });
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(kBip39LicenseAsset);
    yield LicenseEntryWithLineBreaks(<String>['BIP-39 word list'], text);
  });
}
