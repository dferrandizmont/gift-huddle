import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';

/// Lo que se pide al panel del editor: qué regalo abrir o con qué empezar uno
/// nuevo. Es lo mismo que recibe `openGiftEditor`.
class GiftEditorRequest {
  GiftEditorRequest._({
    required this.serial,
    required this.gift,
    required this.recipientId,
    required this.occasionId,
    required this.giverId,
    required this.status,
    required this.chooseRecipient,
  });

  /// Número de orden: pedir otro regalo con el panel abierto cambia el editor.
  final int serial;

  /// El regalo que se edita, o `null` para uno nuevo.
  final Gift? gift;
  final String? recipientId;
  final String? occasionId;
  final String? giverId;

  /// El estado con el que empieza un regalo nuevo, o `null` («Idea»).
  final GiftStatus? status;
  final bool chooseRecipient;

  final Completer<String?> _done = Completer<String?>();
}

/// El panel del editor de regalo del tablero de la web de escritorio
/// (la guía de diseño de escritorio, A): un panel fijo a la derecha
/// que no tapa nada.
///
/// Lo abre `openGiftEditor` cuando hay un [host] (el marco del tablero) y
/// devuelve, como la hoja de siempre, el id del regalo guardado o `null`. Pedir
/// otro regalo con uno abierto lo sustituye (el anterior sin guardar se
/// descarta, como al elegir otra fila en la maqueta).
class GiftEditorPanelController extends ChangeNotifier {
  int _serial = 0;
  int _hosts = 0;
  GiftEditorRequest? _request;

  /// Si hay un marco del tablero que pueda enseñar el panel.
  bool get hosted => _hosts > 0;

  /// Lo que se está editando, o `null` con el panel cerrado.
  GiftEditorRequest? get request => _request;

  /// Si el panel está abierto.
  bool get isOpen => _request != null;

  /// Lo que dice si el formulario abierto tiene cambios sin guardar (lo pone el
  /// editor mientras está en el panel).
  bool Function()? dirtyCheck;

  /// Si el formulario abierto tiene cambios sin guardar.
  bool get isDirty => isOpen && (dirtyCheck?.call() ?? false);

  /// El marco del tablero se monta.
  void attach() => _hosts++;

  /// El marco del tablero se va: lo abierto se cierra sin guardar.
  void detach() {
    _hosts = _hosts > 0 ? _hosts - 1 : 0;
    if (_hosts == 0) {
      final open = _request;
      _request = null;
      if (open != null && !open._done.isCompleted) {
        open._done.complete(null);
      }
    }
  }

  /// Abre el editor. Devuelve el id del regalo guardado, o `null`.
  Future<String?> open({
    Gift? gift,
    String? recipientId,
    String? occasionId,
    String? giverId,
    GiftStatus? status,
    bool chooseRecipient = false,
  }) {
    final previous = _request;
    if (previous != null && !previous._done.isCompleted) {
      previous._done.complete(null);
    }
    final next = GiftEditorRequest._(
      serial: ++_serial,
      gift: gift,
      recipientId: recipientId,
      occasionId: occasionId,
      giverId: giverId,
      status: status,
      chooseRecipient: chooseRecipient,
    );
    _request = next;
    notifyListeners();
    return next._done.future;
  }

  /// Cierra el panel; [result] es el id del regalo guardado, si lo hubo.
  void close([String? result]) {
    final open = _request;
    if (open == null) {
      return;
    }
    _request = null;
    if (!open._done.isCompleted) {
      open._done.complete(result);
    }
    notifyListeners();
  }
}

/// El panel del editor de la sesión.
final giftEditorPanelProvider = Provider<GiftEditorPanelController>((ref) {
  final panel = GiftEditorPanelController();
  ref.onDispose(panel.dispose);
  return panel;
});
