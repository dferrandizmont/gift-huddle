// Fichero de recuperación (ADR 0008), capa de aplicación sin pantallas:
// guardar o compartir el código de la entrega en curso, comprobar un fichero
// y restaurar desde uno. El formato está en core/sync/recovery_file.dart.
//
// Reglas que se cumplen aquí:
// * Recibir un fichero (arranque en frío, intent con la app abierta o el
//   selector) solo lo valida por encima: nunca deriva ni va a la red.
// * Con familia, un fichero recibido solo avisa de que sirve para un móvil
//   vacío; no hace nada más.
// * Una sola operación y una sola derivación de Argon2 a la vez; cancelar la
//   descarta sin efectos (si el isolate sigue, la siguiente espera a que
//   acabe para no gastar dos veces 64 MiB).
// * Las contraseñas pasan a NFC en la plataforma antes de validar, comparar
//   o derivar.
// * Guardar con el selector solo confirma el código si la relectura del
//   destino da la misma E; compartir no confirma nada.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show ShareResult;

import '../../../core/platform/document_exchange.dart';
import '../../../core/sync/device_keys.dart' show constantTimeEquals;
import '../../../core/sync/exchange_file_names.dart';
import '../../../core/sync/recovery.dart';
import '../../../core/sync/recovery_file.dart';
import '../../family/data/family_store.dart';
import 'recovery_providers.dart';

export '../../../core/platform/document_exchange.dart'
    show DocumentPickerException, DocumentPickerFailure;
export '../../../core/sync/recovery_file.dart'
    show
        RecoveryFileException,
        RecoveryFileFailure,
        RecoveryFileVariant,
        RecoveryPasswordProblem,
        kRecoveryPasswordMaxRunes,
        kRecoveryPasswordMinRunes;

/// `<stem>-AAAAMMDD-HHMM.gifthuddle`, con [stem] traducido por ARB (p. ej.
/// `gift-huddle-recuperacion`).
String recoveryCodeFileName(String stem, DateTime t) {
  String p(int n, int w) => n.toString().padLeft(w, '0');
  return '$stem-${p(t.year, 4)}${p(t.month, 2)}${p(t.day, 2)}'
      '-${p(t.hour, 2)}${p(t.minute, 2)}$kExchangeFileExtension';
}

/// Errores propios del flujo (los del formato son [RecoveryFileException],
/// los del selector [DocumentPickerException] y los de restaurar o confirmar
/// `RecoveryApplicationException`).
enum RecoveryFileFlowError {
  /// Ya hay una operación de fichero de recuperación en marcha.
  busy,

  /// Se canceló la derivación: no pasó nada.
  cancelled,

  /// El fichero va protegido y no se dio la contraseña.
  passwordRequired,

  /// No hay fichero elegido o recibido (o todavía no se abrió).
  noFile,

  /// Este móvil ya tiene familia: el fichero sirve para un móvil vacío.
  hasFamily,

  /// Lo que se releyó del destino no da la misma E: no se confirma nada.
  verificationFailed,
}

/// Un error del flujo. Nunca lleva secretos.
class RecoveryFileFlowException implements Exception {
  /// Crea el error.
  const RecoveryFileFlowException(this.error);

  /// El motivo.
  final RecoveryFileFlowError error;

  @override
  String toString() => 'RecoveryFileFlowException(${error.name})';
}

/// La contraseña nueva no vale. La interfaz traduce [problem].
class RecoveryPasswordException implements Exception {
  /// Crea el error.
  const RecoveryPasswordException(this.problem);

  /// El motivo.
  final RecoveryPasswordProblem problem;

  @override
  String toString() => 'RecoveryPasswordException(${problem.name})';
}

/// Qué está haciendo el flujo ahora (para deshabilitar botones y enseñar el
/// progreso indeterminado de la derivación).
enum RecoveryFileActivity {
  /// Nada.
  idle,

  /// El selector del sistema está abierto.
  picking,

  /// Argon2 en marcha (unos segundos).
  deriving,
}

/// De dónde vino el fichero elegido.
enum RecoveryFileSource {
  /// Abierto con la app desde Archivos, otra app o la hoja de compartir.
  received,

  /// Elegido con «Recuperar con fichero».
  picked,
}

