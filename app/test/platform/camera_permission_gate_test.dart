// El permiso de cámara del lector de QR (1.0.2): nunca se queda esperando para
// siempre. Sin respuesta en 4 s mira el permiso sin preguntar; al volver a la
// app lo mira otra vez; distingue denegado, denegado para siempre e
// interrumpido; «Reintentar» vuelve a preguntar; y una comprobación que
// termina tarde nunca pisa una respuesta más nueva. Tiempo falso y completers.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/camera_permission.dart';
import 'package:regalos/core/platform/camera_permission_gate.dart';

void main() {
  late List<Completer<CameraPermissionOutcome>> answers;
  late List<Completer<bool>> checks;
  late int settings;
  CameraPermissionGate gate() => CameraPermissionGate(
    request: () {
      final c = Completer<CameraPermissionOutcome>();
      answers.add(c);
      return c.future;
    },
    check: () {
      final c = Completer<bool>();
      checks.add(c);
      return c.future;
    },
    openSettings: () async {
      settings++;
      return true;
    },
  );
  setUp(() {
    answers = [];
    checks = [];
    settings = 0;
  });

  test('granted, denied and permanently denied answers; the answer cancels '
      'the no-answer check', () {
    for (final (answer, state) in [
      (CameraPermissionOutcome.granted, CameraPermissionState.granted),
      (CameraPermissionOutcome.denied, CameraPermissionState.denied),
      (
        CameraPermissionOutcome.permanentlyDenied,
        CameraPermissionState.permanentlyDenied,
      ),
    ]) {
      fakeAsync((async) {
        final g = gate();
        unawaited(g.start());
        expect(g.state, CameraPermissionState.waiting);
        answers.last.complete(answer);
        async.flushMicrotasks();
        expect(g.state, state);
        async.elapse(const Duration(seconds: 10));
        expect(checks, isEmpty);
        expect(async.pendingTimers, isEmpty);
        g.dispose();
      });
    }
  });

  test('no answer in 4 s: it checks without asking; granted goes on', () {
    fakeAsync((async) {
      final g = gate();
      unawaited(g.start());
      async.elapse(const Duration(seconds: 3));
      expect(checks, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(checks, hasLength(1));
      checks.last.complete(true);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      expect(answers, hasLength(1), reason: 'it did not ask again');
      g.dispose();
    });
  });

  test('no answer and no permission: a retryable failure; a late answer '
      'still counts', () {
    fakeAsync((async) {
      final g = gate();
      final issues = <CameraIssue?>[];
      g.addListener(() => issues.add(g.issue));
      unawaited(g.start());
      async.elapse(const Duration(seconds: 4));
      checks.last.complete(false);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.failed);
      answers.last.complete(CameraPermissionOutcome.granted);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      expect(issues, [CameraIssue.failed, null]);
      g.dispose();
    });
  });

  test('item 3: the answer arrives while the no-answer check is running; the '
      'late «not granted» check does not overwrite it', () {
    fakeAsync((async) {
      final g = gate();
      unawaited(g.start());
      async.elapse(const Duration(seconds: 4));
      expect(checks, hasLength(1));
      answers.last.complete(CameraPermissionOutcome.granted);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      checks.last.complete(false);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      g.dispose();
    });
  });

  test('item 3: a «denied» answer while a resume check runs is not undone by '
      'it, in either order', () {
    fakeAsync((async) {
      // Order A: the answer first, then the old check.
      final g = gate();
      unawaited(g.start());
      unawaited(g.resumed());
      answers.last.complete(CameraPermissionOutcome.denied);
      async.flushMicrotasks();
      checks.last.complete(true);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.denied);
      g.dispose();

      // Order B: the check first (no permission yet), then the answer.
      final h = gate();
      unawaited(h.start());
      unawaited(h.resumed());
      checks.last.complete(false);
      async.flushMicrotasks();
      expect(h.state, CameraPermissionState.waiting);
      answers.last.complete(CameraPermissionOutcome.granted);
      async.flushMicrotasks();
      expect(h.state, CameraPermissionState.granted);
      h.dispose();
    });
  });

  test('item 3: a check from an older attempt is ignored after a retry', () {
    fakeAsync((async) {
      final g = gate();
      unawaited(g.start());
      answers.last.complete(CameraPermissionOutcome.denied);
      async.flushMicrotasks();
      unawaited(g.resumed()); // check of attempt 1, still running
      unawaited(g.retry()); // attempt 2
      checks.first.complete(true);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.waiting);
      answers.last.complete(CameraPermissionOutcome.denied);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.denied);
      g.dispose();
    });
  });

  test('round 2: of two overlapping checks the newest wins, whichever '
      'finishes first', () {
    fakeAsync((async) {
      // Order A: the old check (false) finishes first.
      final g = gate();
      unawaited(g.start());
      async.elapse(const Duration(seconds: 4)); // check 1 (timeout)
      unawaited(g.resumed()); // check 2
      expect(checks, hasLength(2));
      checks[0].complete(false);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.waiting, reason: 'old check');
      checks[1].complete(true);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      g.dispose();

      // Order B: the new check (true) first, then the old one (false).
      checks.clear();
      final h = gate();
      unawaited(h.start());
      async.elapse(const Duration(seconds: 4));
      unawaited(h.resumed());
      checks[1].complete(true);
      async.flushMicrotasks();
      expect(h.state, CameraPermissionState.granted);
      checks[0].complete(false);
      async.flushMicrotasks();
      expect(h.state, CameraPermissionState.granted);
      h.dispose();
    });
  });

  test('round 3: after «cancelled», a resume check that supersedes the '
      'pending one inherits its fallback: both false ends in failed, in '
      'either order', () {
    for (final oldFirst in [true, false]) {
      fakeAsync((async) {
        checks.clear();
        final g = gate();
        unawaited(g.start());
        answers.last.complete(CameraPermissionOutcome.cancelled);
        async.flushMicrotasks(); // check 1 (otherwise: failed)
        unawaited(g.resumed()); // check 2 (no fallback of its own)
        expect(checks, hasLength(2));
        final order = oldFirst ? [0, 1] : [1, 0];
        for (final i in order) {
          checks[i].complete(false);
          async.flushMicrotasks();
        }
        expect(
          g.state,
          CameraPermissionState.failed,
          reason: 'oldFirst=$oldFirst',
        );
        expect(g.issue, CameraIssue.failed);
        // Retryable.
        unawaited(g.retry());
        expect(g.state, CameraPermissionState.waiting);
        g.dispose();
      });
    }
  });

  test('round 3: the same after a no-answer timeout', () {
    fakeAsync((async) {
      final g = gate();
      unawaited(g.start());
      async.elapse(const Duration(seconds: 4)); // check 1 (otherwise: failed)
      unawaited(g.resumed()); // check 2
      checks[1].complete(false);
      async.flushMicrotasks();
      checks[0].complete(false);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.failed);
      g.dispose();
    });
  });

  test('item 4: a retry while the first request is still unanswered asks '
      'again (the platform answers both); the newest answer decides', () {
    fakeAsync((async) {
      final g = gate();
      unawaited(g.start());
      async.elapse(const Duration(seconds: 4));
      checks.last.complete(false);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.failed);
      unawaited(g.retry());
      expect(answers, hasLength(2));
      // The native side keeps one dialog and answers every waiter with it.
      answers.first.complete(CameraPermissionOutcome.granted);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.waiting, reason: 'old attempt');
      answers.last.complete(CameraPermissionOutcome.granted);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      g.dispose();
    });
  });

  test(
    'cancelled (empty results) checks the permission and otherwise fails',
    () {
      fakeAsync((async) {
        final g = gate();
        unawaited(g.start());
        answers.last.complete(CameraPermissionOutcome.cancelled);
        async.flushMicrotasks();
        checks.last.complete(false);
        async.flushMicrotasks();
        expect(g.state, CameraPermissionState.failed);
        g.dispose();
      });
    },
  );

  test('a request that throws is not a black screen either', () {
    fakeAsync((async) {
      final g = CameraPermissionGate(
        request: () async => throw StateError('no channel'),
        check: () async => false,
      );
      unawaited(g.start());
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.failed);
      g.dispose();
    });
  });

  test('permanently denied: settings, then resume grants without asking', () {
    fakeAsync((async) {
      final g = gate();
      unawaited(g.start());
      answers.last.complete(CameraPermissionOutcome.permanentlyDenied);
      async.flushMicrotasks();
      expect(g.issue, CameraIssue.permanentlyDenied);
      unawaited(g.openSettings());
      async.flushMicrotasks();
      expect(settings, 1);
      unawaited(g.resumed());
      checks.last.complete(true);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      expect(answers, hasLength(1));
      g.dispose();
    });
  });

  test('retry asks again', () {
    fakeAsync((async) {
      final g = gate();
      unawaited(g.start());
      answers.last.complete(CameraPermissionOutcome.denied);
      async.flushMicrotasks();
      unawaited(g.retry());
      expect(g.state, CameraPermissionState.waiting);
      expect(answers, hasLength(2));
      answers.last.complete(CameraPermissionOutcome.granted);
      async.flushMicrotasks();
      expect(g.state, CameraPermissionState.granted);
      g.dispose();
    });
  });

  test('after dispose a late answer changes nothing and no timer is left', () {
    fakeAsync((async) {
      final g = gate();
      var changes = 0;
      g.addListener(() => changes++);
      unawaited(g.start());
      g.dispose();
      answers.last.complete(CameraPermissionOutcome.granted);
      async.elapse(const Duration(seconds: 10));
      expect(changes, 0);
      expect(checks, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('the native outcome text', () {
    for (final o in CameraPermissionOutcome.values) {
      expect(parseCameraPermissionOutcome(o.name), o);
    }
    expect(
      parseCameraPermissionOutcome(null),
      CameraPermissionOutcome.cancelled,
    );
  });
}
