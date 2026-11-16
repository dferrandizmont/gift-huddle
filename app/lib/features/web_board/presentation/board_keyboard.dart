import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'board_editor_host.dart';

class _StepIntent extends Intent {
  const _StepIntent(this.delta);

  final int delta;
}

class _PageIntent extends Intent {
  const _PageIntent(this.delta);

  final int delta;
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _NewIntent extends Intent {
  const _NewIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

/// Los atajos del tablero de la web de escritorio
/// (la guía de diseño de escritorio, L6): ↑ y ↓ recorren los
/// regalos de la pantalla (los carriles de «Hoy» o la tabla de una persona; con
/// el editor abierto, el editor sigue a la marca), Intro abre el marcado,
/// Alt + ↑ y Alt + ↓ cambian de persona en la barra lateral, N abre «Nuevo
/// regalo» y Esc cierra el editor (o quita la marca).
///
/// Ninguno actúa mientras se escribe en un campo. ↑, ↓ e Intro tampoco actúan
/// con el foco dentro del editor ni de un diálogo u hoja.
class BoardKeyboard extends StatelessWidget {
  /// Crea los atajos.
  const BoardKeyboard({
    super.key,
    required this.onStep,
    required this.onPage,
    required this.onOpen,
    required this.onNew,
    required this.onEscape,
    required this.escapeEnabled,
    required this.openEnabled,
    required this.child,
  });

  /// ↑ (-1) y ↓ (1): el regalo de al lado.
  final ValueChanged<int> onStep;

  /// Alt + ↑ (-1) y Alt + ↓ (1): la persona de al lado.
  final ValueChanged<int> onPage;

  /// Intro: abre el regalo marcado.
  final VoidCallback onOpen;

  /// N.
  final VoidCallback onNew;

  /// Esc.
  final VoidCallback onEscape;

  /// Si Esc tiene algo que cerrar (el editor abierto o una marca).
  final bool Function() escapeEnabled;

  /// Si hay un regalo marcado que abrir con Intro.
  final bool Function() openEnabled;

  final Widget child;

  static bool _typing() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) {
      return false;
    }
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Si el foco está en un sitio donde las flechas son del tablero: en
  /// ninguna parte en concreto o en cualquier control que no sea del editor
  /// ni de un diálogo o una hoja.
  static bool _boardFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus is FocusScopeNode) {
      return true;
    }
    final context = focus.context;
    if (context == null || !context.mounted) {
      return true;
    }
    if (BoardEditorMarker.isInside(context)) {
      return false;
    }
    return ModalRoute.of(context) is! PopupRoute;
  }

  /// Si el foco no está en ningún control en concreto (Intro, en un botón, es
  /// del botón).
  static bool _noControl() {
    final focus = FocusManager.instance.primaryFocus;
    return focus == null || focus is FocusScopeNode;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      includeSemantics: false,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp): _StepIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowDown): _StepIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _PageIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _PageIntent(
          1,
        ),
        SingleActivator(LogicalKeyboardKey.enter): _OpenIntent(),
        SingleActivator(LogicalKeyboardKey.keyN): _NewIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _StepIntent: _Guarded<_StepIntent>(
            enabled: (_) => !_typing() && _boardFocus(),
            onInvoke: (intent) => onStep(intent.delta),
          ),
          _PageIntent: _Guarded<_PageIntent>(
            enabled: (_) => !_typing() && _boardFocus(),
            onInvoke: (intent) => onPage(intent.delta),
          ),
          _OpenIntent: _Guarded<_OpenIntent>(
            enabled: (_) => !_typing() && _noControl() && openEnabled(),
            onInvoke: (_) => onOpen(),
          ),
          _NewIntent: _Guarded<_NewIntent>(
            enabled: (_) => !_typing(),
            onInvoke: (_) => onNew(),
          ),
          _EscapeIntent: _Guarded<_EscapeIntent>(
            enabled: (_) => escapeEnabled(),
            onInvoke: (_) => onEscape(),
          ),
        },
        child: Focus(
          // Sin nodo de accesibilidad propio, y sin pedir el foco: solo
          // recoge las teclas que le llegan de dentro.
          includeSemantics: false,
          skipTraversal: true,
          canRequestFocus: false,
          child: child,
        ),
      ),
    );
  }
}

class _Guarded<T extends Intent> extends Action<T> {
  _Guarded({required this.enabled, required this.onInvoke});

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
