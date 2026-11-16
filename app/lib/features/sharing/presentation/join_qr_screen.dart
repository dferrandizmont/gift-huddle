import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/root_navigator.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/device/device_name.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/domain/family_errors.dart';
import '../../sync/application/pairing_v2_controller.dart';
import '../../sync/data/sync_config.dart';
import '../../sync/invites/invite_link.dart';
import '../../sync/presentation/join_invite_screen.dart';
import '../application/pairing_service.dart';
import 'paired_sheet.dart';
import 'qr_camera_scanner.dart';
import 'scan_viewfinder.dart';
import 'share_error_text.dart';
import '../../../core/widgets/regalos_snack_bar.dart';

/// Construye el lector de códigos. Recibe lo que lee en [onCode]. Las pruebas
/// lo sustituyen: no hay cámara.
typedef ScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

/// Lector de códigos que usa la pantalla; las pruebas lo sustituyen.
final scannerBuilderProvider = Provider<ScannerBuilder?>((ref) => null);

/// «Unirme con QR»: lee el código del otro móvil y entra en su familia.
///
/// En el móvil, la cámara ocupa lo que queda bajo el nombre. En tablet
/// (la guía de diseño para tablet, §3) va en un cuadro de [cameraMaxSide]
/// como mucho: en vertical, centrado en una columna de 520 con el texto
/// debajo; en horizontal, a la izquierda del texto en una columna de 720.
class JoinQrScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const JoinQrScreen({super.key, this.deviceName = ''});

  /// Nombre confirmado en la bienvenida, si se pasó por su campo editable.
  final String deviceName;

  /// Lado máximo del cuadro de la cámara en tablet.
  static const double cameraMaxSide = 480;

  /// Lado mínimo del cuadro de la cámara en tablet: si la ventana es más baja,
  /// la pantalla se desplaza.
  static const double cameraMinSide = 240;

  /// Ancho mínimo del texto cuando va a la derecha de la cámara.
  static const double sideTextMinWidth = 280;

  @override
  ConsumerState<JoinQrScreen> createState() => _JoinQrScreenState();
}

