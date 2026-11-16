import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart' show routerProvider;

import '../../../core/motion/haptics.dart';
import '../../../core/motion/shake.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/sync/recovery.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../settings/presentation/verify_owner.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/self_recipient_provider.dart';
import '../../family/data/recovery_wordlist_loader.dart';
import '../application/recovery_hold.dart';
import '../../sync/application/recovery_file_flow.dart';
import '../../sync/application/recovery_providers.dart';
import 'recovery_file_parts.dart';
import 'recovery_file_problem.dart';
import 'recovery_parts.dart';
import 'recovery_problem.dart';
import 'recovery_scan_screen.dart';

enum _Stage {
  entry,
  progress,
  error,
  done,

  /// Con fichero (ADR 0008): elegir, contraseña y confirmación.
  filePick,
  filePassword,
  fileConfirm,
}

/// «Tengo un código de recuperación»: se escriben o se pegan las 24 palabras
/// (con autocompletado de la lista inglesa), o se escanea el QR; luego se ve
/// el progreso real por fases y, al terminar, a quién pertenece el móvil.
///
/// Cada palabra y la suma de control se comprueban aquí antes de enviar nada.
/// Nada de lo escrito se guarda: al enviar, los campos se vacían.
///
/// Con [fileMode] («Recuperar con fichero», ADR 0008) el principio es otro:
/// elegir el fichero de recuperación (o el que llegó desde Archivos), su
/// contraseña con el progreso de la derivación y una confirmación. Desde ahí
/// el seguimiento, los errores y el final son los mismos que con las palabras.
class RecoveryRestoreScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const RecoveryRestoreScreen({
    super.key,
    this.embedded = false,
    this.fileMode = false,
  });

  /// Si se recupera con un fichero en vez de con las palabras.
  final bool fileMode;

  /// Si va dentro de la pantalla de «lista traspasada», fuera del router de la
  /// app: volver cierra su propio navegador y no usa rutas.
  final bool embedded;

  @override
  ConsumerState<RecoveryRestoreScreen> createState() =>
      _RecoveryRestoreScreenState();
}

class _RecoveryRestoreScreenState extends ConsumerState<RecoveryRestoreScreen> {
  static const int _count = kRecoveryWordCount;

  final List<TextEditingController> _controllers = [
    for (var i = 0; i < _count; i++) TextEditingController(),
  ];
  final List<FocusNode> _nodes = [for (var i = 0; i < _count; i++) FocusNode()];
  RecoveryWordlist? _wordlist;
  _Stage _stage = _Stage.entry;
  RecoveryProblem? _problem;

  // ---- Fichero (ADR 0008)
  late final RecoveryFileController _file;
  final TextEditingController _filePassword = TextEditingController();
  final GlobalKey<ShakeXState> _fileShake = GlobalKey<ShakeXState>();
  RecoveryFileProblem? _fileProblem;
  bool _filePicking = false;
  bool _fileOpening = false;

  /// Cambia con cada fichero adoptado o soltado: una apertura vieja que acaba
  /// tarde no toca nada (y la del fichero nuevo espera a que acabe).
  int _fileSerial = 0;

  /// El `_fileSerial` del fichero abierto que espera a que acabe la apertura
  /// anterior; si el fichero cambia otra vez, ya no vale.
  int? _reopenSerial;
  late final RecoveryFileRestoring _restoring;
  RecoveryFileScreenOpen? _screens;
  bool _fileReceived = false;

  bool _running = false;
  bool _checksumFailed = false;

  /// Cómo repetir la última petición (con las mismas palabras o el mismo QR);
  /// vive solo en memoria y se suelta al terminar o cancelar.
  Future<void> Function({required bool replace})? _lastInput;

  /// Si lo siguiente que se envíe ya viene confirmado para sustituir la
  /// familia de este móvil.
  bool _replaceNext = false;
  String? _hint;
  int? _focused;

  /// La retención de la entrada a la app (ver `recoveryHoldProvider`); se
  /// guarda aquí para soltarla en `dispose`, donde `ref` ya no vale.
  late final ValueNotifier<bool> _hold = ref.read(recoveryHoldProvider);