/// El fichero de recuperación recibido o elegido para restaurar. Solo
/// metadatos: los bytes y la E se quedan dentro del controlador.
class RecoveryFileSelection {
  /// Crea la descripción.
  const RecoveryFileSelection({
    required this.source,
    required this.hasFamily,
    this.variant,
    this.failure,
    this.opened = false,
  });

  /// De dónde vino.
  final RecoveryFileSource source;

  /// Su variante, o null si no se puede usar ([failure]).
  final RecoveryFileVariant? variant;

  /// Si no se puede usar: no es un fichero válido o es de una versión nueva.
  final RecoveryFileFailure? failure;

  /// Este móvil ya tiene familia: solo se avisa de que sirve para un móvil
  /// vacío.
  final bool hasFamily;

  /// Ya se abrió (E obtenida): listo para [RecoveryFileController.restore].
  final bool opened;

  /// Falta pedir la contraseña.
  bool get needsPassword =>
      variant == RecoveryFileVariant.protected && !opened && failure == null;

  RecoveryFileSelection _openedCopy() => RecoveryFileSelection(
    source: source,
    hasFamily: hasFamily,
    variant: variant,
    failure: failure,
    opened: true,
  );
}

/// Estado del flujo del fichero de recuperación.
class RecoveryFileState {
  /// Crea el estado.
  const RecoveryFileState({
    this.activity = RecoveryFileActivity.idle,
    this.selection,
    this.waiting,
  });

  /// Qué está haciendo.
  final RecoveryFileActivity activity;

  /// El fichero recibido o elegido (aviso «fichero de recuperación
  /// recibido»), o null.
  final RecoveryFileSelection? selection;

  /// Llegó otro mientras se procesaba [selection]: la interfaz pregunta antes
  /// de cambiarlo ([RecoveryFileController.acceptWaiting] o
  /// [RecoveryFileController.dismissWaiting]).
  final RecoveryFileSelection? waiting;

  RecoveryFileState _copy({
    RecoveryFileActivity? activity,
    RecoveryFileSelection? selection,
    RecoveryFileSelection? waiting,
    bool clearSelection = false,
    bool clearWaiting = false,
  }) => RecoveryFileState(
    activity: activity ?? this.activity,
    selection: clearSelection ? null : selection ?? this.selection,
    waiting: clearWaiting ? null : waiting ?? this.waiting,
  );
}

/// Un fichero sellado con el código de la entrega en curso, listo para
/// guardar y compartir. Vive lo que la pantalla de las palabras; nunca entra
/// en el estado de un provider.
class PreparedRecoveryFile {
  PreparedRecoveryFile._(this._display, this._code, this._sealed);

  final RecoveryCodeDisplay _display;
  final RecoveryCode _code;
  final SealedRecoveryFile _sealed;

  /// Su variante.
  RecoveryFileVariant get variant => _sealed.variant;

  @override
  String toString() => 'PreparedRecoveryFile(${variant.name})';
}

/// Resultado de guardar con el selector.
enum RecoveryFileSaveResult {
  /// La persona cerró el selector: no se guardó nada.
  cancelled,

  /// Guardado, releído del destino con la misma E y código comprobado.
  confirmed,
}

/// Un fichero elegido con «Comprobar un fichero».
class RecoveryFileCheck {
  RecoveryFileCheck._(this._file);

  final RecoveryFile _file;

  /// Su variante.
  RecoveryFileVariant get variant => _file.variant;

  /// Si hay que pedir la contraseña.
  bool get needsPassword => _file.needsPassword;

  @override
  String toString() => 'RecoveryFileCheck(${variant.name})';
}

/// Si este móvil ya tiene una familia. Lectura local sin efectos: no carga
/// `familyControllerProvider` (que puede reanudar una restauración, con red y
/// Argon2). Falla en cerrado: si no se puede leer, cuenta como que la hay y
/// no se restaura nada. Se puede sustituir en pruebas.
final recoveryFileHasFamilyProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    try {
      return await ref.read(familyStoreProvider).hasFamily();
    } on Object {
      return true;
    }
  },
);

/// Cómo se deriva la clave del fichero (Argon2 en otro isolate). Solo se
/// sustituye en pruebas, para controlar cuándo termina cada derivación.
final recoveryFileDeriverProvider = Provider<RecoveryFileKeyDeriver>(
  (ref) => deriveRecoveryFileKey,
);

