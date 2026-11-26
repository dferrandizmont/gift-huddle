import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_selection.dart' show kSelectionSpring;
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../application/board_metrics.dart';
import '../application/gift_editor_panel.dart';
import 'board_scope.dart';

/// Marca lo que está dentro del panel del editor, para que los atajos del
/// tablero (↑ y ↓) no actúen con el foco ahí dentro.
class BoardEditorMarker extends InheritedWidget {
  /// Crea la marca.
  const BoardEditorMarker({super.key, required super.child});

  /// Si [context] está dentro del panel del editor.
  static bool isInside(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BoardEditorMarker>() != null;

  @override
  bool updateShouldNotify(BoardEditorMarker old) => false;
}

/// El marco del contenido del tablero y el panel del editor de regalo, a su
/// derecha (la guía de diseño de escritorio, «Editor»).
///
/// El panel mide `clamp(0,17·W, 400, 480)`. Si quedan unos 1100 para los
/// carriles, **empuja** el contenido (que se estrecha con él); si no, se
/// **superpone** con sombra y el contenido sigue a su ancho (las pantallas que
/// no pueden quedar debajo, como la tabla de Persona, reservan el sitio con
/// `BoardScope.overlayInset`). Abrir, cerrar y pasar de empujar a superponer al
/// cambiar el tamaño de la ventana se animan con un muelle crítico de 280 ms
/// (sin rebote: un ancho no puede pasarse de su sitio); con «Reducir
/// movimiento», un fundido de 150 ms.
///
/// Pedir otro regalo con el panel abierto cambia el editor con un fundido, sin
/// cerrarlo. Mientras está montado, avisa al [GiftEditorPanelController] de que
/// hay dónde enseñar el editor (`openGiftEditor` lo usa en lugar de la hoja).
class BoardEditorHost extends ConsumerStatefulWidget {
  /// Crea el marco con el [child] de contenido. [sidebar] es lo que mide la
  /// barra lateral ahora (para decidir si el editor empuja).
  const BoardEditorHost({
    super.key,
    required this.child,
    this.sidebar = BoardMetrics.sidebarWide,
  });

  /// El contenido del tablero.
  final Widget child;

  /// El ancho de la barra lateral ahora.
  final double sidebar;

  /// Lo que tarda en abrirse y cerrarse.
  static const Duration travel = Duration(milliseconds: 280);

  /// El ancho del panel abierto para una ventana de [windowWidth].
  static double widthFor(double windowWidth) =>
      BoardMetrics.editorWidthFor(windowWidth);

  @override
  ConsumerState<BoardEditorHost> createState() => _BoardEditorHostState();
}

class _BoardEditorHostState extends ConsumerState<BoardEditorHost> {
  late final GiftEditorPanelController _panel = ref.read(
    giftEditorPanelProvider,
  );
  final Curve _curve = SpringCurve(kSelectionSpring, BoardEditorHost.travel);

  /// La última petición, para seguir enseñándola mientras el panel se cierra.
  GiftEditorRequest? _shown;

  GoRouterDelegate? _delegate;
  String? _path;

  @override
  void initState() {
    super.initState();
    _panel.attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final delegate = GoRouter.maybeOf(context)?.routerDelegate;
    if (delegate != _delegate) {
      _delegate?.removeListener(_onRoute);
      _delegate = delegate;
      _path = delegate?.currentConfiguration.uri.path;
      delegate?.addListener(_onRoute);
    }
  }

  @override
  void dispose() {
    _delegate?.removeListener(_onRoute);
    _panel.detach();
    super.dispose();
  }

