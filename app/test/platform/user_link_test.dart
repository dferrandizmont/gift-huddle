import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/external_link_native.dart';
import 'package:regalos/core/platform/user_link.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';

/// El enlace de un regalo lo escribe la persona: solo `https` con un sitio de
/// verdad llega al navegador.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('userLinkUri', () {
    test('acepta enlaces https normales', () {
      for (final link in const [
        'https://amzn.eu/d/07GTji3t',
        'https://www.amazon.es/dp/X',
        'https://www.amazon.es/dp/B0TEST?th=1&psc=1#x',
        'HTTPS://Tienda.Example/ruta',
        'https://sub.tienda.example.com/a/b',
        'https://xn--juguetera-n5a.es/',
        'https://tienda.XN--P1AI/',
        'https://tienda.example/a%2Fb?q=a@b#c',
        'https://no-gifthuddle.app/',
        'https://gifthuddle.app.example/',
        '  https://ikea.com/es/  ',
      ]) {
        expect(userLinkUri(link), isNotNull, reason: link);
      }
    });

    test('rechaza lo demás', () {
      for (final link in const [
        '',
        '   ',
        'amazon.es',
        'www.amazon.es',
        'http://amazon.es',
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        'data:text/html,<b>x</b>',
        'file:///etc/hosts',
        'intent://amazon.es/#Intent;scheme=https;end',
        'tel:112',
        'mailto:a@b.example',
        'https://',
        'https:///ruta',
        'https://localhost/',
        'https://tienda/',
        'https://127.0.0.1/',
        'https://192.168.1.1/',
        'https://2130706433/',
        'https://127.0.0.0x1/',
        'https://0x7f.0.0.0x1/',
        'https://0177.0.0.01/',
        'https://[::1]/',
        'https://１２７.０.０.１/',
        'https://1.1.1.١/',
        'https://аmazon.es/', // «а» cirílica.
        'https://Kiosco.es/', // El signo Kelvin tiene una minúscula ASCII.
        'https://juguetería.es/patinete',
        'https://%61mazon.es/',
        'https://tienda.es%2e/',
        'https://amazon.es@evil.example/',
        'https://usuario:clave@tienda.example/',
        'https://tienda.example:443/',
        'https://tienda.example:8443/',
        r'https://tienda.example\otra.example/',
        r'https://tienda.example/a\b',
        'https://tienda..example/',
        'https://.tienda.example/',
        'https://tienda.example./',
        'https://-tienda.example/',
        'https://tienda-.example/',
        'https://mi_tienda.example/',
        'https://tienda.e/',
        'https://tienda.e5/',
        'https://tienda.xn--/',
        'https://tienda.xn--abc-/',
        'https://tienda.example/con espacio',
        'https://tienda example.com/',
        'https://tienda.example/\nx',
      ]) {
        expect(userLinkUri(link), isNull, reason: link);
      }
    });

    test('limita el largo de cada etiqueta a 63 caracteres', () {
      expect(userLinkUri('https://${'a' * 63}.${'b' * 63}/'), isNotNull);
      expect(userLinkUri('https://tienda.xn--${'a' * 59}/'), isNotNull);
      expect(userLinkUri('https://${'a' * 64}.es/'), isNull);
      expect(userLinkUri('https://tienda.${'a' * 64}/'), isNull);
      expect(userLinkUri('https://tienda.xn--${'a' * 60}/'), isNull);
    });

    test('rechaza caracteres de formato y controles C1 en todo el texto', () {
      for (final character in const [
        '\u202e', // Control bidireccional.
        '\u200f', // Marca de derecha a izquierda.
        '\u200b', // Espacio de ancho cero.
        '\ufeff', // Dart lo quita al recortar.
        '\u{e0001}', // Carácter de formato fuera del plano básico.
        '\u0080',
        '\u0085',
        '\u009f',
      ]) {
        for (final link in [
          '${character}https://tienda.example/',
          'https://tienda.example/$character',
          'https://tienda.example?q=a${character}b',
          'https://tienda.example/#${character}a',
        ]) {
          expect(userLinkUri(link), isNull, reason: '${link.codeUnits}');
        }
      }
    });

    test('rechaza los dominios propios y sus subdominios', () {
      for (final link in const [
        'https://gifthuddle.app/',
        'https://gifthuddle.app/i#example',
        'https://GIFTHUDDLE.APP/i#example',
        'https://web.gifthuddle.app/',
        'https://sub.sync.gifthuddle.app/',
      ]) {
        expect(userLinkUri(link), isNull, reason: link);
      }
    });

    test('rechaza también el dominio configurado para las invitaciones', () {
      final endpoint = SyncEndpoint.parse(
        kSyncHost,
        invitationOrigin: kInvitationOrigin,
      )!;
      final host = endpoint.invitationOrigin.host;
      expect(userLinkUri('https://$host/i#example'), isNull);
      expect(userLinkUri('https://sub.$host/i#example'), isNull);
    });

    test('rechaza un enlace demasiado largo', () {
      final long = 'https://tienda.example/${'a' * kUserLinkMaxLength}';
      expect(userLinkUri(long), isNull);
    });
  });

  group('userLinkHost', () {
    test('el sitio sin www. y en minúsculas', () {
      expect(userLinkHost('https://www.Amazon.ES/dp/1'), 'amazon.es');
      expect(userLinkHost('https://amzn.eu/d/abc'), 'amzn.eu');
      expect(userLinkHost('https://m.ikea.com/es'), 'm.ikea.com');
    });

    test('null si no es un enlace que se pueda abrir', () {
      expect(userLinkHost('amazon.es'), isNull);
      expect(userLinkHost('http://amazon.es'), isNull);
      expect(userLinkHost(''), isNull);
    });
  });

  group('el abridor nativo, con enlaces de la persona', () {
    const channel = MethodChannel('com.dferrandizmont.regalos/incoming');
    const native = NativeExternalLinkOpener();
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('pide al código nativo abrir un https de cualquier tienda', () async {
      expect(await native.openUserLink('https://amzn.eu/d/abc'), isTrue);
      expect(calls.single.method, 'openUserUrl');
      expect(calls.single.arguments, 'https://amzn.eu/d/abc');
    });

    test('no deja pasar al código nativo lo que no es https válido', () async {
      for (final link in const [
        'http://amzn.eu/d/abc',
        'javascript:alert(1)',
        'https://amazon.es@evil.example/',
        'https://tienda.example:8443/',
        'https://127.0.0.1/',
        'https://gifthuddle.app/i#example',
        'https://amzn.eu/d/a\u202eb',
        'amzn.eu',
        '',
      ]) {
        expect(await native.openUserLink(link), isFalse, reason: link);
      }
      expect(calls, isEmpty);
    });

    test('«open» sigue sin abrir tiendas: solo la web de la app', () async {
      expect(await native.open('https://amzn.eu/d/abc'), isFalse);
      expect(calls, isEmpty);
    });

    test('sin código nativo, no se abre', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await native.openUserLink('https://amzn.eu/d/abc'), isFalse);
    });
  });
}
