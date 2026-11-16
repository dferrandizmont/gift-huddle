import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app_info.dart';
import 'package:regalos/core/platform/external_link.dart';
import 'package:regalos/core/platform/external_link_native.dart';

/// Revisión de seguridad: el abridor nativo solo abre la web de la app. Un
/// enlace de cualquier otro sitio no llega al código nativo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('solo la web actual está permitida', () {
    expect(kExternalLinkHosts, {Uri.parse(kWebsiteOrigin).host});
  });

  test('abre la política de privacidad en los tres idiomas', () async {
    for (final language in ['es', 'ca', 'en']) {
      expect(await native.open(privacyPolicyUrl(language).toString()), isTrue);
    }
    expect(calls.map((c) => c.method), everyElement('openUrl'));
    expect(calls.map((c) => c.arguments), [
      'https://gifthuddle.app/privacy/',
      'https://gifthuddle.app/ca/privacy/',
      'https://gifthuddle.app/en/privacy/',
    ]);
  });

  test('no abre ningún otro sitio, aunque sea https', () async {
    const rejected = [
      'https://example.com/',
      'https://ko-fi.com/danielmfdev',
      'https://gifthuddle.retired.example/privacy/',
      'https://GiftHuddle.retired.example/privacy/',
      // Otro sitio que lleva el nombre de la web delante, detrás o como
      // usuario.
      'https://gifthuddle.app.example.com/privacy/',
      'https://xgifthuddle.app/privacy/',
      'https://gifthuddle.retired.example.example.com/privacy/',
      'https://usuario@gifthuddle.retired.example/privacy/',
      'https://gifthuddle.retired.example:443/privacy/',
      'https://gifthuddle.retired.example:8443/privacy/',
      'http://gifthuddle.retired.example/privacy/',
      'https://example.com/gifthuddle.app/',
      'https://gifthuddle.app@example.com/privacy/',
      'https://usuario@gifthuddle.app/privacy/',
      'https://retired.example/',
      'https://otra.retired.example/privacy/',
      'https://gifthuddle.app:443/privacy/',
      'https://gifthuddle.app:8443/privacy/',
      // Otros esquemas hacia la misma web o hacia el móvil.
      'http://gifthuddle.app/privacy/',
      'intent://gifthuddle.app/#Intent;scheme=https;end',
      'tel:112',
      'file:///etc/hosts',
      'javascript:alert(1)',
    ];
    for (final link in rejected) {
      final url = link;
      expect(NativeExternalLinkOpener.allows(url), isFalse, reason: link);
      expect(await native.open(url), isFalse, reason: link);
    }
    expect(calls, isEmpty, reason: 'nada llega al código nativo');
  });

  group('correo de soporte', () {
    test(
      'es el de la web',
      () {
        final toml = File('../web/site.toml').readAsStringSync();
        expect(toml, contains('contact_email = "$kSupportEmail"'));
        expect(kSupportMailto.toString(), 'mailto:gifthuddle@gifthuddle.app');
      },
      skip: !File('../web/site.toml').existsSync()
          ? 'needs ../web (not in this repository)'
          : false,
    );

    test('abre solo el mailto de soporte, sin nada más', () async {
      expect(
        NativeExternalLinkOpener.allows(kSupportMailto.toString()),
        isTrue,
      );
      expect(await native.open(kSupportMailto.toString()), isTrue);
      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments, 'mailto:gifthuddle@gifthuddle.app');
    });

    test('rechaza otros destinatarios, copias, asunto y cuerpo', () async {
      const rejected = [
        'mailto:otro@example.com',
        'mailto:gifthuddle@gifthuddle.app,otro@example.com',
        'mailto:gifthuddle@gifthuddle.app?cc=otro@example.com',
        'mailto:gifthuddle@gifthuddle.app?subject=hola',
        'mailto:gifthuddle@gifthuddle.app?body=mi%20lista',
        'mailto:gifthuddle@gifthuddle.app#x',
        'mailto:gifthuddle@gifthuddle.app.example.com',
        'mailto:?to=otro@example.com',
        'sms:gifthuddle@gifthuddle.app',
      ];
      for (final link in rejected) {
        final url = link;
        expect(isSupportMailto(Uri.parse(url)), isFalse, reason: link);
        expect(NativeExternalLinkOpener.allows(url), isFalse, reason: link);
        expect(await native.open(url), isFalse, reason: link);
      }
      expect(calls, isEmpty, reason: 'nada llega al código nativo');
    });
  });

  test('las mayúsculas del nombre de la web no importan', () async {
    expect(await native.open('https://GiftHuddle.App/privacy/'), isTrue);
    expect(calls, hasLength(1));
  });
}