class _JoinQrScreenState extends ConsumerState<JoinQrScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.deviceName,
  );
  final GlobalKey<ScanViewfinderState> _finder =
      GlobalKey<ScanViewfinderState>();

  // La cámara y el campo cambian de sitio entre el móvil, la tablet en
  // vertical y en horizontal: con clave, girar no reinicia la cámara ni
  // pierde el foco del campo.
  final GlobalKey _cameraKey = GlobalKey(debugLabel: 'join-camera');
  final GlobalKey _nameKey = GlobalKey(debugLabel: 'join-name');
  bool _busy = false;

  /// Si el permiso de cámara está denegado: sin cámara no hay visor.
  bool _denied = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _inviteIdOf(String text) {
    try {
      return parseInvite(
        text,
        expectedHost: ref.read(syncEndpointProvider)?.invitationHost,
      );
    } on InviteFormatException {
      return null;
    }
  }

  /// Abre la invitación v2 leída del QR en la pantalla de entrar con un
  /// número; al volver sin haber entrado, el lector queda listo otra vez.
  Future<void> _openV2(String inviteId, Rect? codeRect) async {
    setState(() => _busy = true);
    final reduce = RegalosMotion.of(context).reduce;
    _finder.currentState?.lock(codeRect);
    // Las esquinas recorren el 70 % de su muelle antes de pasar a la pantalla
    // de comparar el número, igual que con la hoja de éxito.
    await Future<void>.delayed(ScanViewfinder.followUp(reduce: reduce));
    if (!mounted) {
      return;
    }
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JoinInviteScreen(
          initialInvite: inviteId,
          deviceName: deviceNameToSend(ref, _name.text),
        ),
      ),
    );
    if (mounted) {
      _finder.currentState?.reset();
      setState(() => _busy = false);
    }
  }

  /// Se leyó un código. [codeRect] es dónde está en el visor, si se sabe: las
  /// esquinas se cierran sobre él mientras se une. El lector de la app no lo
  /// sabe (ZXing solo da el texto): se cierran hacia el centro.
  Future<void> _onCode(String text, [Rect? codeRect]) async {
    if (_busy) {
      return;
    }
    // Con la sincronización v2 el QR es un enlace de invitación sin clave: se
    // entra comparando un número con el otro móvil (ADR 0004).
    if (ref.read(pairingV2AvailableProvider)) {
      final inviteId = _inviteIdOf(text);
      if (inviteId != null) {
        await _openV2(inviteId, codeRect);
        return;
      }
    }
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    final service = ref.read(pairingServiceProvider);
    final deviceName = deviceNameToSend(ref, _name.text);
    // Las esquinas viajan al código y la unión corre a la vez; la hoja de
    // éxito sube al 70 % del muelle de las esquinas.
    final reduce = RegalosMotion.of(context).reduce;
    final sinceRead = Stopwatch()..start();
    _finder.currentState?.lock(codeRect);
    try {
      JoinResult result;
      try {
        result = await service.joinFromQr(text, deviceName: deviceName);
      } on FamilyConflictException {
        if (!mounted) {
          return;
        }
        final replace = await showRegalosConfirm(
          context,
          title: l10n.joinConflictTitle,
          body: l10n.joinConflictBody,
          confirmLabel: l10n.joinReplace,
          cancelLabel: l10n.actionCancel,
        );
        if (!replace) {
          if (mounted) {
            _finder.currentState?.reset();
            setState(() => _busy = false);
          }
          return;
        }
        result = await service.joinFromQr(
          text,
          replace: true,
          deviceName: deviceName,
        );
      }
      // Las esquinas ya han recorrido el 70 % de su muelle.
      final wait = ScanViewfinder.followUp(reduce: reduce) - sinceRead.elapsed;
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      // Al unirse hay familia: se sale a Personas y allí se avisa del
      // emparejado, aunque esta pantalla ya no esté.
      router.go('/people');
      await WidgetsBinding.instance.endOfFrame;
      final sheetContext = rootNavigatorKey.currentContext;
      if (sheetContext != null && sheetContext.mounted) {
        await showPairedSheet(
          sheetContext,
          title: l10n.joinDoneTitle,
          body: l10n.joinDoneBody(result.peerName),
        );
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _finder.currentState?.reset();
      setState(() => _busy = false);
      // Un móvil ya en v2 no usa un QR de v1 con la clave (hallazgo 13): el
      // otro móvil tiene que actualizarse.
      final message = error is V1PairingOnV2Exception
          ? l10n.pairingV2VersionMismatch
          : shareErrorMessage(l10n, error);
      showRegalosSnackBar(context, SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final custom = ref.watch(scannerBuilderProvider);
    // El lector real (ZXing, sin servicios de Google) y el de las pruebas solo
    // dan el texto del código.
    Widget scanner(BuildContext context) =>
        custom?.call(context, _onCode) ??
        QrCameraScanner(
          onCode: _onCode,
          // El visor entra cuando la cámara ya da imagen.
          onReady: () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => _finder.currentState?.begin(),
          ),
          onDeniedChanged: (denied) {
            if (mounted) {
              setState(() => _denied = denied);
            }
          },
        );
    final window = WindowClass.of(context);
    final compact = window == WindowClass.compact;
    final header = ScreenHeader(
      title: l10n.shareJoinTitle,
      // En tablet la frase acompaña a la cámara, con el campo del nombre.
      subtitle: compact ? l10n.joinIntro : null,
      backLabel: l10n.actionBack,
      onBack: () => context.canPop() ? context.pop() : context.go('/people'),
    );
    final name = KeyedSubtree(
      key: _nameKey,
      child: DeviceNameField(controller: _name),
    );
    final camera = KeyedSubtree(
      key: _cameraKey,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            scanner(context),
            if (_busy)
              const ColoredBox(
                color: Color(0x88000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            // Encima de todo: las esquinas se ven al leer. Con el permiso
            // denegado no hay nada que enmarcar.
            if (!_denied)
              IgnorePointer(
                child: ScanViewfinder(key: _finder, autoStart: custom != null),
              ),
          ],
        ),
      ),
    );
    if (compact) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              header,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: name,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: camera,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final sideBySide = window == WindowClass.expanded;
    final column = sideBySide
        ? RegalosLayout.detailMaxWidth
        : RegalosLayout.onboardingColumn;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.joinIntro, style: t.styles.body),
        const SizedBox(height: 12),
        name,
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ContentWidth(maxWidth: column, child: header),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const margin = EdgeInsets.fromLTRB(20, 12, 20, 16);
                  const gap = 24.0;
                  final inner =
                      math.min(constraints.maxWidth, column) -
                      margin.horizontal;
                  // El cuadro cabe entero a la vista si la ventana da para
                  // ello; si no, se queda en el mínimo y la pantalla se
                  // desplaza.
                  final room =
                      constraints.maxHeight -
                      margin.vertical -
                      (sideBySide ? 0 : _textReserve);
                  final side = math.max(
                    JoinQrScreen.cameraMinSide,
                    math.min(
                      JoinQrScreen.cameraMaxSide,
                      math.min(
                        room,
                        sideBySide
                            ? inner - gap - JoinQrScreen.sideTextMinWidth
                            : inner,
                      ),
                    ),
                  );
                  final box = SizedBox.square(dimension: side, child: camera);
                  return SingleChildScrollView(
                    child: ContentWidth(
                      maxWidth: column,
                      child: Padding(
                        padding: margin,
                        child: sideBySide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  box,
                                  const SizedBox(width: gap),
                                  Expanded(child: text),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Center(child: box),
                                  const SizedBox(height: 16),
                                  text,
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que se guarda de alto para el texto y el campo que van bajo la cámara
/// en la tablet en vertical, al decidir el lado del cuadro.
const double _textReserve = 150;
