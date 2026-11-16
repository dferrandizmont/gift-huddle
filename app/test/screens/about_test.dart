import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app_info.dart';
import 'package:regalos/core/platform/external_link.dart';
import 'package:regalos/core/platform/external_link_native.dart';

import '../helpers/screens.dart';

/// Un navegador de mentira: apunta lo que se le pide abrir.
class _FakeOpener implements ExternalLinkOpener {
  _FakeOpener({this.works = true});

  final bool works;
  final List<Uri> opened = <Uri>[];

  @override
  Future<bool> open(String url) async {
    opened.add(Uri.parse(url));
    return works;
  }
}

/// «Acerca de» enlaza a la política de privacidad publicada en la web y la
/// abre en el navegador del sistema.
void main() {
  Future<void> openAbout(
    WidgetTester tester, {
    String settings = 'Ajustes',
  }) async {
    await tester.tap(find.text(settings).last);
    await settle(tester);
    final row = find.textContaining('Gift Huddle').last;
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await settle(tester);
  }

  test('la política está en la web de la app, en el idioma de la app', () {
    expect(
      privacyPolicyUrl('es').toString(),
      'https://gifthuddle.app/privacy/',
    );
    expect(
      privacyPolicyUrl('ca').toString(),
      'https://gifthuddle.app/ca/privacy/',
    );
    expect(
      privacyPolicyUrl('en').toString(),
      'https://gifthuddle.app/en/privacy/',
    );
    // Un idioma que la web no tiene abre la versión en castellano.
    expect(
      privacyPolicyUrl('fr').toString(),
      'https://gifthuddle.app/privacy/',
    );
  });

  final opener = _FakeOpener();
  screenTest(
    'la fila «Política de privacidad» abre la política en el navegador',
    (tester, phone) async {
      opener.opened.clear();
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openAbout(tester);
      expect(find.text('Política de privacidad'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Política de privacidad. Se abre en el navegador.',
        ),
        findsOneWidget,
      );
      expect(opener.opened, isEmpty, reason: 'nada se abre sin tocar');

      await tapText(tester, 'Política de privacidad');
      expect(opener.opened, [Uri.parse('https://gifthuddle.app/privacy/')]);
      // Sigue en Acerca de y sin avisos: lo que se abre es el navegador.
      expect(find.text('Política de privacidad'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
    overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
    size: const Size(390, 1500),
  );

  final support = _FakeOpener();
  screenTest(
    'la fila «Ayuda y soporte» abre el correo de soporte',
    (tester, phone) async {
      support.opened.clear();
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openAbout(tester);
      expect(find.text('Ayuda y soporte'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Ayuda y soporte. Escríbenos desde tu app de correo.',
        ),
        findsOneWidget,
      );
      expect(support.opened, isEmpty, reason: 'nada se abre sin tocar');
      await tapText(tester, 'Ayuda y soporte');
      expect(support.opened, [Uri.parse('mailto:gifthuddle@gifthuddle.app')]);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
    overrides: [externalLinkOpenerProvider.overrideWithValue(support)],
    size: const Size(390, 1500),
  );

  final noMail = _FakeOpener(works: false);
  screenTest(
    'sin app de correo, copia la dirección y lo dice',
    (tester, phone) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openAbout(tester);
      await tapText(tester, 'Ayuda y soporte');
      expect(copied, 'gifthuddle@gifthuddle.app');
      expect(
        find.text(
          'No se ha podido abrir el correo. Dirección copiada: gifthuddle@gifthuddle.app',
        ),
        findsOneWidget,
      );
    },
    overrides: [externalLinkOpenerProvider.overrideWithValue(noMail)],
    size: const Size(390, 1500),
  );

  final englishSupport = _FakeOpener();
  screenTest(
    'con la app en inglés la fila de soporte sale en inglés',
    (tester, phone) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'GB')];
      tester.platformDispatcher.localeTestValue = const Locale('en', 'GB');
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openAbout(tester, settings: 'Settings');
      expect(find.text('Help and support'), findsOneWidget);
      await tapText(tester, 'Help and support');
      expect(englishSupport.opened, [kSupportMailto]);
    },
    overrides: [externalLinkOpenerProvider.overrideWithValue(englishSupport)],
    size: const Size(390, 1500),
  );

  final catalan = _FakeOpener();
  screenTest(
    'con la app en catalán abre la política en catalán',
    (tester, phone) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ca', 'ES')];
      tester.platformDispatcher.localeTestValue = const Locale('ca', 'ES');
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openAbout(tester, settings: 'Ajustos');
      await tapText(tester, 'Política de privadesa');
      expect(catalan.opened, [Uri.parse('https://gifthuddle.app/ca/privacy/')]);
    },
    overrides: [externalLinkOpenerProvider.overrideWithValue(catalan)],
    size: const Size(390, 1500),
  );

  final broken = _FakeOpener(works: false);
  screenTest(
    'si no hay navegador, copia el enlace y lo dice',
    (tester, phone) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openAbout(tester);
      await tapText(tester, 'Política de privacidad');
      expect(copied, 'https://gifthuddle.app/privacy/');
      expect(
        find.text('No se ha podido abrir el navegador. Enlace copiado.'),
        findsOneWidget,
      );
    },
    overrides: [externalLinkOpenerProvider.overrideWithValue(broken)],
    size: const Size(390, 1500),
  );

  group('el abridor nativo', () {
    const channel = MethodChannel('com.dferrandizmont.regalos/incoming');
    const native = NativeExternalLinkOpener();

    testWidgets('pide al código nativo que abra el enlace https', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      expect(await native.open(privacyPolicyUrl('es').toString()), isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments, 'https://gifthuddle.app/privacy/');
    });

    testWidgets('no abre nada que no sea https', (tester) async {
      var called = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        called = true;
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      expect(await native.open('http://example.com/'), isFalse);
      expect(await native.open('tel:112'), isFalse);
      expect(await native.open('file:///etc/hosts'), isFalse);
      expect(called, isFalse);
    });

    testWidgets('sin código nativo devuelve false en vez de fallar', (
      tester,
    ) async {
      // La respuesta «no hay nadie» llega del motor: fuera del reloj falso.
      final opened = await tester.runAsync(
        () => native.open(privacyPolicyUrl('es').toString()),
      );
      expect(opened, isFalse);
    });

    testWidgets('si el código nativo falla devuelve false', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'no_browser'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      expect(await native.open(privacyPolicyUrl('es').toString()), isFalse);
    });

    testWidgets('si el código nativo no puede abrirlo devuelve false', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => false,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      expect(await native.open(privacyPolicyUrl('es').toString()), isFalse);
    });
  });
}
