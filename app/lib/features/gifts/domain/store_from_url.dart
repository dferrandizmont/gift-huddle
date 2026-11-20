/// El nombre de la tienda que se deduce del enlace de un regalo, sin red: solo
/// mira el nombre del sitio y lo busca en una tabla de tiendas habituales.
library;

import '../../../core/platform/user_link.dart';

/// Las terminaciones de dos partes que cuentan como una sola (`amazon.co.uk`).
const Set<String> _compoundSuffixes = {
  'co.uk',
  'org.uk',
  'com.mx',
  'com.br',
  'com.au',
  'com.tr',
  'co.jp',
};

/// Las terminaciones de una parte con las que se reconoce una tienda
/// (`amazon.es`). Otras (`amazon.xyz`) no valen: un sitio que solo lleva el
/// nombre de una tienda no es esa tienda.
const Set<String> _suffixes = {
  'com',
  'es',
  'net',
  'eu',
  'de',
  'fr',
  'it',
  'pt',
  'nl',
  'be',
  'ch',
  'at',
  'pl',
  'se',
  'dk',
  'no',
  'fi',
  'ie',
  'ca',
  'us',
  'mx',
  'br',
  'au',
  'jp',
  'in',
  'cat',
  'uk',
};

/// El nombre del sitio (la parte que va antes de la terminación) → la tienda.
/// El nombre va en minúsculas y tal como está en la dirección.
const Map<String, String> _storesByName = {
  'amazon': 'Amazon',
  'elcorteingles': 'El Corte Inglés',
  'decathlon': 'Decathlon',
  'ikea': 'IKEA',
  'zara': 'Zara',
  'aliexpress': 'AliExpress',
  'fnac': 'Fnac',
  'mediamarkt': 'MediaMarkt',
  'pccomponentes': 'PcComponentes',
  'carrefour': 'Carrefour',
  'toysrus': 'Toys R Us',
  'lego': 'Lego',
  'etsy': 'Etsy',
  'ebay': 'eBay',
  'apple': 'Apple',
  'nike': 'Nike',
  'adidas': 'Adidas',
  'hm': 'H&M',
  'primark': 'Primark',
  'juguettos': 'Juguettos',
  'imaginarium': 'Imaginarium',
  'casadellibro': 'Casa del Libro',
  'shein': 'Shein',
  'temu': 'Temu',
};

/// Los acortadores de enlaces de las tiendas: el sitio entero (o un
/// subdominio suyo), sin terminación que quitar.
const Map<String, String> _storesByShortHost = {
  'amzn.eu': 'Amazon',
  'amzn.to': 'Amazon',
  'amzn.com': 'Amazon',
  'a.co': 'Amazon',
};

/// La tienda que corresponde a [url], o `null` si no es un enlace `https`
/// válido ([userLinkUri]) o su sitio no está en la tabla.
///
/// Reconoce el sitio con subdominios y `www.` (`www.amazon.es`,
/// `m.ikea.com`) y sin distinguir mayúsculas. No reconoce sitios que solo
/// *parecen* los de una tienda: `amazon-fake.com`, `amazon.evil.com`,
/// `evil.com/amazon.es` o `amazon.xyz`.
String? storeFromUrl(String url) {
  final uri = userLinkUri(url);
  if (uri == null) {
    return null;
  }
  final host = uri.host.toLowerCase();
  for (final entry in _storesByShortHost.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) {
      return entry.value;
    }
  }
  final labels = host.split('.');
  if (labels.length < 2) {
    return null;
  }
  // La terminación: dos partes si es de las compuestas, si no la última.
  var suffixLabels = 1;
  if (labels.length >= 3 &&
      _compoundSuffixes.contains(labels.sublist(labels.length - 2).join('.'))) {
    suffixLabels = 2;
  } else if (!_suffixes.contains(labels.last)) {
    return null;
  }
  final siteIndex = labels.length - suffixLabels - 1;
  if (siteIndex < 0) {
    return null;
  }
  return _storesByName[labels[siteIndex]];
}
