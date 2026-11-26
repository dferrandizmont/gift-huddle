import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ruta de la licencia de Tabler Icons dentro de los assets.
const String kTablerLicenseAsset = 'assets/icons/tabler/LICENSE';

/// Ruta de la licencia OFL de Inter dentro de los assets.
const String kInterLicenseAsset = 'assets/fonts/inter/LICENSE.txt';

/// Ruta de la licencia MIT de la lista de palabras de BIP-39 (código de
/// recuperación, ADR 0004).
const String kBip39LicenseAsset = 'assets/recovery/LICENSE';

const String _fallbackFontAssets = 'web/fallback-fonts';

/// Añade al registro de licencias (la pantalla de licencias de Flutter) las
/// de lo que la app lleva y Flutter no conoce: los iconos de Tabler, la
/// fuente Inter, la lista de palabras de BIP-39 y las fuentes Noto de la web.
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
  if (kIsWeb) {
    registerWebFallbackFontLicenses();
  }
}

@visibleForTesting
void registerWebFallbackFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (path, packages) in const [
      ('notocoloremoji/OFL.txt', ['Noto Color Emoji']),
      ('notosansarabic/OFL.txt', ['Noto Sans Arabic']),
      (
        'OFL-Noto-CJK.txt',
        [
          'Noto Sans HK',
          'Noto Sans JP',
          'Noto Sans KR',
          'Noto Sans SC',
          'Noto Sans TC',
        ],
      ),
      ('OFL-Noto-fallback.txt', ['Noto fallback fonts']),
    ]) {
      final text = await rootBundle.loadString('$_fallbackFontAssets/$path');
      yield LicenseEntryWithLineBreaks(packages, text);
    }
  });
}
