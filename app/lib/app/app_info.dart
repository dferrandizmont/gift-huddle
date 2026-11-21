/// Versión de la app que enseña Ajustes › Acerca de. Debe coincidir con la
/// de `pubspec.yaml` (lo comprueba una prueba).
const String kAppVersion = '1.0.5';

/// Web de la app (`web/site.toml`, `domain`).
const String kWebsiteOrigin = 'https://gifthuddle.app';

/// La política de privacidad publicada en la web, en el idioma
/// [languageCode] de la app.
///
/// Las rutas son las del generador de la web: el idioma por defecto
/// (castellano) va en `/privacy/` y los demás en `/<idioma>/privacy/`. Un
/// idioma que la web no tiene abre la versión en castellano, que es la que
/// prevalece.
Uri privacyPolicyUrl(String languageCode) => Uri.parse(switch (languageCode) {
  'ca' => '$kWebsiteOrigin/ca/privacy/',
  'en' => '$kWebsiteOrigin/en/privacy/',
  _ => '$kWebsiteOrigin/privacy/',
});
