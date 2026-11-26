import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/platform/external_link.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/link_icon_button.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/web_board/presentation/board_gift_table.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../web_device/presentation/gate_test_support.dart';

/// Un navegador de mentira: apunta los enlaces de regalo que se le piden.
class _FakeOpener implements ExternalLinkOpener {
  _FakeOpener({this.works = true});

  final bool works;
  final List<String> userLinks = <String>[];

  @override
  Future<bool> open(String url) async => false;

  @override
  Future<bool> openUserLink(String url) async {
    userLinks.add(url);
    return works;
  }
}

Gift _gift(String id, String title, {String? url, String? store}) => Gift(
  id: id,
  recipientId: 'aritz',
  title: title,
  status: GiftStatus.idea,
  rawStatus: 'idea',
  url: url,
  store: store,
  surprise: false,
  year: 2026,
);

/// La muestra de siempre más dos regalos de Aritz con enlace y uno sin
/// tienda.
Future<void> _seed(
  WidgetTester tester,
  FakePhone phone, {
  String shopUrl = 'https://www.amzn.eu/d/abc',
}) async {
  await seedSample(tester, phone);
  await tester.runAsync(() async {
    final c = familyOf(phone);
    await c.upsertGift(_gift('gl1', 'Cometa de seda', url: shopUrl));
    await c.upsertGift(
      _gift('gl2', 'Cuerda de saltar', url: 'http://viejo.example/cuerda'),
    );
    await c.upsertGift(_gift('gl3', 'Peonza de madera'));
  });
}

Future<void> _mount(WidgetTester tester, FakePhone phone) async {
  await _seed(tester, phone);
  await pumpRegalos(tester, phone);
  await tester.tap(find.text('Aritz').first);
  await settle(tester);
}

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

final _editor = find.byType(GiftEditorScreen);

LinkIconButton _openButton(WidgetTester tester) =>
    tester.widget<LinkIconButton>(
      find.descendant(of: _editor, matching: find.byType(LinkIconButton)),
    );

Future<void> _openEditorOf(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await settle(tester);
  expect(_editor, findsOneWidget);
  await openMoreDetails(tester);
}

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