  @override
  void initState() {
    super.initState();
    _file = ref.read(recoveryFileProvider.notifier);
    _restoring = ref.read(recoveryFileRestoringProvider.notifier);
    if (widget.fileMode) {
      _stage = _Stage.filePick;
      // Un fichero que llegó desde Archivos antes de abrir esta pantalla.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _screens = ref.read(recoveryFileScreenOpenProvider.notifier);
          _screens!.add(1);
          unawaited(_adoptSelection(ref.read(recoveryFileProvider).selection));
        }
      });
    }
    // La familia aparece en pleno proceso: hasta «Entrar en la lista», que se
    // vea la pantalla final y ni el router ni el aviso de crear el PIN se
    // adelanten.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _hold.value = true;
      }
    });
    // Lo que se escribe o se pega aquí son las 24 palabras: Android no deja
    // capturar ni grabar mientras esta pantalla está a la vista.
    unawaited(enableSecureScreen());
    for (var i = 0; i < _count; i++) {
      final index = i;
      _nodes[i].addListener(() {
        if (_nodes[index].hasFocus) {
          setState(() => _focused = index);
        } else if (_focused == index) {
          setState(() => _focused = null);
        }
      });
    }
    unawaited(_loadWordlist());
    // Si la recuperación ya estaba en marcha (se cerró la app a medias), se
    // enseña su estado en vez de pedir las palabras otra vez.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncStatus());
    });
  }

  @override
  void dispose() {
    unawaited(disableSecureScreen());
    // Fuera del fotograma en que se desmonta: el router y la puerta del
    // bloqueo se repintan.
    final defer = _hold;
    scheduleMicrotask(() => defer.value = false);
    if (widget.fileMode) {
      final screens = _screens;
      if (screens != null) {
        scheduleMicrotask(() {
          try {
            screens.add(-1);
          } on Object {
            // El contenedor ya se cerró con la app.
          }
        });
      }
      // Fuera del fotograma en que se desmonta: el estado del flujo se repinta.
      final file = _file;
      scheduleMicrotask(() {
        try {
          file.clear();
        } on Object {
          // El contenedor ya se cerró con la app.
        }
      });
    }
    _filePassword.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  /// Mira el estado real al abrir (esperando a que se lea del diario) y lo
  /// adopta.
  Future<void> _syncStatus() async {
    try {
      await ref.read(recoveryApplicationProvider.notifier).refresh();
    } on Object {
      // Se sigue con lo que haya.
    }
    if (mounted) {
      _adopt(ref.read(recoveryStatusProvider));
    }
  }

  Future<void> _loadWordlist() async {
    try {
      final list = await loadRecoveryWordlist();
      if (mounted) {
        setState(() => _wordlist = list);
      }
    } on Object {
      // Sin la lista no se puede validar: el botón se queda apagado.
    }
  }

  /// Sigue el estado real cuando no es esta pantalla quien lo mueve: una
  /// recuperación que se reanudó sola al abrir la app, o que acaba mientras se
  /// mira. Una fase suelta solo se adopta si todavía se piden las palabras; en
  /// el progreso y en el error, solo cuentan el final y la atención.
  void _adopt(RecoveryStatus status) {
    if (_running) {
      return;
    }
    final phase = status.phase;
    if (phase == null || _stage == _Stage.done) {
      return;
    }
    if (phase == RecoveryPhase.needsAttention) {
      setState(() {
        _problem = recoveryProblemOf(status.cause);
        _stage = _Stage.error;
      });
    } else if (phase == RecoveryPhase.active) {
      if (_stage == _Stage.progress) {
        setState(() => _stage = _Stage.done);
      }
    } else if (_isEntryStage) {
      setState(() => _stage = _Stage.progress);
    }
  }

  /// Si todavía se está pidiendo el código (palabras o fichero), antes de que
  /// nada se envíe.
  bool get _isEntryStage =>
      _stage == _Stage.entry ||
      _stage == _Stage.filePick ||
      _stage == _Stage.filePassword ||
      _stage == _Stage.fileConfirm;

  // ---- Palabras

  String _norm(String text) => text.trim().toLowerCase();

  bool _isValid(String text) {
    final word = _norm(text);
    return word.isNotEmpty && _wordlist?.indexOf(word) != null;
  }

  String _full(String text) {
    final word = _norm(text);
    final list = _wordlist!;
    return list.words[list.indexOf(word)!];
  }

  bool _canBecomeValid(String text) {
    final word = _norm(text);
    final list = _wordlist;
    if (word.isEmpty || list == null) {
      return true;
    }
    return list.words.any((w) => w.startsWith(word));
  }

  int get _validCount => _controllers.where((c) => _isValid(c.text)).length;

  bool _isInvalid(int i) {
    final text = _controllers[i].text;
    if (_norm(text).isEmpty || _wordlist == null || _isValid(text)) {
      return false;
    }
    return _focused != i || !_canBecomeValid(text);
  }

  int? get _firstInvalid {
    for (var i = 0; i < _count; i++) {
      if (_isInvalid(i)) {
        return i;
      }
    }
    return null;
  }

  List<String> get _suggestions {
    final i = _focused;
    final list = _wordlist;
    if (i == null || list == null) {
      return const [];
    }
    final prefix = _norm(_controllers[i].text);
    if (prefix.length < 2 || _isExact(prefix)) {
      return const [];
    }
    return [
      for (final w in list.words)
        if (w.startsWith(prefix)) w,
    ].take(4).toList();
  }

  bool _isExact(String word) => _wordlist?.words.contains(word) ?? false;

  void _focusNext(int i) {
    if (i + 1 < _count) {
      _nodes[i + 1].requestFocus();
    } else {
      _nodes[i].unfocus();
    }
  }

  /// Reparte [tokens] desde el campo [start]: pegar varias palabras de golpe en
  /// cualquier campo las coloca todas.
  void _fill(int start, List<String> tokens) {
    for (var k = 0; k < tokens.length && start + k < _count; k++) {
      _controllers[start + k].text = _norm(tokens[k]);
    }
    final last = (start + tokens.length).clamp(0, _count);
    setState(() {
      _checksumFailed = false;
      _hint = null;
    });
    if (last < _count) {
      _nodes[last].requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _onChanged(int i, String text) {
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final hasSpace = RegExp(r'\s').hasMatch(text);
    if (hasSpace && tokens.isNotEmpty) {
      final list = tokens.toList();
      if (list.length == 1) {
        // Un espacio al final: la palabra está lista, se pasa a la siguiente.
        _controllers[i].text = _norm(list.first);
        _controllers[i].selection = TextSelection.collapsed(
          offset: _controllers[i].text.length,
        );
        setState(() {
          _checksumFailed = false;
          _hint = null;
        });
        _focusNext(i);
      } else {
        _fill(i, list);
      }
      return;
    }
    setState(() {
      _checksumFailed = false;
      _hint = null;
    });
  }

  void _accept(int i, String word) {
    _controllers[i].text = word;
    setState(() => _checksumFailed = false);
    _focusNext(i);
  }

  Future<void> _paste() async {
    final l10n = AppLocalizations.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (!mounted) {
      return;
    }
    if (text.isEmpty) {
      setState(() => _hint = l10n.recoverPasteEmpty);
      return;
    }
    final tokens = text.split(RegExp(r'\s+'));
    if (tokens.length != _count) {
      setState(() => _hint = l10n.recoverPasteWrong);
      return;
    }
    _fill(0, tokens);
    // Las palabras no se quedan en el portapapeles.
    unawaited(Clipboard.setData(const ClipboardData(text: '')));
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute<String>(builder: (_) => const RecoveryScanScreen()),
    );
    if (text != null && mounted) {
      _wipe();
      _lastInput = ({required bool replace}) => ref
          .read(recoveryApplicationProvider.notifier)
          .restoreQr(text, replaceExisting: replace);
      await _run(() => _lastInput!(replace: _replaceNext));
    }
  }

  void _wipe() {
    for (final c in _controllers) {
      c.clear();
    }
  }

  // ---- Envío

  Future<void> _submit() async {
    final list = _wordlist;
    if (list == null || _validCount != _count) {
      return;
    }
    final words = [for (final c in _controllers) _full(c.text)].join(' ');
    try {
      RecoveryCode.fromWords(words, list);
    } on RecoveryException {
      ref.read(hapticsProvider).error();
      setState(() => _checksumFailed = true);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _wipe();
    _lastInput = ({required bool replace}) => ref
        .read(recoveryApplicationProvider.notifier)
        .restoreWords(words, replaceExisting: replace);
    await _run(() => _lastInput!(replace: _replaceNext));
  }

  Future<void> _retry() =>
      _run(() => ref.read(recoveryApplicationProvider.notifier).retry());

  Future<void> _run(Future<void> Function() action) async {
    // Mientras restaura, un segundo fichero espera: no se puede parar a medias.
    if (widget.fileMode) {
      _restoring.set(true);
    }
    try {
      await _runAction(action);
    } finally {
      if (widget.fileMode) {
        try {
          _restoring.set(false);
        } on Object {
          // El contenedor ya se cerró con la app.
        }
      }
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() {
      _stage = _Stage.progress;
      _problem = null;
      _running = true;
    });
    RecoveryProblem? problem;
    try {
      await action();
      final status = ref.read(recoveryStatusProvider);
      if (status.readiness == RecoveryReadiness.needsAttention) {
        problem = recoveryProblemOf(status.cause);
      }
    } on RecoveryApplicationException catch (e) {
      problem = recoveryProblemOfException(e);
    } on RecoveryFileFlowException catch (e) {
      if (e.error == RecoveryFileFlowError.cancelled) {
        // El fichero se soltó o se cambió mientras tanto: sin mensaje.
        if (mounted) {
          setState(() {
            _running = false;
            _stage = _Stage.filePick;
          });
        }
        return;
      }
      problem = RecoveryProblem.other;
    } on Object {
      problem = RecoveryProblem.other;
    }
    if (!mounted) {
      return;
    }
    final haptics = ref.read(hapticsProvider);
    if (problem == null) {
      haptics.success();
      _lastInput = null;
      _replaceNext = false;
    } else {
      haptics.error();
    }
    setState(() {
      _running = false;
      _problem = problem;
      _stage = problem == null ? _Stage.done : _Stage.error;
    });
    if (problem != null && recoveryProblemNeedsReplace(problem)) {
      await _askReplace();
    }
  }

  /// El código es de otra familia: se pregunta antes de sustituir la de este
  /// móvil. Sin confirmar, se queda el aviso con sus botones.
  Future<void> _askReplace() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showRegalosConfirm(
      context,
      title: l10n.recoverReplaceTitle,
      body: l10n.recoverReplaceBody,
      confirmLabel: l10n.recoverReplaceConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!ok || !mounted) {
      return;
    }
    // Sustituir la lista de este móvil pide el PIN o la huella.
    try {
      final allowed = await verifyOwner(
        context,
        ref,
        title: l10n.recoverReplaceConfirm,
        message: l10n.joinReplacePinPrompt,
        biometricReason: l10n.joinReplaceBiometricReason,
      );
      if (!allowed || !mounted) {
        return;
      }
    } on Object {
      if (mounted) {
        showRegalosSnackBar(
          context,
          SnackBar(content: Text(l10n.recoverAbandonFailed)),
        );
      }
      return;
    }
    final again = _lastInput;
    if (again != null) {
      await _run(() => again(replace: true));
    } else {
      // Sin las palabras a mano (la recuperación venía de antes): se pide el
      // código otra vez y esta vez va confirmado.
      if (await _abandon()) {
        _replaceNext = true;
      }
    }
  }

  /// Descarta la recuperación a medias de este móvil y vuelve a pedir las
  /// palabras. Lo pedido antes se olvida.
  Future<bool> _abandon() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(recoveryApplicationProvider.notifier).abandon();
    } on Object {
      if (mounted) {
        showRegalosSnackBar(
          context,
          SnackBar(content: Text(l10n.recoverAbandonFailed)),
        );
      }
      return false;
    }
    if (!mounted) {
      return false;
    }
    // Otro código es otra decisión: la sustitución confirmada no se arrastra.
    _replaceNext = false;
    _lastInput = null;
    if (widget.fileMode) {
      _fileSerial++;
      _reopenSerial = null;
      _file.clear();
      _filePassword.clear();
    }
    setState(() {
      _stage = widget.fileMode ? _Stage.filePick : _Stage.entry;
      _problem = null;
      _fileProblem = null;
      _checksumFailed = false;
      _hint = null;
    });
    return true;
  }

  /// «Cancelar la recuperación»: pregunta antes, con el texto de antes o de
  /// después de que la reclamación se enviara.
  Future<void> _confirmAbandon() async {
    final claimSent = ref.read(recoveryStatusProvider).claimSent;
    final ok = await confirmAbandonRecovery(context, claimSent: claimSent);
    if (ok && mounted) {
      await _abandon();
    }
  }

  /// «Escribir otro código»: sin preguntar si no se envió nada; con
  /// pregunta si la reclamación ya salió.
  Future<void> _otherCode() async {
    if (ref.read(recoveryStatusProvider).claimSent) {
      await _confirmAbandon();
    } else {
      await _abandon();
    }
  }

  /// Salir de la pantalla. Con una recuperación a medias se pregunta: se queda
  /// como está y se podrá reanudar o cancelar desde la bienvenida.
  Future<void> _leave() async {
    if (_running) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (ref.read(recoveryStatusProvider).hasPendingRestore) {
      final leave = await showRegalosConfirm(
        context,
        title: l10n.recoverLeaveTitle,
        body: l10n.recoverLeaveBody,
        confirmLabel: l10n.recoveryLeaveConfirm,
        cancelLabel: l10n.recoveryLeaveStay,
      );
      if (!leave || !mounted) {
        return;
      }
    }
    _exit();
  }

  void _exit() {
    if (widget.embedded) {
      Navigator.of(context).pop();
      return;
    }
    final router = ref.read(routerProvider);
    router.canPop() ? router.pop() : router.go('/welcome');
  }

  // ---- Fichero (ADR 0008)

  /// Adopta el fichero que llegó de fuera (o ya estaba al abrir): lo inservible
  /// se dice y se descarta; el protegido pide la contraseña y el abierto pasa
  /// directo a la confirmación. Nunca deriva sin la contraseña.
  Future<void> _adoptSelection(RecoveryFileSelection? selection) async {
    if (!widget.fileMode || selection == null || _running) {
      return;
    }
    if (_stage == _Stage.progress || _stage == _Stage.done) {
      return;
    }
    // Antes del primer await: invalida las adopciones anteriores que sigan
    // esperando y es el fichero al que se refiere todo lo que sigue.
    final serial = ++_fileSerial;
    if (_stage == _Stage.error) {
      // Un fichero nuevo aceptado tras fallar la restauración del anterior:
      // se sale del error y se adopta el nuevo (lo elegido con el selector
      // sale de «elegir fichero», no de aquí).
      if (selection.source != RecoveryFileSource.received) {
        return;
      }
      if (ref.read(recoveryStatusProvider).hasPendingRestore) {
        try {
          await ref.read(recoveryApplicationProvider.notifier).abandon();
        } on Object {
          return;
        }
        if (!mounted || serial != _fileSerial) {
          // Mientras se abandonaba, se aceptó otro fichero: es el que manda.
          return;
        }
      }
      _replaceNext = false;
      _lastInput = null;
      setState(() => _problem = null);
    }
    _fileReceived = selection.source == RecoveryFileSource.received;
    _filePassword.clear();
    final failure = selection.failure;
    if (failure != null) {
      _file.clear();
      setState(() {
        _fileProblem = RecoveryFileProblem(
          failure == RecoveryFileFailure.newerVersion
              ? RecoveryFileProblemKind.newerVersion
              : RecoveryFileProblemKind.notRecoveryFile,
        );
        _stage = _Stage.filePick;
      });
      return;
    }
    if (selection.hasFamily) {
      _file.clear();
      setState(() {
        _fileProblem = const RecoveryFileProblem(
          RecoveryFileProblemKind.hasFamily,
        );
        _stage = _Stage.filePick;
      });
      return;
    }
    setState(() {
      _fileProblem = null;
      _stage = selection.opened
          ? _Stage.fileConfirm
          : selection.needsPassword
          ? _Stage.filePassword
          : _Stage.filePick;
    });
    if (!selection.opened && !selection.needsPassword) {
      if (_fileOpening) {
        // La apertura del anterior sigue deshaciéndose: esta empieza en cuanto
        // acabe.
        _reopenSerial = serial;
      } else {
        await _openFile();
      }
    }
  }

  /// «Elegir fichero»: el selector del sistema.
  Future<void> _pickFile() async {
    if (_filePicking) {
      return;
    }
    setState(() {
      _filePicking = true;
      _fileProblem = null;
    });
    try {
      final selection = await _file.pickForRestore();
      if (!mounted || selection == null) {
        return;
      }
      await _adoptSelection(selection);
    } on Object catch (e) {
      _fileFail(e);
    } finally {
      if (mounted) {
        setState(() => _filePicking = false);
      }
    }
  }

  /// Abre el fichero elegido: la variante abierta al momento; la protegida,
  /// con la contraseña y el progreso de la derivación (con «Cancelar»).
  Future<void> _openFile() async {
    if (_fileOpening) {
      return;
    }
    final needsPassword =
        ref.read(recoveryFileProvider).selection?.needsPassword ?? false;
    final serial = _fileSerial;
    setState(() {
      _fileOpening = true;
      _fileProblem = null;
    });
    try {
      await _file.open(password: needsPassword ? _filePassword.text : null);
      if (!mounted || serial != _fileSerial) {
        return;
      }
      _filePassword.clear();
      setState(() => _stage = _Stage.fileConfirm);
    } on Object catch (e) {
      if (serial == _fileSerial) {
        _fileFail(e);
      }
    } finally {
      if (mounted) {
        setState(() => _fileOpening = false);
        final pending = _reopenSerial;
        _reopenSerial = null;
        final current = ref.read(recoveryFileProvider).selection;
        if (pending != null &&
            pending == _fileSerial &&
            current != null &&
            current.failure == null &&
            current.variant == RecoveryFileVariant.open &&
            !current.opened) {
          unawaited(_openFile());
        }
      }
    }
  }

  /// Dice por qué no se pudo elegir o abrir el fichero. Una cancelación no
  /// dice nada.
  void _fileFail(Object error) {
    final problem = recoveryFileProblemOf(error);
    if (!mounted || problem == null) {
      return;
    }
    ref.read(hapticsProvider).error();
    setState(() {
      _fileProblem = problem;
      _stage = problem.isWrongPassword ? _Stage.filePassword : _Stage.filePick;
    });
    if (problem.isWrongPassword) {
      _fileShake.currentState?.shake();
    }
  }

  /// «Elegir otro fichero»: suelta el actual.
  void _otherFile() {
    _fileSerial++;
    _reopenSerial = null;
    _file.clear();
    _filePassword.clear();
    setState(() {
      _fileProblem = null;
      _stage = _Stage.filePick;
    });
  }

  /// «Recuperar la lista»: el mismo flujo que con las palabras, con la
  /// entropía del fichero abierto (que se conserva para reintentar).
  Future<void> _restoreFile() async {
    _lastInput = ({required bool replace}) =>
        _file.restore(replaceExisting: replace);
    await _run(() => _lastInput!(replace: _replaceNext));
  }

  Widget _fileBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final note = _fileReceived ? l10n.recoverFileReceived : null;
    switch (_stage) {
      case _Stage.filePassword:
        final deriving =
            ref.watch(recoveryFileProvider).activity ==
            RecoveryFileActivity.deriving;
        return AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecoveryFileStepBody(
                note: note,
                title: l10n.recoveryFilePasswordTitle,
                body: l10n.recoveryFilePasswordOpenBody,
                problem: _fileProblem,
                field: ShakeX(
                  key: _fileShake,
                  child: RecoveryPasswordField(
                    controller: _filePassword,
                    label: l10n.recoveryFilePassword,
                    newPassword: false,
                    autofocus: true,
                    enabled: !_fileOpening,
                    error: _fileProblem?.isWrongPassword ?? false,
                    onChanged: () => setState(() => _fileProblem = null),
                    onSubmitted: _filePassword.text.isEmpty || _fileOpening
                        ? null
                        : _openFile,
                  ),
                ),
              ),
              UnfoldSection(
                show: deriving,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: RecoveryDerivingCard(
                    title: l10n.recoveryFileDerivingTitle,
                    body: l10n.recoveryFileDerivingBody,
                  ),
                ),
              ),
            ],
          ),
        );
      case _Stage.fileConfirm:
        return StaggerScope(
          maxItems: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggerItem(
                index: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RecoveryBadge(icon: SettingsIcons.key, size: 56),
                ),
              ),
              const SizedBox(height: 16),
              StaggerItem(
                index: 1,
                child: RecoveryFileStepBody(
                  note: note,
                  title: l10n.recoverFileConfirmTitle,
                  body: l10n.recoverFileConfirmBody,
                ),
              ),
            ],
          ),
        );
      default:
        return StaggerScope(
          maxItems: 2,
          child: StaggerItem(
            index: 0,
            child: RecoveryFileStepBody(
              title: l10n.recoverFileTitle,
              body: l10n.recoverFileBody,
              problem: _fileProblem,
            ),
          ),
        );
    }
  }

  Widget _fileFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (_stage) {
      case _Stage.filePassword:
        // Mientras deriva, «Cancelar» va en el pie, siempre a la vista.
        if (ref.watch(recoveryFileProvider).activity ==
            RecoveryFileActivity.deriving) {
          return OutlinedButton(
            onPressed: _file.cancel,
            child: Text(l10n.actionCancel),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _filePassword.text.isEmpty || _fileOpening
                  ? null
                  : _openFile,
              child: Text(l10n.recoveryFileOpen),
            ),
            TextButton(
              onPressed: _otherFile,
              child: Text(l10n.recoverFileOther),
            ),
          ],
        );
      case _Stage.fileConfirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _restoreFile,
              child: Text(l10n.recoverSubmit),
            ),
            TextButton(
              onPressed: _otherFile,
              child: Text(l10n.recoverFileOther),
            ),
          ],
        );
      default:
        return FilledButton(
          onPressed: _filePicking || _fileOpening ? null : _pickFile,
          child: Text(l10n.recoveryFilePick),
        );
    }
  }

  // ---- Pantalla

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<RecoveryStatus>(
      recoveryStatusProvider,
      (previous, next) => _adopt(next),
    );
    // Un fichero que llega de fuera con esta pantalla abierta (o uno que
    // sustituye al actual tras preguntar).
    ref.listen<RecoveryFileSelection?>(
      recoveryFileProvider.select((state) => state.selection),
      (previous, next) {
        if (widget.fileMode &&
            next != null &&
            next.source == RecoveryFileSource.received &&
            !identical(previous, next)) {
          unawaited(_adoptSelection(next));
        }
      },
    );
    final status = ref.watch(recoveryStatusProvider);

    final Widget body;
    Widget? footer;
    switch (_stage) {
      case _Stage.entry:
        body = _entryBody(context);
        footer = _entryFooter(context);
      case _Stage.filePick || _Stage.filePassword || _Stage.fileConfirm:
        body = _fileBody(context);
        footer = _fileFooter(context);
      case _Stage.progress:
        body = _ProgressBody(phase: status.phase);
        // Una recuperación que sigue sin que esta pantalla la mueva (se
        // abrió la app a medias) se puede reanudar o cancelar.
        if (!_running) {
          footer = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(onPressed: _retry, child: Text(l10n.recoverResume)),
              TextButton(
                onPressed: _confirmAbandon,
                child: Text(l10n.recoverAbandon),
              ),
            ],
          );
        }
      case _Stage.error:
        final problem = _problem ?? RecoveryProblem.other;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RecoveryBadge(icon: SettingsIcons.key, size: 56),
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: RecoveryHeading(
                title: recoveryProblemTitle(l10n, problem),
                body: recoveryProblemBody(l10n, problem),
              ),
            ),
          ],
        );
        final other = recoveryProblemAllowsOtherCode(problem);
        final replace = recoveryProblemNeedsReplace(problem);
        final retry = recoveryProblemAllowsRetry(problem);
        footer = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (other)
              FilledButton(
                onPressed: _otherCode,
                child: Text(
                  widget.fileMode
                      ? l10n.recoverFileOther
                      : l10n.recoverOtherCode,
                ),
              ),
            if (replace)
              FilledButton(
                onPressed: _askReplace,
                child: Text(l10n.recoverReplaceConfirm),
              ),
            if (retry)
              if (other)
                TextButton(onPressed: _retry, child: Text(l10n.recoveryRetry))
              else
                FilledButton(
                  onPressed: _retry,
                  child: Text(l10n.recoveryRetry),
                ),
            if (!other)
              TextButton(
                onPressed: _confirmAbandon,
                child: Text(l10n.recoverAbandon),
              ),
          ],
        );
      case _Stage.done:
        body = _DoneBody();
        footer = FilledButton(
          onPressed: () {
            // Ahora sí: a la app, y el aviso del PIN, si toca, sobre ella.
            final router = ref.read(routerProvider);
            _hold.value = false;
            router.go('/people');
          },
          child: Text(l10n.recoverEnter),
        );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_leave());
        }
      },
      child: RecoveryFlowScaffold(
        onBack: (_stage == _Stage.progress && _running) || _stage == _Stage.done
            ? null
            : () => unawaited(_leave()),
        footer: footer,
        child: RecoveryFade(stateKey: _stage, child: body),
      ),
    );
  }

  Widget _entryBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final firstBad = _firstInvalid;
    final message = _checksumFailed
        ? l10n.recoverChecksum
        : firstBad != null
        ? l10n.recoverWordUnknown(firstBad + 1)
        : _hint;
    return StaggerScope(
      maxItems: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggerItem(
            index: 0,
            child: RecoveryHeading(
              title: l10n.recoverTitle,
              body: l10n.recoverBody,
            ),
          ),
          const SizedBox(height: 16),
          StaggerItem(
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _paste,
                  icon: StrokeIcon(
                    SettingsIcons.clipboard,
                    size: 18,
                    color: t.text,
                    strokeWidth: 1.9,
                  ),
                  label: Text(l10n.recoverPaste),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _scan,
                  icon: StrokeIcon(
                    SettingsIcons.qr,
                    size: 18,
                    color: t.text,
                    strokeWidth: 1.9,
                  ),
                  label: Text(l10n.recoverScan),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          StaggerItem(
            index: 2,
            child: Text(
              l10n.recoverFilled(_validCount),
              style: t.styles.metaStrong,
            ),
          ),
          const SizedBox(height: 8),
          StaggerItem(
            index: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = recoveryGridColumns(
                  context,
                  constraints.maxWidth,
                );
                const gap = 8.0;
                final cell =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < _count; i++)
                      SizedBox(
                        width: cell,
                        child: _WordCell(
                          number: i + 1,
                          controller: _controllers[i],
                          node: _nodes[i],
                          valid: _isValid(_controllers[i].text),
                          invalid: _isInvalid(i),
                          last: i == _count - 1,
                          onChanged: (text) => _onChanged(i, text),
                          onSubmitted: () => _focusNext(i),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: t.styles.meta.copyWith(
                  color: _hint == message ? t.textSecondary : t.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entryFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final suggestions = _suggestions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final word in suggestions)
                  Semantics(
                    button: true,
                    label: word,
                    excludeSemantics: true,
                    onTap: () => _accept(_focused!, word),
                    child: InkWell(
                      borderRadius: RegalosShape.chip,
                      onTap: () => _accept(_focused!, word),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: 44,
                          minWidth: 64,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: RegalosShape.chip,
                          border: Border.all(color: t.chipBorder),
                        ),
                        child: Text(word, style: t.styles.label),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        FilledButton(
          onPressed: _wordlist != null && _validCount == _count
              ? _submit
              : null,
          child: Text(l10n.recoverSubmit),
        ),
      ],
    );
  }
}

/// Un campo de palabra: el número a la izquierda, un visto cuando vale y el
/// borde rojo cuando no puede valer.
class _WordCell extends StatelessWidget {
  const _WordCell({
    required this.number,
    required this.controller,
    required this.node,
    required this.valid,
    required this.invalid,
    required this.last,
    required this.onChanged,
    required this.onSubmitted,
  });

  final int number;
  final TextEditingController controller;
  final FocusNode node;
  final bool valid;
  final bool invalid;
  final bool last;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: RegalosShape.field,
          borderSide: BorderSide(color: color, width: width),
        );
    return Semantics(
      label: l10n.recoverWordField(number),
      child: TextField(
        controller: controller,
        focusNode: node,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        textCapitalization: TextCapitalization.none,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted(),
        style: t.styles.rowTitle,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 12,
          ),
          prefixIcon: SizedBox(
            width: 34,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '$number',
                  style: t.styles.meta.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  semanticsLabel: '',
                ),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: valid
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: StrokeIcon(
                    AppIcons.check,
                    size: 16,
                    color: t.ink,
                    strokeWidth: 2.2,
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 24),
          enabledBorder: invalid
              ? border(t.danger, 1.5)
              : border(t.controlBorder),
          focusedBorder: invalid ? border(t.danger, 2) : border(t.ink, 2),
        ),
      ),
    );
  }
}

