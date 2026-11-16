import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/document_exchange.dart';
import 'package:regalos/core/platform/link_source.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_file.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/sharing/application/incoming_share.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/features/sync/application/recovery_file_flow.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';
import 'package:share_plus/share_plus.dart';

import '../helpers/fake_recovery.dart';

/// ADR 0008, capa de aplicación: distribuidor por magia, NFC en la
/// plataforma, una derivación a la vez, guardar con relectura del destino y
/// comprobar un fichero.
Uint8List hex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

/// La plataforma sin plataforma: selectores y hoja de compartir simulados y
/// una NFC mínima para las letras de las pruebas.
class FakeExchange implements DocumentExchange {
  Future<void> Function(Uint8List)? receive;
  int clearedShares = 0;
  int normalized = 0;

  /// Mientras no se complete, la NFC de la plataforma no contesta.
  Completer<void>? holdNfc;

  /// Mientras no se complete, el selector de guardar no contesta.
  Completer<void>? holdSave;

  /// Si no es null, el selector de abrir contesta con su futuro.
  Completer<Uint8List?>? holdPick;

  /// Lo que devuelve el selector de abrir (null = cancelar).
  Uint8List? picked;
  Object? pickError;

  /// Lo que se escribió con el selector de guardar.
  final saved = <Uint8List>[];

  /// Lo que se relee del destino (por defecto, lo mismo que se escribió);
  /// null = la persona cancela.
  Uint8List? Function(Uint8List written) readBack = (w) => w;

  final shared = <Uint8List>[];

  static const _compose = {
    'ñ': 'ñ',
    'á': 'á',
    'é': 'é',
    'í': 'í',
    'ó': 'ó',
    'ú': 'ú',
  };

  @override
  Future<String> normalizeNfc(String text) async {
    normalized++;
    await holdNfc?.future;
    var out = text;
    _compose.forEach((nfd, nfc) => out = out.replaceAll(nfd, nfc));
    return out;
  }

  @override
  Future<Uint8List?> openWithPicker({required int maxBytes}) async {
    expect(maxBytes, kRecoveryFileMaxBytes);
    final hold = holdPick;
    if (hold != null) return hold.future;
    final error = pickError;
    if (error != null) throw error;
    return picked;
  }

  @override
  Future<Uint8List?> saveWithPicker(
    Uint8List bytes,
    String name, {
    required int maxReadBytes,
  }) async {
    expect(maxReadBytes, kRecoveryFileMaxBytes);
    saved.add(bytes);
    await holdSave?.future;
    return readBack(bytes);
  }

  @override
  Future<ShareResult> shareRecoveryFile(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) async {
    shared.add(bytes);
    return const ShareResult('', ShareResultStatus.success);
  }

  @override
  Future<void> clearRecoveryShares() async => clearedShares++;

  @override
  Future<void> startReceiving(Future<void> Function(Uint8List) receive) async =>
      this.receive = receive;

  @override
  void stopReceiving() => receive = null;

  @override
  Future<void> clearExports() async {}

  @override
  Future<XFile> exportBytes(Uint8List bytes, String name) =>
      throw UnimplementedError();

  @override
  Future<Uint8List?> pickBytes() => throw UnimplementedError();

  @override
  Future<ShareResult> shareBytes(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) => throw UnimplementedError();
}

class _NoLinks implements LinkSource {
  @override
  String? takeInitialLink() => null;
  @override
  Stream<String> get links => const Stream.empty();
}

class _FakeShareService extends ShareService {
  _FakeShareService(super.ref);
  final imported = <Uint8List>[];