/// El flujo del fichero de recuperación.
///
/// Cada operación toma un número antes de su primer `await`; [cancel],
/// [clear] y [acceptWaiting] lo invalidan, y tras cada espera (NFC, selector,
/// derivación) se comprueba: un resultado viejo nunca cambia nada.
class RecoveryFileController extends Notifier<RecoveryFileState> {
  RecoveryFile? _selected;
  RecoveryFile? _waiting;
  RecoveryCode? _opened;
  int _op = 0;
  bool _running = false;
  Future<void>? _derivation;

  @override
  RecoveryFileState build() => const RecoveryFileState();

  DocumentExchange get _exchange => ref.read(documentExchangeProvider);

  RecoveryFileKeyDeriver get _deriver => ref.read(recoveryFileDeriverProvider);

  // ------------------------------------------------------------ recibir

  /// Un fichero GHK que llegó de fuera (lo llama el distribuidor de
  /// `IncomingShareController`). Solo lo valida por encima: ni Argon2 ni red.
  /// Si ya hay uno o hay una operación en marcha, el nuevo queda en
  /// [RecoveryFileState.waiting].
  Future<void> receive(Uint8List bytes) async {
    RecoveryFile? file;
    RecoveryFileFailure? failure;
    try {
      file = parseRecoveryFile(bytes);
    } on RecoveryFileException catch (e) {
      failure = e.failure;
    }
    final hasFamily = await ref.read(recoveryFileHasFamilyProvider)();
    if (!ref.mounted) return;
    final selection = RecoveryFileSelection(
      source: RecoveryFileSource.received,
      hasFamily: hasFamily,
      variant: file?.variant,
      failure: failure,
    );
    if (state.selection != null || _running) {
      _waiting = file;
      state = state._copy(waiting: selection);
      return;
    }
    _invalidate();
    _select(file, selection);
  }

  /// Cambia al fichero que esperaba (cancela lo que estuviera en marcha:
  /// NFC, selector o derivación).
  void acceptWaiting() {
    final waiting = state.waiting;
    if (waiting == null) return;
    final file = _waiting;
    _waiting = null;
    _invalidate();
    state = state._copy(clearWaiting: true);
    _select(file, waiting);
  }

  /// Descarta el fichero que esperaba y sigue con el de ahora.
  void dismissWaiting() {
    _waiting = null;
    state = state._copy(clearWaiting: true);
  }

  /// La interfaz terminó con el fichero elegido o recibido (lo descarta, con
  /// la E si se abrió, y cancela lo que estuviera en marcha).
  void clear() {
    _invalidate();
    _dropSelection();
  }

  void _dropSelection() {
    _selected = null;
    _opened = null;
    state = state._copy(clearSelection: true);
  }

  void _select(RecoveryFile? file, RecoveryFileSelection selection) {
    _selected = file;
    _opened = null;
    state = state._copy(selection: selection);
  }

  // ----------------------------------------------------------- restaurar

  /// «Recuperar con fichero»: abre el selector del sistema (≤ 512 bytes). Null
  /// si la persona cancela. Lanza [RecoveryFileException] si no vale (también
  /// si pasa del tope) y [RecoveryFileFlowException] (`hasFamily`, `busy`,
  /// `cancelled` si mientras tanto se aceptó otro fichero o se canceló).
  Future<RecoveryFileSelection?> pickForRestore() async {
    final op = _begin();
    try {
      final hasFamily = await ref.read(recoveryFileHasFamilyProvider)();
      _check(op);
      if (hasFamily) {
        throw const RecoveryFileFlowException(RecoveryFileFlowError.hasFamily);
      }
      final bytes = await _pick(op);
      if (bytes == null) return null;
      final file = _parsePicked(bytes);
      final selection = RecoveryFileSelection(
        source: RecoveryFileSource.picked,
        hasFamily: false,
        variant: file.variant,
      );
      _waiting = null;
      state = state._copy(clearWaiting: true);
      _select(file, selection);
      return selection;
    } catch (_) {
      // Un error tardío de una operación ya cancelada o sustituida no se
      // enseña ni cambia nada: es `cancelled`.
      _stale(op);
      rethrow;
    } finally {
      _end(op);
    }
  }