/// Las cuatro fases de la recuperación, con la actual girando y las hechas
/// con su visto.
class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.phase});

  final RecoveryPhase? phase;

  /// En cuál de los cuatro pasos de la lista está [phase].
  static int stepOf(RecoveryPhase? phase) => switch (phase) {
    null || RecoveryPhase.locating || RecoveryPhase.needsAttention => 0,
    RecoveryPhase.located ||
    RecoveryPhase.verified ||
    RecoveryPhase.claimPrepared ||
    RecoveryPhase.claimConfirmed => 1,
    RecoveryPhase.downloading => 2,
    RecoveryPhase.installPrepared || RecoveryPhase.active => 3,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = stepOf(phase);
    final labels = [
      l10n.recoverStepFind,
      l10n.recoverStepCheck,
      l10n.recoverStepDownload,
      l10n.recoverStepInstall,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecoveryHeading(
          title: l10n.recoverProgressTitle,
          body: l10n.recoverProgressBody,
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < labels.length; i++)
          _StepRow(label: labels[i], done: i < current, active: i == current),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      label: label,
      value: done
          ? l10n.recoverStepDoneValue
          : active
          ? l10n.recoverStepActiveValue
          : null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: Center(
                child: done
                    ? StrokeIcon(
                        AppIcons.check,
                        size: 20,
                        color: t.ink,
                        strokeWidth: 2.4,
                      )
                    : active
                    ? const RecoverySpinner(size: 20)
                    : Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: RegalosShape.tiny,
                          border: Border.all(color: t.chipBorder, width: 1.5),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: active || done
                    ? t.styles.rowTitle
                    : t.styles.rowTitle.copyWith(color: t.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El resultado: a qué persona pertenece el móvil recuperado.
class _DoneBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final self = ref.watch(selfRecipientProvider);
    final people = ref.watch(familyViewProvider).recipients.length;
    return StaggerScope(
      maxItems: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StaggerItem(
            index: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: RecoverySuccessMark(size: 56),
            ),
          ),
          const SizedBox(height: 16),
          StaggerItem(
            index: 1,
            child: Semantics(
              liveRegion: true,
              child: RecoveryHeading(
                title: l10n.recoverDoneTitle,
                body: self == null
                    ? l10n.recoverDoneNoSelf
                    : l10n.recoverDoneSelf(self.name),
              ),
            ),
          ),
          if (people > 0) ...[
            const SizedBox(height: 12),
            StaggerItem(
              index: 2,
              child: Text(
                l10n.recoverDonePeople(people),
                style: RegalosTokens.of(context).styles.body,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