  @override
  Future<ImportSummary> importEnvelopeBytes(Uint8List bytes) async {
    imported.add(bytes);
    throw const NoFamilyException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final vector = jsonDecode(
    File('../docs/adr/0008-vector-fichero.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final entropy = hex(vector['entropyHex'] as String);
  final openFile = hex((vector['open'] as Map)['fileHex'] as String);
  final protected = [
    for (final p in vector['protected'] as List) p as Map<String, Object?>,
  ];
  final ascii = protected.firstWhere((p) => p['name'] == 'ascii');
  final nfc = protected.firstWhere((p) => p['name'] == 'nfc');
  final asciiFile = hex(ascii['fileHex'] as String);
  final nfcFile = hex(nfc['fileHex'] as String);
  String text(Map<String, Object?> p, String field) =>
      utf8.decode(hex(p[field] as String));

  late FakeExchange exchange;
  late FakeRecovery recovery;
  late bool hasFamily;
  late bool holdDerive;
  final derivations =
      <({Completer<Uint8List> done, String password, List<int> salt})>[];

  /// Completes pending derivation [i] with the real Argon2 key.
  Future<void> completeDerivation(int i) async {
    final d = derivations[i];
    d.done.complete(await deriveRecoveryFileKey(d.password, d.salt));
  }

  late ProviderContainer container;

  setUp(() {
    exchange = FakeExchange();
    recovery = FakeRecovery();
    hasFamily = false;
    holdDerive = false;
    derivations.clear();
    container = ProviderContainer(
      overrides: [
        documentExchangeProvider.overrideWithValue(exchange),
        recoveryApplicationProvider.overrideWith(() => recovery),
        recoveryFileHasFamilyProvider.overrideWithValue(() async => hasFamily),
        recoveryFileDeriverProvider.overrideWithValue((password, salt) {
          if (!holdDerive) return deriveRecoveryFileKey(password, salt);
          final done = Completer<Uint8List>();
          derivations.add((done: done, password: password, salt: salt));
          return done.future;
        }),
        linkSourceProvider.overrideWithValue(_NoLinks()),
        shareServiceProvider.overrideWith(_FakeShareService.new),
      ],
    );
    addTearDown(container.dispose);
  });

  _FakeShareService share() =>
      container.read(shareServiceProvider) as _FakeShareService;
  RecoveryFileController flow() =>
      container.read(recoveryFileProvider.notifier);
  RecoveryFileState state() => container.read(recoveryFileProvider);

  Matcher fileFails(RecoveryFileFailure f) => throwsA(
    isA<RecoveryFileException>().having((e) => e.failure, 'failure', f),
  );
  Matcher flowFails(RecoveryFileFlowError f) => throwsA(
    isA<RecoveryFileFlowException>().having((e) => e.error, 'error', f),
  );

  Future<void> startIncoming() async {
    container.read(incomingShareProvider);
    await pumpEventQueue();
    expect(exchange.receive, isNotNull);
  }

  group('distribuidor por magia', () {
    test('GHK goes to the recovery flow, never to the envelope importer, '
        'without Argon2 nor the network', () async {
      await startIncoming();
      expect(exchange.clearedShares, 1, reason: 'sweep at startup');
      await exchange.receive!(asciiFile);
      expect(container.read(incomingShareProvider), isNull);
      expect(share().imported, isEmpty);
      final selection = state().selection!;
      expect(selection.source, RecoveryFileSource.received);
      expect(selection.variant, RecoveryFileVariant.protected);
      expect(selection.needsPassword, isTrue);
      expect(selection.hasFamily, isFalse);
      expect(state().activity, RecoveryFileActivity.idle);
      expect(exchange.normalized, 0);
      expect(recovery.calls, isEmpty);
    });

    test('anything else still goes to the envelope importer', () async {
      await startIncoming();
      final envelope = Uint8List.fromList(utf8.encode('RG not a recovery'));
      await exchange.receive!(envelope);
      expect(share().imported.single, envelope);
      expect(container.read(incomingShareProvider), isA<IncomingFailed>());
      expect(state().selection, isNull);
    });

    test('a newer or broken GHK is reported, not imported', () async {
      await startIncoming();
      final newer = Uint8List.fromList(asciiFile)..[3] = 2;
      await exchange.receive!(newer);
      expect(state().selection!.failure, RecoveryFileFailure.newerVersion);
      expect(state().selection!.needsPassword, isFalse);
      expect(share().imported, isEmpty);
      flow().clear();
      await exchange.receive!(Uint8List.fromList(asciiFile.sublist(0, 40)));
      expect(state().selection!.failure, RecoveryFileFailure.notRecoveryFile);
    });

    test('with a family it only says the file is for an empty phone', () async {
      hasFamily = true;
      await startIncoming();
      await exchange.receive!(openFile);
      expect(state().selection!.hasFamily, isTrue);
      await expectLater(
        flow().open(),
        flowFails(RecoveryFileFlowError.hasFamily),
      );
      expect(recovery.calls, isEmpty);
    });

    test('a second file waits until the person chooses', () async {
      await startIncoming();
      await exchange.receive!(asciiFile);
      await exchange.receive!(openFile);
      expect(state().selection!.variant, RecoveryFileVariant.protected);
      expect(state().waiting!.variant, RecoveryFileVariant.open);
      flow().dismissWaiting();
      expect(state().waiting, isNull);
      await exchange.receive!(openFile);
      flow().acceptWaiting();
      expect(state().waiting, isNull);
      expect(state().selection!.variant, RecoveryFileVariant.open);
    });
  });

  group('restaurar desde un fichero', () {
    test('open variant: confirmation, then the words flow with E', () async {
      await flow().receive(openFile);
      await flow().open();
      expect(state().selection!.opened, isTrue);
      expect(recovery.calls, isEmpty, reason: 'nothing before confirming');
      await flow().restore();
      expect(recovery.calls, ['file']);
      expect(recovery.lastCode!.entropy, entropy);
      expect(state().selection, isNull);
    });

    test('NFD password is normalized to NFC and opens the NFC file', () async {
      final nfd = text(nfc, 'passwordNfdUtf8Hex');
      expect(nfd, isNot(text(nfc, 'passwordUtf8Hex')));
      await flow().receive(nfcFile);
      await flow().open(password: nfd);
      expect(exchange.normalized, 1);
      await flow().restore(replaceExisting: true);
      expect(recovery.calls, ['file+replace']);
      expect(recovery.lastCode!.entropy, entropy);
    });

    test('wrong password, missing password and a failed restore', () async {
      await flow().receive(asciiFile);
      await expectLater(
        flow().open(),
        flowFails(RecoveryFileFlowError.passwordRequired),
      );
      await expectLater(
        flow().open(password: text(ascii, 'passwordUtf8Hex').toUpperCase()),
        fileFails(RecoveryFileFailure.damagedOrWrongPassword),
      );
      expect(state().selection!.opened, isFalse);
      await expectLater(
        flow().restore(),
        flowFails(RecoveryFileFlowError.noFile),
      );
      await flow().open(password: text(ascii, 'passwordUtf8Hex'));
      recovery.restoreError = const RecoveryApplicationException(
        'different_family',
      );
      await expectLater(
        flow().restore(),
        throwsA(isA<RecoveryApplicationException>()),
      );
      // The opened code is kept: retrying does not derive again.
      expect(state().selection!.opened, isTrue);
      await flow().restore(replaceExisting: true);
      expect(recovery.calls, ['file', 'file+replace']);
    });

    test('«Recuperar con fichero» picks through the system picker', () async {
      exchange.picked = null;
      expect(await flow().pickForRestore(), isNull);
      exchange.picked = Uint8List.fromList(utf8.encode('RG envelope'));
      await expectLater(
        flow().pickForRestore(),
        fileFails(RecoveryFileFailure.notRecoveryFile),
      );
      exchange.pickError = const DocumentPickerException(
        DocumentPickerFailure.tooLarge,
      );
      await expectLater(
        flow().pickForRestore(),
        fileFails(RecoveryFileFailure.notRecoveryFile),
      );
      exchange.pickError = null;
      exchange.picked = openFile;
      final selection = await flow().pickForRestore();
      expect(selection!.source, RecoveryFileSource.picked);
      expect(state().activity, RecoveryFileActivity.idle);
      await flow().open();
      await flow().restore();
      expect(recovery.lastCode!.entropy, entropy);
      hasFamily = true;
      await expectLater(
        flow().pickForRestore(),
        flowFails(RecoveryFileFlowError.hasFamily),
      );
    });
  });

  group('una operación y una derivación a la vez', () {
    test('the next derivation waits for the cancelled one: never two at '
        'once', () async {
      holdDerive = true;
      final password = text(ascii, 'passwordUtf8Hex');
      await flow().receive(asciiFile);
      final first = flow().open(password: password);
      await pumpEventQueue();
      expect(derivations, hasLength(1));
      expect(state().activity, RecoveryFileActivity.deriving);
      await expectLater(
        flow().open(password: 'x'),
        flowFails(RecoveryFileFlowError.busy),
      );
      flow().cancel();
      expect(state().activity, RecoveryFileActivity.idle);
      final second = flow().open(password: password);
      await pumpEventQueue();
      // Still one: the second waits for the cancelled isolate to finish.
      expect(derivations, hasLength(1));
      expect(state().activity, RecoveryFileActivity.deriving);
      await completeDerivation(0);
      await expectLater(first, flowFails(RecoveryFileFlowError.cancelled));
      await pumpEventQueue();
      expect(derivations, hasLength(2));
      expect(state().selection!.opened, isFalse);
      await completeDerivation(1);
      await second;
      expect(state().selection!.opened, isTrue);
      expect(state().activity, RecoveryFileActivity.idle);
    });

    test('cancel while NFC is pending never starts Argon2', () async {
      holdDerive = true;
      final activities = <RecoveryFileActivity>[];
      final sub = container.listen(
        recoveryFileProvider,
        (_, next) => activities.add(next.activity),
      );
      addTearDown(sub.close);
      await flow().receive(asciiFile);
      exchange.holdNfc = Completer<void>();
      final opening = flow().open(password: text(ascii, 'passwordUtf8Hex'));
      await pumpEventQueue();
      flow().cancel();
      exchange.holdNfc!.complete();
      await expectLater(opening, flowFails(RecoveryFileFlowError.cancelled));
      expect(derivations, isEmpty);
      expect(activities, isNot(contains(RecoveryFileActivity.deriving)));
      expect(state().selection!.opened, isFalse);
    });

    test('cancel while sealing waits on NFC never derives', () async {
      holdDerive = true;
      final display = await sampleRecoveryDisplay();
      exchange.holdNfc = Completer<void>();
      final password = text(ascii, 'passwordUtf8Hex');
      final preparing = flow().prepare(
        display,
        password: password,
        repeat: password,
      );
      await pumpEventQueue();
      flow().cancel();
      exchange.holdNfc!.complete();
      await expectLater(preparing, flowFails(RecoveryFileFlowError.cancelled));
      expect(derivations, isEmpty);
    });

    test('an old picker never replaces a file accepted later', () async {
      exchange.holdPick = Completer<Uint8List?>();
      final picking = flow().pickForRestore();
      await pumpEventQueue();
      expect(state().activity, RecoveryFileActivity.picking);
      await flow().receive(openFile);
      expect(state().waiting!.variant, RecoveryFileVariant.open);
      flow().acceptWaiting();
      expect(state().selection!.source, RecoveryFileSource.received);
      exchange.holdPick!.complete(asciiFile);
      await expectLater(picking, flowFails(RecoveryFileFlowError.cancelled));
      expect(state().selection!.source, RecoveryFileSource.received);
      expect(state().selection!.variant, RecoveryFileVariant.open);
      expect(state().activity, RecoveryFileActivity.idle);
      // And the flow is free again.
      await flow().open();
      expect(state().selection!.opened, isTrue);
    });

    test('a wrong password failing after cancel is `cancelled`, not «wrong '
        'password», and leaves a newer file alone', () async {
      holdDerive = true;
      await flow().receive(asciiFile);
      final opening = flow().open(password: 'otra contraseña cualquiera');
      await pumpEventQueue();
      expect(derivations, hasLength(1));
      flow().cancel();
      await flow().receive(openFile);
      flow().acceptWaiting();
      await completeDerivation(0); // wrong key: the GCM fails late
      await expectLater(opening, flowFails(RecoveryFileFlowError.cancelled));
      expect(state().selection!.variant, RecoveryFileVariant.open);
      expect(state().selection!.opened, isFalse);
      expect(state().activity, RecoveryFileActivity.idle);
    });

    test('a derivation that errors after cancel is `cancelled`', () async {
      holdDerive = true;
      await flow().receive(asciiFile);
      final opening = flow().open(password: text(ascii, 'passwordUtf8Hex'));
      await pumpEventQueue();
      flow().cancel();
      derivations.single.done.completeError(StateError('isolate died'));
      await expectLater(opening, flowFails(RecoveryFileFlowError.cancelled));
    });

    test('late picker and save errors after cancel are `cancelled`', () async {
      exchange.holdPick = Completer<Uint8List?>();
      final picking = flow().pickForCheck();
      await pumpEventQueue();
      flow().cancel();
      exchange.holdPick!.completeError(
        const DocumentPickerException(DocumentPickerFailure.unreadable),
      );
      await expectLater(picking, flowFails(RecoveryFileFlowError.cancelled));
      final prepared = await flow().prepare(await sampleRecoveryDisplay());
      final hold = Completer<void>();
      exchange.readBack = (w) => Uint8List.fromList(w)..[w.length - 1] ^= 1;
      exchange.holdSave = hold;
      final saving = flow().save(prepared, fileName: 'a.gifthuddle');
      await pumpEventQueue();
      flow().cancel();
      hold.complete();
      await expectLater(saving, flowFails(RecoveryFileFlowError.cancelled));
      expect(recovery.calls, isEmpty);
    });

    test('a restore failing after clear is `cancelled`', () async {
      await flow().receive(openFile);
      await flow().open();
      recovery.holdRestore = Completer<void>();
      recovery.restoreError = const RecoveryApplicationException('network');
      final restoring = flow().restore();
      await pumpEventQueue();
      flow().clear();
      recovery.holdRestore!.complete();
      await expectLater(restoring, flowFails(RecoveryFileFlowError.cancelled));
      expect(state().selection, isNull);
    });

    test('a family that appeared meanwhile stops the restore', () async {
      await flow().receive(openFile);
      await flow().open();
      hasFamily = true;
      await expectLater(
        flow().restore(),
        flowFails(RecoveryFileFlowError.hasFamily),
      );
      expect(recovery.calls, isEmpty);
    });

    test('a picker result after clear is discarded', () async {
      exchange.holdPick = Completer<Uint8List?>();
      final picking = flow().pickForRestore();
      await pumpEventQueue();
      flow().clear();
      exchange.holdPick!.complete(openFile);
      await expectLater(picking, flowFails(RecoveryFileFlowError.cancelled));
      expect(state().selection, isNull);
    });
  });

  group('guardar y compartir durante la entrega', () {
    late RecoveryCodeDisplay display;
    late RecoveryCode code;
    setUp(() async {
      display = await sampleRecoveryDisplay();
      code = RecoveryCode.fromQrText(display.qrText);
    });

    test('open file saved, read back with the same E, confirms', () async {
      final prepared = await flow().prepare(display);
      expect(prepared.variant, RecoveryFileVariant.open);
      final result = await flow().save(
        prepared,
        fileName: recoveryCodeFileName(
          'gift-huddle-recuperacion',
          DateTime(2026, 11, 16, 9, 5),
        ),
      );
      expect(result, RecoveryFileSaveResult.confirmed);
      expect(recovery.calls, ['confirm']);
      final file = parseRecoveryFile(exchange.saved.single);
      expect(openOpenRecoveryFile(file).entropy, code.entropy);
    });

    test('file name', () {
      expect(
        recoveryCodeFileName(
          'gift-huddle-recuperacion',
          DateTime(2026, 1, 2, 3, 4),
        ),
        'gift-huddle-recuperacion-20260102-0304.gifthuddle',
      );
    });

    test(
      'cancel, damaged destination and another file never confirm',
      () async {
        final prepared = await flow().prepare(display);
        exchange.readBack = (_) => null;
        expect(
          await flow().save(prepared, fileName: 'a.gifthuddle'),
          RecoveryFileSaveResult.cancelled,
        );
        exchange.readBack = (w) => Uint8List.fromList(w)..[w.length - 1] ^= 1;
        await expectLater(
          flow().save(prepared, fileName: 'a.gifthuddle'),
          flowFails(RecoveryFileFlowError.verificationFailed),
        );
        exchange.readBack = (_) => openFile; // a valid file of another code
        await expectLater(
          flow().save(prepared, fileName: 'a.gifthuddle'),
          flowFails(RecoveryFileFlowError.verificationFailed),
        );
        exchange.readBack = (w) => Uint8List.fromList([...w, 0]);
        await expectLater(
          flow().save(prepared, fileName: 'a.gifthuddle'),
          flowFails(RecoveryFileFlowError.verificationFailed),
        );
        expect(recovery.calls, isEmpty);
        expect(state().activity, RecoveryFileActivity.idle);
      },
    );

    test('protected: NFC, both entries, rules, then verified save', () async {
      await expectLater(
        flow().prepare(display, password: 'corta', repeat: 'corta'),
        throwsA(
          isA<RecoveryPasswordException>().having(
            (e) => e.problem,
            'problem',
            RecoveryPasswordProblem.tooShort,
          ),
        ),
      );
      final nfcPassword = text(nfc, 'passwordUtf8Hex');
      final nfdPassword = text(nfc, 'passwordNfdUtf8Hex');
      await expectLater(
        flow().prepare(display, password: nfcPassword, repeat: 'otra'),
        throwsA(
          isA<RecoveryPasswordException>().having(
            (e) => e.problem,
            'problem',
            RecoveryPasswordProblem.mismatch,
          ),
        ),
      );
      expect(
        await flow().checkNewPassword(nfcPassword, repeat: nfdPassword),
        isNull,
      );
      expect(
        await flow().checkNewPassword('qwertyuiopasdfgh'),
        RecoveryPasswordProblem.keyboardSequence,
      );
      // Typed in NFD on one entry and NFC on the other: equal after NFC.
      final prepared = await flow().prepare(
        display,
        password: nfdPassword,
        repeat: nfcPassword,
      );
      expect(prepared.variant, RecoveryFileVariant.protected);
      expect(
        await flow().save(prepared, fileName: 'a.gifthuddle'),
        RecoveryFileSaveResult.confirmed,
      );
      final file = parseRecoveryFile(exchange.saved.single);
      // The NFC spelling opens it: the platform normalized before deriving.
      final opened = await openProtectedRecoveryFile(file, nfcPassword);
      expect(opened.entropy, code.entropy);
    });

    test('sharing does not confirm', () async {
      final prepared = await flow().prepare(display);
      final result = await flow().share(
        prepared,
        fileName: 'a.gifthuddle',
        text: 'x',
      );
      expect(result.status, ShareResultStatus.success);
      expect(exchange.shared.single, isNotEmpty);
      expect(recovery.calls, isEmpty);
    });
  });

  group('comprobar un fichero', () {
    test('a protected file confirms possession with its E', () async {
      exchange.picked = asciiFile;
      final check = await flow().pickForCheck();
      expect(check!.needsPassword, isTrue);
      await expectLater(
        flow().confirmCheck(check),
        flowFails(RecoveryFileFlowError.passwordRequired),
      );
      await flow().confirmCheck(
        check,
        password: text(ascii, 'passwordUtf8Hex'),
      );
      expect(recovery.calls, ['possession']);
      expect(recovery.lastCode!.entropy, entropy);
    });

    test('cancel, not a file and a file of another code', () async {
      exchange.picked = null;
      expect(await flow().pickForCheck(), isNull);
      exchange.picked = Uint8List.fromList([0x47, 0x48, 0x52, 1, 0, 0]);
      await expectLater(
        flow().pickForCheck(),
        fileFails(RecoveryFileFailure.notRecoveryFile),
      );
      exchange.picked = openFile;
      final check = await flow().pickForCheck();
      recovery.possessionError = const RecoveryApplicationException(
        'not_current_code',
      );
      await expectLater(
        flow().confirmCheck(check!),
        throwsA(
          isA<RecoveryApplicationException>().having(
            (e) => e.code,
            'code',
            'not_current_code',
          ),
        ),
      );
    });
  });
}