  /// Al cambiar de pantalla el editor se cierra (con su muelle) y se quita la
  /// marca de la fila, salvo que el formulario tenga cambios sin guardar o se
  /// vaya a la persona o la ocasión del regalo que se edita.
  void _onRoute() {
    final uri = _delegate?.currentConfiguration.uri;
    if (uri == null || uri.path == _path) {
      return;
    }
    _path = uri.path;
    final request = _panel.request;
    var stays = false;
    if (request != null) {
      final segments = uri.pathSegments;
      final id = segments.length >= 2 ? segments[1] : null;
      final gift = request.gift;
      final person = gift?.recipientId ?? request.recipientId;
      final occasion = gift?.occasionId ?? request.occasionId;
      stays =
          _panel.isDirty ||
          (id != null &&
              ((segments.first == 'people' && id == person) ||
                  (segments.first == 'occasions' && id == occasion)));
    }
    if (stays) {
      return;
    }
    ref.read(boardGiftCursorProvider).clear();
    _panel.close();
  }

  /// Un valor de 0 a 1 que sigue a [on] con el muelle de la barra.
  Widget _phase(bool on, bool reduce, Widget Function(double phase) builder) =>
      TweenAnimationBuilder<double>(
        tween: Tween<double>(end: on ? 1 : 0),
        duration: reduce ? RegalosMotion.fade : BoardEditorHost.travel,
        curve: reduce ? Curves.linear : _curve,
        builder: (context, value, _) => builder(value),
      );

  Widget _editor(
    BuildContext context,
    GiftEditorRequest shown,
    RegalosTokens t,
    AppLocalizations l10n,
  ) => BoardEditorMarker(
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.boardEditorLabel,
      child: Material(
        color: t.sheet,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.separator)),
          ),
          child: SafeArea(
            left: false,
            child: AnimatedSwitcher(
              duration: RegalosMotion.fade,
              child: GiftEditorScreen(
                key: ValueKey<int>(shown.serial),
                gift: shown.gift,
                initialRecipientId: shown.recipientId,
                initialOccasionId: shown.occasionId,
                initialGiverId: shown.giverId,
                initialStatus: shown.status,
                chooseRecipient: shown.chooseRecipient,
                onOwnPerson: shown.onOwnPerson,
                asPanel: true,
                onClose: _panel.close,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final window = MediaQuery.sizeOf(context).width;
    final panelWidth = BoardEditorHost.widthFor(window);
    final margin = BoardMetrics.marginFor(window);
    final push = BoardMetrics.editorPushes(window, sidebar: widget.sidebar);
    return ListenableBuilder(
      listenable: _panel,
      builder: (context, _) {
        final request = _panel.request;
        if (request != null) {
          _shown = request;
        }
        final open = request != null;
        final shown = _shown;
        return _phase(
          open,
          reduce,
          (openPhase) => _phase(
            open && push,
            reduce,
            (pushPhase) => _phase(open && !push, reduce, (overlayPhase) {
              if (!open && openPhase == 0 && shown != null) {
                // Ya se cerró del todo: se suelta lo último que se enseñaba.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _panel.request == null) {
                    setState(() => _shown = null);
                  }
                });
              }
              final visible = panelWidth * openPhase;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(right: panelWidth * pushPhase),
                      child: BoardScope(
                        margin: margin,
                        overlayInset: panelWidth * overlayPhase,
                        child: widget.child,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: visible,
                    child: DecoratedBox(
                      // Superpuesto, un filete de 1 a su izquierda además de la
                      // sombra: en oscuro la sombra sola no separa.
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: overlayPhase > 0
                            ? Border(left: BorderSide(color: t.separator))
                            : null,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: overlayPhase > 0
                              ? [
                                  BoxShadow(
                                    color: t.shadow.withValues(
                                      alpha: t.shadow.a * overlayPhase,
                                    ),
                                    blurRadius: 32,
                                    offset: const Offset(-6, 0),
                                  ),
                                ]
                              : const <BoxShadow>[],
                        ),
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: AlignmentDirectional.centerStart,
                            minWidth: panelWidth,
                            maxWidth: panelWidth,
                            child: shown == null
                                ? const SizedBox.shrink()
                                : _editor(context, shown, t, l10n),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }
}