  /// Abre el fichero elegido o recibido: la variante abierta al momento; la
  /// protegida deriva con [password] (pasa a NFC en la plataforma). No
  /// restaura: deja [RecoveryFileSelection.opened] para que la interfaz pida
  /// la confirmación. Lanza [RecoveryFileException]
  /// (`damagedOrWrongPassword`) o [RecoveryFileFlowException].
  Future<void> open({String? password}) async {
    final op = _begin();
    try {
      final file = _selected;
      final selection = state.selection;
      if (file == null || selection == null) {
        throw const RecoveryFileFlowException(RecoveryFileFlowError.noFile);
      }
      if (selection.hasFamily) {
        throw const RecoveryFileFlowException(RecoveryFileFlowError.hasFamily);
      }
      await _requireNoFamily(op);
      final RecoveryCode code;
      if (file.variant == RecoveryFileVariant.open) {
        code = openOpenRecoveryFile(file);
      } else {
        if (password == null) {
          throw const RecoveryFileFlowException(
            RecoveryFileFlowError.passwordRequired,
          );
        }
        final nfc = await _exchange.normalizeNfc(password);
        _check(op);
        final derive = _deriver;
        code = await _derive(
          op,
          () => openProtectedRecoveryFile(file, nfc, derive: derive),
        );
      }
      if (!identical(_selected, file)) {
        throw const RecoveryFileFlowException(RecoveryFileFlowError.cancelled);
      }
      _opened = code;
      state = state._copy(selection: selection._openedCopy());
    } catch (_) {
      // Un error tardío de una operación ya cancelada o sustituida no se
      // enseña ni cambia nada: es `cancelled`.
      _stale(op);
      rethrow;
    } finally {
      _end(op);
    }
  }

  /// Restaura con la E del fichero abierto: el mismo flujo que con las
  /// palabras (`RecoveryApplication.restoreCode`). Si falla, la E se conserva
  /// para reintentar (p. ej. con [replaceExisting]) sin volver a derivar.
  Future<void> restore({bool replaceExisting = false}) async {
    final op = _begin();
    try {
      final code = _opened;
      final selection = state.selection;
      if (code == null || selection == null || !selection.opened) {
        throw const RecoveryFileFlowException(RecoveryFileFlowError.noFile);
      }
      if (selection.hasFamily) {
        throw const RecoveryFileFlowException(RecoveryFileFlowError.hasFamily);
      }
      // La familia puede haber llegado mientras se pedía la confirmación.
      await _requireNoFamily(op);
      await ref
          .read(recoveryApplicationProvider.notifier)
          .restoreCode(code, replaceExisting: replaceExisting);
      if (ref.mounted && identical(_opened, code)) _dropSelection();
    } catch (_) {
      // Un error tardío de una operación ya cancelada o sustituida no se
      // enseña ni cambia nada: es `cancelled`.
      _stale(op);
      rethrow;
    } finally {
      _end(op);
    }
  }

  // ------------------------------------------------------ entregar código

  /// Comprueba una contraseña nueva mientras se escribe (las dos entradas;
  /// [repeat] null = aún no se escribió la segunda). Null si vale.
  Future<RecoveryPasswordProblem?> checkNewPassword(
    String password, {
    String? repeat,
  }) async {
    final first = await _exchange.normalizeNfc(password);
    if (repeat == null) return checkRecoveryPassword(first);
    return checkNewRecoveryPassword(
      first,
      await _exchange.normalizeNfc(repeat),
    );
  }