void main() {
  setUpAll(loadInter);

  group('lista del móvil', () {
    final opener = _FakeOpener();
    final failing = _FakeOpener(works: false);
    List<Override> overrides() => [
      externalLinkOpenerProvider.overrideWithValue(opener),
    ];

    setUp(() {
      opener.userLinks.clear();
      failing.userLinks.clear();
    });

    screenTest(
      'el enlace de un regalo se ve como el sitio, sin www., y se abre al '
      'pulsarlo sin abrir el editor',
      (tester, phone) async {
        await _mount(tester, phone);
        final link = find.descendant(
          of: find.byType(GiftRow),
          matching: find.text('amzn.eu'),
        );
        expect(link, findsOneWidget);
        await tester.tap(link);
        await settle(tester);
        expect(opener.userLinks, ['https://www.amzn.eu/d/abc']);
        expect(_editor, findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 2400),
      overrides: overrides(),
    );

    screenTest(
      'solo se enseña un enlace https que se pueda abrir',
      (tester, phone) async {
        await _mount(tester, phone);
        expect(find.textContaining('viejo.example'), findsNothing);
        expect(find.byType(GiftLinkLabel), findsOneWidget);
      },
      size: const Size(390, 2400),
      overrides: overrides(),
    );

    screenTest(
      'si no se puede abrir, copia el enlace y lo dice',
      (tester, phone) async {
        await _mount(tester, phone);
        await tester.tap(find.text('amzn.eu'));
        await settle(tester);
        expect(find.textContaining('Enlace copiado'), findsOneWidget);
      },
      size: const Size(390, 2400),
      overrides: [externalLinkOpenerProvider.overrideWithValue(failing)],
    );
  });

  group('editor del regalo', () {
    final opener = _FakeOpener();
    setUp(opener.userLinks.clear);

    screenTest(
      'el botón «Abrir» solo responde con un enlace https válido',
      (tester, phone) async {
        await _mount(tester, phone);
        await _openEditorOf(tester, 'Peonza de madera');
        // Sin enlace: apagado y sin verse.
        expect(_openButton(tester).onTap, isNull);
        expect(
          tester
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.byType(LinkIconButton),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity,
          0,
        );
        await tester.ensureVisible(_field('Enlace'));
        await tester.enterText(_field('Enlace'), 'amazon.es/dp/1');
        await tester.pump();
        expect(_openButton(tester).onTap, isNull);
        await tester.enterText(_field('Enlace'), 'http://amazon.es/dp/1');
        await tester.pump();
        expect(_openButton(tester).onTap, isNull);
        await tester.enterText(_field('Enlace'), 'javascript:alert(1)');
        await tester.pump();
        expect(_openButton(tester).onTap, isNull);
        await tester.enterText(_field('Enlace'), 'https://amazon.es/dp/1');
        await settle(tester);
        expect(_openButton(tester).onTap, isNotNull);
        expect(find.bySemanticsLabel('Abrir enlace'), findsOneWidget);
        expect(
          tester
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.byType(LinkIconButton),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity,
          1,
        );
        await tester.tap(find.byType(LinkIconButton));
        await settle(tester);
        expect(opener.userLinks, ['https://amazon.es/dp/1']);
        // Vuelve a apagarse al borrar el texto.
        await tester.enterText(_field('Enlace'), '');
        await tester.pump();
        expect(_openButton(tester).onTap, isNull);
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 2400),
      overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
    );

    screenTest(
      'un enlace con el botón apagado no abre nada al tocar donde estaba',
      (tester, phone) async {
        await _mount(tester, phone);
        await _openEditorOf(tester, 'Peonza de madera');
        await tester.ensureVisible(_field('Enlace'));
        await tester.enterText(_field('Enlace'), 'nada que abrir');
        await tester.pump();
        await tester.tap(find.byType(LinkIconButton), warnIfMissed: false);
        await settle(tester);
        expect(opener.userLinks, isEmpty);
      },
      size: const Size(390, 2400),
      overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
    );

    screenTest(
      'al pegar un enlace de una tienda conocida, la tienda vacía se rellena',
      (tester, phone) async {
        await _mount(tester, phone);
        await _openEditorOf(tester, 'Peonza de madera');
        await tester.ensureVisible(_field('Enlace'));
        expect(_text(tester, 'Tienda'), '');
        await tester.enterText(
          _field('Enlace'),
          'https://www.decathlon.es/es/p/bici',
        );
        await tester.pump();
        expect(_text(tester, 'Tienda'), 'Decathlon');
        // Otro enlace de otra tienda cambia lo que rellenó el enlace...
        await tester.enterText(_field('Enlace'), 'https://www.ikea.com/es/');
        await tester.pump();
        expect(_text(tester, 'Tienda'), 'IKEA');
        // ...y un sitio que no está en la tabla lo vacía.
        await tester.enterText(_field('Enlace'), 'https://tienda.example/a');
        await tester.pump();
        expect(_text(tester, 'Tienda'), '');
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 2400),
      overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
    );

    screenTest(
      'nunca pisa lo que escribió la persona en «Tienda»',
      (tester, phone) async {
        await _mount(tester, phone);
        await _openEditorOf(tester, 'Peonza de madera');
        await tester.ensureVisible(_field('Tienda'));
        await tester.enterText(_field('Tienda'), 'Mi tienda');
        await tester.enterText(_field('Enlace'), 'https://www.ikea.com/es/');
        await tester.pump();
        expect(_text(tester, 'Tienda'), 'Mi tienda');
        // Si la tienda la rellenó el enlace y la persona la cambia, ya es suya.
        await tester.enterText(_field('Tienda'), '');
        await tester.enterText(_field('Enlace'), 'https://www.zara.com/es/');
        await tester.pump();
        expect(_text(tester, 'Tienda'), '');
        await tester.enterText(_field('Enlace'), '');
        await tester.enterText(_field('Enlace'), 'https://www.fnac.es/a1');
        await tester.pump();
        expect(_text(tester, 'Tienda'), '');
      },
      size: const Size(390, 2400),
      overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
    );

    screenTest(
      'si la persona toca lo que rellenó el enlace, deja de seguirlo',
      (tester, phone) async {
        await _mount(tester, phone);
        await _openEditorOf(tester, 'Peonza de madera');
        await tester.ensureVisible(_field('Enlace'));
        await tester.enterText(_field('Enlace'), 'https://www.ikea.com/es/');
        await tester.pump();
        expect(_text(tester, 'Tienda'), 'IKEA');
        await tester.enterText(_field('Tienda'), 'IKEA Badalona');
        await tester.enterText(_field('Enlace'), 'https://www.zara.com/es/');
        await tester.pump();
        expect(_text(tester, 'Tienda'), 'IKEA Badalona');
      },
      size: const Size(390, 2400),
      overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
    );

    screenTest(
      'al abrir un regalo que ya tiene tienda, el enlace no la cambia',
      (tester, phone) async {
        await tester.runAsync(() async {});
        await _seed(tester, phone);
        await tester.runAsync(
          () => familyOf(phone).upsertGift(
            _gift('gl4', 'Libro de recetas', store: 'Librería', url: null),
          ),
        );
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Aritz').first);
        await settle(tester);
        await _openEditorOf(tester, 'Libro de recetas');
        await tester.ensureVisible(_field('Enlace'));
        await tester.enterText(_field('Enlace'), 'https://www.ikea.com/es/');
        await tester.pump();
        expect(_text(tester, 'Tienda'), 'Librería');
      },
      size: const Size(390, 2400),
      overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
    );
  });

  group('tabla de la web', () {
    final opener = _FakeOpener();
    const rawShopUrl = 'HTTPS://WWW.AMZN.EU/d/abc';
    const validatedShopUrl = 'https://www.amzn.eu/d/abc';
    setUp(opener.userLinks.clear);

    List<Override> web() => [
      webAppProvider.overrideWithValue(true),
      webGateActionsProvider.overrideWithValue(FakeGateActions()),
      webDeviceStateProvider.overrideWithValue(
        const WebDeviceState(
          status: WebSyncStatus.confirmed,
          hasRoots: true,
          setAsideChanges: 0,
          persistenceDenied: false,
        ),
      ),
      externalLinkOpenerProvider.overrideWithValue(opener),
    ];

    Future<void> mountWeb(WidgetTester tester, FakePhone phone) async {
      await _seed(tester, phone, shopUrl: rawShopUrl);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: phone.container,
          child: const RegalosApp(webSession: true),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Aritz').first);
      await settle(tester);
    }

    screenTest(
      'el icono de la columna «Enlace» se pulsa, abre el enlace y no el editor',
      (tester, phone) async {
        await mountWeb(tester, phone);
        final row = find.ancestor(
          of: find.text('Cometa de seda'),
          matching: find.byType(BoardGiftTableRow),
        );
        final button = find.descendant(
          of: row,
          matching: find.byType(LinkIconButton),
        );
        expect(button, findsOneWidget);
        // El dibujo es un cuadrado de 18 dentro de la columna de 40: no se
        // estira ni se recorta.
        final icon = find.descendant(
          of: find.descendant(of: button, matching: find.byType(StrokeIcon)),
          matching: find.byType(CustomPaint),
        );
        expect(tester.getSize(icon.first), const Size(18, 18));
        expect(tester.getSize(button).width, lessThanOrEqualTo(40));
        // El tooltip y el lector de pantalla muestran la URL validada.
        expect(
          find.descendant(of: row, matching: find.byTooltip(validatedShopUrl)),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Abrir enlace: $validatedShopUrl'),
          findsOneWidget,
        );
        await tester.tap(button);
        await settle(tester);
        expect(opener.userLinks, [rawShopUrl]);
        expect(_editor, findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 1600),
      overrides: web(),
    );

    screenTest(
      'con un texto que no es https, el icono no se puede pulsar',
      (tester, phone) async {
        await mountWeb(tester, phone);
        final row = find.ancestor(
          of: find.text('Cuerda de saltar'),
          matching: find.byType(BoardGiftTableRow),
        );
        expect(
          find.descendant(of: row, matching: find.byType(LinkIconButton)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.byTooltip('http://viejo.example/cuerda'),
          ),
          findsOneWidget,
        );
      },
      size: const Size(1920, 1600),
      overrides: web(),
    );
  });
}
