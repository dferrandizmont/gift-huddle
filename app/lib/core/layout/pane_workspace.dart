import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pane_scope.dart';

/// Lo que comparten las pestañas de dos paneles (Personas, Ocasiones y
/// Ajustes) para el atrás del sistema.
///
/// Con dos paneles, la página de la lista (`/occasions`) queda debajo de la
/// del detalle (`/occasions/:id`) y no se ve: no monta nada mientras tanto. Y
/// el detalle es la raíz de la pestaña, así que el atrás del sistema sale de la
/// app (si no, la lista se queda debajo y el router la manda de vuelta a una
/// fila, y el atrás no llevaría a ningún sitio).
///
/// - [panes]: si la ventana tiene dos paneles.
/// - [routed]: si la URL lleva una fila elegida (`/occasions/:id`).
/// - [exitOnBack]: si el atrás sale de la app (no, si se llegó desde otra
///   pantalla y tiene a dónde volver).
class PaneRootGuard extends StatelessWidget {
  /// Crea la guardia.
  const PaneRootGuard({
    super.key,
    required this.panes,
    required this.routed,
    this.exitOnBack = true,
    required this.child,
  });

  final bool panes;
  final bool routed;
  final bool exitOnBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // La página de la lista, tapada por la del detalle, no monta nada.
    if (panes && !routed && !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return const SizedBox.shrink();
    }
    final isRoot = panes && routed && exitOnBack;
    return PopScope(
      canPop: !isRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isRoot) {
          SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}

/// Los atajos de teclado de una pestaña de dos paneles (plan de escritorio,
/// §2.3):
///
/// - ↑ y ↓ cambian la fila elegida del panel de lista ([onStep] recibe -1 o 1).
/// - Intro pasa el foco al detalle: la fila elegida ya está abierta, así que
///   abrirla es entrar en ella.
/// - N abre «Nuevo regalo» ([onNew]).
///
/// Ninguno actúa mientras el foco está en un campo de texto. ↑ y ↓ solo actúan
/// con el foco en el panel de lista (o en ninguna parte), e Intro solo cuando
/// el foco no está en ningún control: en un botón o una fila, Intro es del
/// botón o de la fila, como siempre. Esc no se ata aquí: lo cierra cada hoja
/// y cada editor por su cuenta.
///
/// Solo atrapa teclas la pestaña que se ve (las demás siguen montadas). Sin
/// [enabled] (un panel) no atrapa ninguna.
class PaneKeyboard extends StatefulWidget {
  /// Crea los atajos alrededor de [child].
  const PaneKeyboard({
    super.key,
    required this.enabled,
    this.onStep,
    this.onNew,
    required this.child,
  });

  /// Si la pestaña tiene dos paneles.
  final bool enabled;

  /// Cambia la fila elegida [delta] filas (-1 arriba, 1 abajo).
  final ValueChanged<int>? onStep;

  /// Abre «Nuevo regalo». Recibe un contexto del panel de detalle (o el de la
  /// pestaña), para que la hoja se centre en él.
  final ValueChanged<BuildContext>? onNew;

  final Widget child;

  @override
  State<PaneKeyboard> createState() => _PaneKeyboardState();
}

class _StepIntent extends Intent {
  const _StepIntent(this.delta);
  final int delta;
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _NewIntent extends Intent {
  const _NewIntent();
}

class _PaneKeyboardState extends State<PaneKeyboard> {
  final FocusNode _root = FocusNode(
    debugLabel: 'pane-keyboard',
    skipTraversal: true,
  );
  ValueListenable<TickerModeData>? _visible;
  bool _claimScheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_claimSoon);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible?.removeListener(_claimSoon);
    _visible = TickerMode.getValuesNotifier(context)..addListener(_claimSoon);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_claimSoon);
    _visible?.removeListener(_claimSoon);
    _root.dispose();
    super.dispose();
  }

  /// Si esta pestaña es la que se ve (las demás siguen montadas, fuera de la
  /// vista).
  bool get _isVisible => _visible?.value.enabled ?? true;

  /// Si la tecla va para esta pestaña.
  bool get _active => widget.enabled && _isVisible;

  /// Si el foco está escribiendo en un campo de texto.
  static bool _typing() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) {
      return false;
    }
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Recoge el foco si nadie lo tiene dentro de la pestaña que se ve: así las
  /// flechas, Intro y N funcionan nada más entrar o tras escribir en un campo.
  /// Lo hace al acabar el fotograma, que no se puede pedir foco en medio de un
  /// cambio de foco.
  void _claimSoon() {
    if (_claimScheduled || !mounted) {
      return;
    }
    _claimScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _claimScheduled = false;
      if (!mounted || !_active || !_root.canRequestFocus) {
        return;
      }
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null || identical(focus, _root)) {
        return;
      }
      final context = focus.context;
      final hidden =
          context != null &&
          context.mounted &&
          !TickerMode.getValuesNotifier(context).value.enabled;
      final blank = focus is FocusScopeNode && _root.ancestors.contains(focus);
      if (hidden || blank) {
        _root.requestFocus();
      }
    });
  }

  /// Los controles del panel de detalle, por orden.
  Iterable<FocusNode> _detailNodes() => _root.traversalDescendants.where((n) {
    final context = n.context;
    return context != null &&
        context.mounted &&
        PaneScope.roleOf(context) == PaneRole.detail;
  });

  bool _stepEnabled() {
    if (widget.onStep == null || !_active || _typing()) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (identical(focus, _root)) {
      return true;
    }
    final context = focus?.context;
    return context != null &&
        context.mounted &&
        PaneScope.roleOf(context) == PaneRole.list &&
        _root.descendants.contains(focus);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    return Shortcuts(
      // Ni este ni el `Focus` de dentro llevan nodo de accesibilidad propio:
      // unirían en uno solo lo de debajo.
      includeSemantics: false,
      shortcuts: on
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowUp): _StepIntent(-1),
              SingleActivator(LogicalKeyboardKey.arrowDown): _StepIntent(1),
              SingleActivator(LogicalKeyboardKey.enter): _OpenIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): _OpenIntent(),
              SingleActivator(LogicalKeyboardKey.keyN): _NewIntent(),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          _StepIntent: _GuardedAction<_StepIntent>(
            enabled: (_) => _stepEnabled(),
            onInvoke: (intent) => widget.onStep?.call(intent.delta),
          ),
          _OpenIntent: _GuardedAction<_OpenIntent>(
            enabled: (_) =>
                _active &&
                !_typing() &&
                identical(FocusManager.instance.primaryFocus, _root),
            onInvoke: (_) => _detailNodes().firstOrNull?.requestFocus(),
          ),
          _NewIntent: _GuardedAction<_NewIntent>(
            enabled: (_) => widget.onNew != null && _active && !_typing(),
            onInvoke: (_) => widget.onNew?.call(
              _detailNodes().firstOrNull?.context ?? context,
            ),
          ),
        },
        child: Focus(
          focusNode: _root,
          autofocus: true,
          // Sin nodo de accesibilidad propio: uniría lo de debajo en uno solo.
          includeSemantics: false,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Una acción que solo corre si [enabled] lo permite; si no, la tecla sigue su
/// camino.
class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction({required this.enabled, required this.onInvoke});

  final bool Function(T intent) enabled;
  final void Function(T intent) onInvoke;

  @override
  bool isEnabled(T intent) => enabled(intent);

  @override
  Object? invoke(T intent) {
    onInvoke(intent);
    return null;
  }
}