  /// Sella el fichero con el código que la pantalla recibió de
  /// `takeCreatedCode`/`createCode`/`rotateCode` ([display]); nunca se relee
  /// E del almacén. Sin [password], la variante abierta (por defecto); con
  /// ella, la protegida (Argon2, unos segundos) tras validarla con [repeat].
  /// Sal y nonce nuevos en cada llamada. Lanza [RecoveryPasswordException] o
  /// [RecoveryFileFlowException] (`busy`, `cancelled`).
  Future<PreparedRecoveryFile> prepare(
    RecoveryCodeDisplay display, {
    String? password,
    String? repeat,
  }) async {
    final op = _begin();
    try {
      final code = RecoveryCode.fromQrText(display.qrText);
      if (password == null) {
        return PreparedRecoveryFile._(
          display,
          code,
          sealOpenRecoveryFile(code),
        );
      }
      final first = await _exchange.normalizeNfc(password);
      _check(op);
      final second = await _exchange.normalizeNfc(repeat ?? '');
      _check(op);
      final problem = checkNewRecoveryPassword(first, second);
      if (problem != null) throw RecoveryPasswordException(problem);
      final derive = _deriver;
      final sealed = await _derive(
        op,
        () => sealProtectedRecoveryFile(code, first, derive: derive),
      );
      return PreparedRecoveryFile._(display, code, sealed);
    } catch (_) {
      // Un error tardío de una operación ya cancelada o sustituida no se
      // enseña ni cambia nada: es `cancelled`.
      _stale(op);
      rethrow;
    } finally {
      _end(op);
    }
  }

  /// Guarda [file] con el selector del sistema, relee el destino y, si da la
  /// misma E, comprueba el código (`confirmCreatedCode`, que revalida bajo el
  /// candado que siga siendo el código y la persona vigentes). Lanza
  /// [RecoveryFileFlowException] (`verificationFailed`, `busy`, `cancelled`),
  /// [DocumentPickerException] o `RecoveryApplicationException`
  /// (`person_changed`, `operation_pending`…).
  Future<RecoveryFileSaveResult> save(
    PreparedRecoveryFile file, {
    required String fileName,
  }) async {
    final op = _begin();
    try {
      final Uint8List? readBack;
      state = state._copy(activity: RecoveryFileActivity.picking);
      try {
        readBack = await _exchange.saveWithPicker(
          file._sealed.bytes,
          fileName,
          maxReadBytes: kRecoveryFileMaxBytes,
        );
      } on DocumentPickerException catch (e) {
        if (e.failure == DocumentPickerFailure.tooLarge) {
          throw const RecoveryFileFlowException(
            RecoveryFileFlowError.verificationFailed,
          );
        }
        rethrow;
      }
      _check(op);
      _activity(op, RecoveryFileActivity.idle);
      if (readBack == null) return RecoveryFileSaveResult.cancelled;
      final RecoveryCode reopened;
      try {
        reopened = await file._sealed.reopen(readBack);
      } on RecoveryFileException {
        throw const RecoveryFileFlowException(
          RecoveryFileFlowError.verificationFailed,
        );
      }
      _check(op);
      if (!constantTimeEquals(reopened.entropy, file._code.entropy)) {
        throw const RecoveryFileFlowException(
          RecoveryFileFlowError.verificationFailed,
        );
      }
      await ref
          .read(recoveryApplicationProvider.notifier)
          .confirmCreatedCode(file._display);
      return RecoveryFileSaveResult.confirmed;
    } catch (_) {
      // Un error tardío de una operación ya cancelada o sustituida no se
      // enseña ni cambia nada: es `cancelled`.
      _stale(op);
      rethrow;
    } finally {
      _end(op);
    }
  }

  /// Comparte [file] con la hoja de compartir. No comprueba el código. El
  /// temporal se borra al volver tras un margen, al arrancar y en «Borrar
  /// todo».
  Future<ShareResult> share(
    PreparedRecoveryFile file, {
    required String fileName,
    required String text,
    Rect? origin,
  }) => _exchange.shareRecoveryFile(
    file._sealed.bytes,
    fileName,
    text: text,
    origin: origin,
  );

  // ------------------------------------------------------------ comprobar

  /// «Comprobar un fichero»: elige uno con el selector. Null si se cancela.
  /// Lanza [RecoveryFileException] si no vale.
  Future<RecoveryFileCheck?> pickForCheck() async {
    final op = _begin();
    try {
      final bytes = await _pick(op);
      return bytes == null ? null : RecoveryFileCheck._(_parsePicked(bytes));
    } catch (_) {
      // Un error tardío de una operación ya cancelada o sustituida no se
      // enseña ni cambia nada: es `cancelled`.
      _stale(op);
      rethrow;
    } finally {
      _end(op);
    }
  }

