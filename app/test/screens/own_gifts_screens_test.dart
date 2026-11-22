// Las pantallas de la 1.0.6 que tocan lo que se ve de cada persona: Personas
// con «Solo regala», la ficha de la propia persona (bloque fijo que no cuenta
// regalos), «Pendiente» en la web y la pista del bloqueo en la
// tarjeta de Compartir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart' show SecretBlock;
import 'package:regalos/core/widgets/secret_block.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart'
    show syncLikelyBlockedProvider;
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fonts.dart';
import '../helpers/screens.dart';

class _OfflineSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.offline);
}

const _ownNote =
    'En este móvil no se ven los regalos para Aritz. Solo otra persona de la '
    'familia puede cambiarlo, desde su móvil.';

void main() {
  setUpAll(loadInter);

  screenTest(
    'quien solo regala dice «Solo regala» en vez de «0 regalos» (1.0.6)',
    (tester, phone) async {
      await seedSample(tester, phone);
      await tester.runAsync(
        () => familyOf(phone).upsertRecipient(
          const Recipient(
            id: 'leo',
            name: 'Leo',
            colorIndex: 3,
            archived: false,
            noGifts: true,
            inReparto: false,
          ),
        ),
      );
      await pumpRegalos(tester, phone);
      expect(find.textContaining('Solo regala'), findsOneWidget);
      // Su ficha tampoco cuenta regalos.
      await tapText(tester, 'Leo');
      expect(find.textContaining('Solo regala'), findsOneWidget);
      expect(find.text('0 regalos'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  group('la ficha de la propia persona (1.0.6)', () {
    final overrides = [
      ownHiddenPeopleProvider.overrideWithValue({'aritz'}),
      secretBlocksProvider.overrideWithValue(const [
        SecretBlock('aritz'),
        SecretBlock('nora'),
      ]),
    ];

    screenTest(
      'dice que en este móvil no se ven y no cuenta nada; la de otra persona '
      'sigue con su frase',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Aritz');
        expect(find.text(_ownNote), findsOneWidget);
        // Ni cifras ni filas de regalos: solo el bloque.
        expect(find.textContaining('Pijama'), findsNothing);
        expect(find.textContaining('regalos ·'), findsNothing);
        final own = tester.getSize(find.byType(SecretBlockCard)).height;
        expect(own, greaterThanOrEqualTo(SecretBlockCard.height));
        await tapLabel(tester, 'Volver a Personas');
        await tapText(tester, 'Nora');
        expect(find.text('Este móvil no los muestra.'), findsOneWidget);
        expect(find.text(_ownNote), findsNothing);
        expect(tester.getSize(find.byType(SecretBlockCard)).height, 88);
        expect(tester.takeException(), isNull);
      },
      overrides: overrides,
    );

    screenTest(
      'oscuro y con letra grande no desborda',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Aritz');
        expect(find.text(_ownNote), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: overrides,
      brightness: Brightness.dark,
      textScale: 2,
    );
  });

  screenTest(
    'la web marca «Pendiente» (primera etiqueta) en el regalo con cambios sin '
    'recoger, y el texto largo va en la ayuda y en la lectura',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Aritz');
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.byTooltip('Pendiente de tu móvil'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Pendiente de tu móvil')), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
    overrides: [
      webPendingSecretGiftIdsProvider.overrideWithValue(const {'g2'}),
    ],
  );

  screenTest(
    '«Pendiente» va antes que «Sorpresa» en la misma fila',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Aritz');
      final pending = tester.getTopLeft(find.text('Pendiente')).dx;
      final surprise = tester.getTopLeft(find.text('Sorpresa').first).dx;
      expect(pending, lessThan(surprise));
    },
    overrides: [
      // g4 (la bici) es una sorpresa.
      webPendingSecretGiftIdsProvider.overrideWithValue(const {'g4'}),
    ],
  );

  screenTest('sin cambios pendientes no hay marca', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');
    expect(find.text('Pendiente'), findsNothing);
  });

  group('la pista del bloqueo en Compartir', () {
    Future<void> openDevices(WidgetTester tester) async {
      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
      await tapText(tester, 'Móviles de la familia');
    }

    screenTest(
      'tras tres intentos sin ruta, la pista va bajo «Los cambios se '
      'enviarán luego»',
      (tester, phone) async {
        await seedSample(tester, phone);
        // Con otro móvil conectado la tarjeta habla del estado, no de «Solo
        // en este móvil».
        await tester.runAsync(() => familyOf(phone).markPaired());
        await pumpRegalos(tester, phone);
        await openDevices(tester);
        expect(find.text('No se puede conectar'), findsOneWidget);
        expect(find.text('Los cambios se enviarán luego.'), findsOneWidget);
        expect(
          find.textContaining('puede que tu operador esté bloqueando'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 1500),
      overrides: [
        syncControllerProvider.overrideWith(_OfflineSync.new),
        syncLikelyBlockedProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );

    screenTest(
      'sin bloqueo probable solo está la frase de siempre',
      (tester, phone) async {
        await seedSample(tester, phone);
        // Con otro móvil conectado la tarjeta habla del estado, no de «Solo
        // en este móvil».
        await tester.runAsync(() => familyOf(phone).markPaired());
        await pumpRegalos(tester, phone);
        await openDevices(tester);
        expect(find.text('Los cambios se enviarán luego.'), findsOneWidget);
        expect(find.textContaining('operador'), findsNothing);
      },
      size: const Size(390, 1500),
      overrides: [
        syncControllerProvider.overrideWith(_OfflineSync.new),
        syncLikelyBlockedProvider.overrideWith((ref) => Stream.value(false)),
      ],
    );
  });
}
