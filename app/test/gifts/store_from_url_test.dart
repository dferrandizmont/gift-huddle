import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/gifts/domain/store_from_url.dart';

void main() {
  group('tiendas habituales', () {
    const known = <String, String>{
      'https://www.amazon.es/dp/B0TEST': 'Amazon',
      'https://amazon.com/dp/B0TEST': 'Amazon',
      'https://www.amazon.co.uk/dp/B0TEST': 'Amazon',
      'https://www.amazon.com.mx/dp/B0TEST': 'Amazon',
      'https://amzn.eu/d/abc123': 'Amazon',
      'https://amzn.to/3abc': 'Amazon',
      'https://a.co/d/abc': 'Amazon',
      'https://www.elcorteingles.es/juguetes/A123/': 'El Corte Inglés',
      'https://www.decathlon.es/es/p/bici': 'Decathlon',
      'https://www.ikea.com/es/es/p/kallax/': 'IKEA',
      'https://www.zara.com/es/es/camiseta-p0123.html': 'Zara',
      'https://es.aliexpress.com/item/1005.html': 'AliExpress',
      'https://a.aliexpress.com/_abc': 'AliExpress',
      'https://www.fnac.es/a1234': 'Fnac',
      'https://www.mediamarkt.es/es/product/_tablet': 'MediaMarkt',
      'https://www.pccomponentes.com/portatil': 'PcComponentes',
      'https://www.carrefour.es/supermercado': 'Carrefour',
      'https://www.toysrus.es/producto': 'Toys R Us',
      'https://www.lego.com/es-es/product/10000': 'Lego',
      'https://www.etsy.com/es/listing/123': 'Etsy',
      'https://www.ebay.es/itm/123': 'eBay',
      'https://www.apple.com/es/shop/buy-ipad': 'Apple',
      'https://www.nike.com/es/t/zapatillas': 'Nike',
      'https://www.adidas.es/zapatillas': 'Adidas',
      'https://www2.hm.com/es_es/productpage.123.html': 'H&M',
      'https://www.primark.com/es-es/p/123': 'Primark',
      'https://www.juguettos.com/producto': 'Juguettos',
      'https://www.imaginarium.es/producto': 'Imaginarium',
      'https://www.casadellibro.com/libro-cuento/1': 'Casa del Libro',
      'https://es.shein.com/p-123.html': 'Shein',
      'https://www.temu.com/es/g-123.html': 'Temu',
    };
    for (final entry in known.entries) {
      test(entry.key, () => expect(storeFromUrl(entry.key), entry.value));
    }
  });

  group('forma del enlace', () {
    test('sin www., con subdominios y sin mirar mayúsculas', () {
      expect(storeFromUrl('https://amazon.es/dp/1'), 'Amazon');
      expect(storeFromUrl('https://m.ikea.com/es/'), 'IKEA');
      expect(storeFromUrl('https://SHOP.LEGO.COM/es-es'), 'Lego');
      expect(storeFromUrl('HTTPS://WWW.Amazon.ES/dp/1'), 'Amazon');
      expect(storeFromUrl('  https://www.ikea.com/es/  '), 'IKEA');
    });

    test('con consulta y fragmento', () {
      expect(storeFromUrl('https://www.amazon.es?tag=x'), 'Amazon');
      expect(storeFromUrl('https://www.amazon.es#top'), 'Amazon');
    });
  });

  group('lo que no se reconoce', () {
    const unknown = <String>[
      // Un sitio que no está en la tabla.
      'https://www.jugueteriadelbarrio.es/patinete',
      'https://example.com/',
      // Sitios que solo parecen los de una tienda.
      'https://amazon-fake.com/dp/1',
      'https://www.amazon-fake.es/dp/1',
      'https://fakeamazon.com/dp/1',
      'https://amazon.evil.com/dp/1',
      'https://amazon.es.evil.com/dp/1',
      'https://amazon.com.evil.com/',
      'https://ikea.com.example.net/',
      'https://amazon.xyz/dp/1',
      'https://notikea.com/',
      'https://ba.co/d/abc',
      'https://amzn.eu.evil.com/d/abc',
      'https://evil.com/amazon.es',
      'https://evil.com/?u=https://www.amazon.es',
      // No es un enlace https que valga.
      'http://www.amazon.es/dp/1',
      'www.amazon.es/dp/1',
      'amazon.es',
      'javascript:alert(1)',
      'https://amazon.es@evil.example/',
      'https://www.amazon.es:8443/dp/1',
      'https://www.amazon.es dp',
      'https://',
      'https://localhost/',
      'https://192.168.0.1/',
      '',
      'Amazon',
    ];
    for (final link in unknown) {
      test(link.isEmpty ? '(vacío)' : link, () {
        expect(storeFromUrl(link), isNull);
      });
    }
  });
}