  /// Abre [check] (con [password] si va protegido) y, si da la E vigente,
  /// comprueba el código (`confirmPossession`). No exporta nada. Lanza
  /// [RecoveryFileException], [RecoveryFileFlowException] o
  /// `RecoveryApplicationException` (`not_current_code` si es de otro código,
  /// `person_changed` si cambió «Yo»).
  Future<void> confirmCheck(RecoveryFileCheck check, {String? password}) async {
    final op = _begin();
    try {
      final file = check._file;
      final RecoveryCode code;
      if (file.variant == RecoveryFileVariant.open) {
        code = openOpenRecoveryFile(file);
      } else {
        if (password == null) {
          throw const RecoveryFileFlowException(
            RecoveryFileFlowError.passwordRequired,
          );
        }
        final nfc = await _exchange.normalizeNfc(password);
        _check(op);
        final derive = _deriver;
        code = await _derive(
          op,
          () => openProtectedRecoveryFile(file, nfc, derive: derive),
        );
      }
      await ref
          .read(recoveryApplicationProvider.notifier)
          .confirmPossession(code);
    } catch (_) {
      // Un error tardío de una operación ya cancelada o sustituida no se
      // enseña ni cambia nada: es `cancelled`.
      _stale(op);
      rethrow;
    } finally {
      _end(op);
    }
  }

  // ------------------------------------------------- operación y derivación

  /// Cancela la operación en curso (NFC, selector o derivación): su resultado
  /// se descarta sin efectos.
  void cancel() => _invalidate();

  int _begin() {
    if (_running) {
      throw const RecoveryFileFlowException(RecoveryFileFlowError.busy);
    }
    _running = true;
    return ++_op;
  }

  Future<void> _requireNoFamily(int op) async {
    final hasFamily = await ref.read(recoveryFileHasFamilyProvider)();
    _check(op);
    if (hasFamily) {
      throw const RecoveryFileFlowException(RecoveryFileFlowError.hasFamily);
    }
  }

  /// En el camino de error: si la operación ya no es la vigente, `cancelled`.
  void _stale(int op) {
    if (op != _op || !ref.mounted) {
      throw const RecoveryFileFlowException(RecoveryFileFlowError.cancelled);
    }
  }

  void _check(int op) {
    if (op != _op || !ref.mounted) {
      throw const RecoveryFileFlowException(RecoveryFileFlowError.cancelled);
    }
  }

  void _end(int op) {
    if (op != _op) return;
    _running = false;
    _activity(op, RecoveryFileActivity.idle);
  }

  void _invalidate() {
    _op++;
    _running = false;
    if (ref.mounted) state = state._copy(activity: RecoveryFileActivity.idle);
  }

  void _activity(int op, RecoveryFileActivity activity) {
    if (op == _op && ref.mounted) state = state._copy(activity: activity);
  }

  /// Nunca dos derivaciones a la vez: una cancelada sigue en su isolate y la
  /// siguiente espera a que acabe.
  Future<T> _derive<T>(int op, Future<T> Function() task) async {
    _activity(op, RecoveryFileActivity.deriving);
    final previous = _derivation;
    if (previous != null) await previous;
    _check(op);
    final running = task();
    _derivation = running.then<void>((_) {}, onError: (Object _) {});
    final value = await running;
    _check(op);
    return value;
  }

  Future<Uint8List?> _pick(int op) async {
    _activity(op, RecoveryFileActivity.picking);
    final Uint8List? bytes;
    try {
      bytes = await _exchange.openWithPicker(maxBytes: kRecoveryFileMaxBytes);
    } on DocumentPickerException catch (e) {
      _check(op);
      if (e.failure == DocumentPickerFailure.tooLarge) {
        throw const RecoveryFileException(RecoveryFileFailure.notRecoveryFile);
      }
      rethrow;
    }
    _check(op);
    _activity(op, RecoveryFileActivity.idle);
    return bytes;
  }

  RecoveryFile _parsePicked(Uint8List bytes) {
    if (!isRecoveryFile(bytes)) {
      throw const RecoveryFileException(RecoveryFileFailure.notRecoveryFile);
    }
    return parseRecoveryFile(bytes);
  }
}

/// El flujo del fichero de recuperación (estado: [RecoveryFileState]).
final recoveryFileProvider =
    NotifierProvider<RecoveryFileController, RecoveryFileState>(
      RecoveryFileController.new,
    );
