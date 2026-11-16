import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_tokens.dart';

/// Los ids de lo que el usuario acaba de borrar, para que [AnimatedRows] use
/// la salida de borrado (tinte, desplazamiento y plegado de 220 ms) y no el
/// pliegue normal de un filtro (§2.10 de la guía de movimiento).
///
/// La acción de borrar rellena el conjunto *antes* de borrar el dato; las
/// filas lo vacían al terminar de salir.
class RecentlyDeleted extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  /// Apunta [id] como borrado ahora mismo.
  void add(String id) => state = {...state, id};

  /// Quita [id] (la fila ya salió).
  void clear(String id) {
    if (state.contains(id)) {
      state = {...state}..remove(id);
    }
  }
}

/// Dónde se apunta lo recién borrado.
final recentlyDeletedProvider = NotifierProvider<RecentlyDeleted, Set<String>>(
  RecentlyDeleted.new,
);

/// Una fila de [AnimatedRows]: su [id] estable y su contenido.
@immutable
class AnimatedRowItem {
  /// Crea la fila.
  const AnimatedRowItem({required this.id, required this.child});

  /// Identifica la fila entre un cambio y el siguiente (su clave).
  final String id;

  /// El contenido.
  final Widget child;
}

/// Una columna de filas que se despliegan al llegar y se pliegan al irse
/// (§2.6 de la guía de movimiento).
///
/// Compara las filas con las del cambio anterior por [AnimatedRowItem.id]:
/// - las que llegan se despliegan con `snap` (altura y fundido, 375 ms);
/// - las que se van se pliegan con `fold` en 180 ms y luego se quitan;
/// - las que están en [deleted] (un borrado, no un filtro) se tiñen de
///   rojo claro en 90 ms, se desplazan 16 px a la izquierda y se pliegan en
///   220 ms con `fold`;
/// - con [quiet] (cambios que llegan por sincronización) las filas entran
///   solo con fundido `soft`, sin desplegarse ni rebotar;
/// - la primera vez no se anima nada.
///
/// Con «Reducir movimiento» las filas aparecen y desaparecen con un fundido
/// de 150 ms, sin cambiar de altura.
class AnimatedRows extends StatefulWidget {
  /// Crea la columna.
  const AnimatedRows({
    super.key,
    required this.rows,
    this.deleted = const <String>{},
    this.quiet = false,
    this.onDeletedGone,
    this.exitChildren = const <String, Widget>{},
    this.leaveDelay = const Duration(milliseconds: 250),
  });

  /// Las filas, en orden.
  final List<AnimatedRowItem> rows;

  /// Los ids que se acaban de borrar.
  final Set<String> deleted;

  /// Si el cambio llegó por sincronización: entran solo con fundido `soft`.
  final bool quiet;

  /// Se llama con el id de una fila borrada cuando acabó de salir.
  final ValueChanged<String>? onDeletedGone;

  /// Lo que enseña, por id, una fila que sale por un cambio (no por un
  /// borrado): su contenido ya con el cambio que la saca de esta lista (por
  /// ejemplo, la casilla ya en «comprado»). Si hay uno, la fila lo recibe, lo
  /// enseña [leaveDelay] y entonces se pliega.
  final Map<String, Widget> exitChildren;

  /// Cuánto se ve el último cambio de una fila que sale con [exitChildren].
  final Duration leaveDelay;

  @override
  State<AnimatedRows> createState() => _AnimatedRowsState();
}

enum _Mode { stable, entering, enteringQuiet, leaving, leavingDelete }

class _Entry {
  _Entry(this.id, this.child, this.mode);

  final String id;
  Widget child;
  _Mode mode;
  Duration delay = Duration.zero;
}

class _AnimatedRowsState extends State<AnimatedRows> {
  late List<_Entry> _entries = [
    for (final r in widget.rows) _Entry(r.id, r.child, _Mode.stable),
  ];

  @override
  void didUpdateWidget(AnimatedRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    final known = {for (final e in _entries) e.id: e};
    final next = <_Entry>[];
    for (final row in widget.rows) {
      final existing = known[row.id];
      if (existing == null) {
        next.add(
          _Entry(
            row.id,
            row.child,
            widget.quiet ? _Mode.enteringQuiet : _Mode.entering,
          ),
        );
        continue;
      }
      existing.child = row.child;
      if (existing.mode == _Mode.leaving ||
          existing.mode == _Mode.leavingDelete) {
        // Volvió (Deshacer) mientras se plegaba.
        existing.delay = Duration.zero;
        existing.mode = widget.quiet ? _Mode.enteringQuiet : _Mode.entering;
      }
      next.add(existing);
    }
    // Las que se van se quedan detrás de la fila que tenían delante.
    final newIds = {for (final r in widget.rows) r.id};
    for (var i = 0; i < _entries.length; i++) {
      final gone = _entries[i];
      if (newIds.contains(gone.id)) {
        continue;
      }
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final before = next.indexOf(_entries[j]);
        if (before >= 0) {
          at = before + 1;
          break;
        }
      }
      next.insert(at, _leaving(gone));
    }
    _entries = next;
  }

  _Entry _leaving(_Entry e) {
    if (e.mode != _Mode.leaving && e.mode != _Mode.leavingDelete) {
      final deleted = widget.deleted.contains(e.id);
      e.mode = deleted ? _Mode.leavingDelete : _Mode.leaving;
      final exit = widget.exitChildren[e.id];
      if (!deleted && exit != null) {
        e.child = exit;
        e.delay = widget.leaveDelay;
      }
    }
    return e;
  }

  void _settled(String id) {
    if (!mounted) {
      return;
    }
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry != null &&
        (entry.mode == _Mode.entering || entry.mode == _Mode.enteringQuiet)) {
      setState(() => entry.mode = _Mode.stable);
    }
  }

  void _gone(String id) {
    if (!mounted) {
      return;
    }
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry == null ||
        (entry.mode != _Mode.leaving && entry.mode != _Mode.leavingDelete)) {
      return;
    }
    setState(() => _entries.remove(entry));
    widget.onDeletedGone?.call(id);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final e in _entries)
        _AnimatedRow(
          key: ValueKey(e.id),
          mode: e.mode,
          onGone: () => _gone(e.id),
          onSettled: () => _settled(e.id),
          leaveDelay: e.delay,
          child: e.child,
        ),
    ],
  );
}

class _AnimatedRow extends StatefulWidget {
  const _AnimatedRow({
    super.key,
    required this.mode,
    required this.onGone,
    required this.onSettled,
    required this.leaveDelay,
    required this.child,
  });

  final _Mode mode;
  final VoidCallback onGone;

  /// La entrada terminó: la fila pasa a `stable`.
  final VoidCallback onSettled;

  /// Cuánto espera una fila que se va antes de plegarse (para que se vea su
  /// último cambio).
  final Duration leaveDelay;
  final Widget child;

  @override
  State<_AnimatedRow> createState() => _AnimatedRowState();
}

class _AnimatedRowState extends State<_AnimatedRow>
    with SingleTickerProviderStateMixin {
  static const Duration _deleteDuration = Duration(milliseconds: 310);
  static const double _tintShare = 90 / 310;

  // La presencia de la fila: 1 es entera y 0 es plegada. Es el valor que se ve
  // (la altura y la opacidad), así que invertir a medias parte de lo que se
  // ve y conserva la velocidad.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_onStatus);
  bool _reduce = false;
  bool _initialized = false;

  bool get _leaving =>
      widget.mode == _Mode.leaving || widget.mode == _Mode.leavingDelete;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = RegalosMotion.of(context).reduce;
    if (!_initialized) {
      _initialized = true;
      _apply(widget.mode, first: true);
    }
  }

  @override
  void didUpdateWidget(_AnimatedRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _apply(widget.mode, previous: oldWidget.mode);
    }
  }

  /// La presencia que se ve ahora con el modo [mode] (en un borrado el valor
  /// del controlador es tiempo, no altura).
  double _visible(_Mode mode, double v) {
    if (mode == _Mode.leavingDelete && !_reduce) {
      final e = 1 - v;
      final fold = ((e - _tintShare) / (1 - _tintShare)).clamp(0.0, 1.0);
      return 1 - RegalosCurves.fold.transform(fold);
    }
    return v;
  }

  void _apply(_Mode mode, {bool first = false, _Mode? previous}) {
    final velocity = _controller.isAnimating ? _controller.velocity : 0.0;
    if (previous == _Mode.leavingDelete) {
      // Deshacer a mitad de un borrado: se parte de la altura que se ve.
      _controller.value = _visible(previous!, _controller.value);
    }
    switch (mode) {
      case _Mode.stable:
        break;
      case _Mode.entering:
      case _Mode.enteringQuiet:
        if (first) {
          _controller.value = 0;
        }
        if (_reduce) {
          _controller.animateTo(
            1,
            duration: RegalosMotion.fade,
            curve: Curves.linear,
          );
        } else if (mode == _Mode.entering) {
          // El muelle sigue desde donde esté y con la velocidad que llevara.
          _controller.animateWith(
            SpringSimulation(
              RegalosSprings.snap,
              _controller.value,
              1,
              first ? 0 : velocity,
              snapToEnd: true,
            ),
          );
        } else {
          _controller.animateTo(
            1,
            duration: RegalosSprings.softDuration,
            curve: RegalosCurves.soft,
          );
        }
      case _Mode.leaving:
        final fold = _reduce ? RegalosMotion.fade : RegalosCurves.foldDuration;
        final wait = _reduce ? Duration.zero : widget.leaveDelay;
        if (wait == Duration.zero) {
          _controller.animateBack(
            0,
            duration: fold,
            curve: _reduce ? Curves.linear : RegalosCurves.fold,
          );
        } else {
          // La espera va en la curva: la fila se queda entera, enseñando su
          // último cambio, y luego se pliega.
          final total = wait + fold;
          _controller.animateBack(
            0,
            duration: total,
            curve: Interval(
              wait.inMicroseconds / total.inMicroseconds,
              1,
              curve: RegalosCurves.fold,
            ),
          );
        }
      case _Mode.leavingDelete:
        _controller
          ..value = _reduce ? _controller.value : 1
          ..animateBack(
            0,
            duration: _reduce ? RegalosMotion.fade : _deleteDuration,
            curve: Curves.linear,
          );
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _leaving) {
      widget.onGone();
    } else if (status == AnimationStatus.completed &&
        (widget.mode == _Mode.entering || widget.mode == _Mode.enteringQuiet)) {
      // Entera: deja de ser una fila que entra (si no, su recorte seguiría
      // cortando lo que la mueva, como un reorden).
      widget.onSettled();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final mode = widget.mode;
        final leaving = _leaving;
        final v = _controller.value.clamp(0.0, 1.0);
        // Siempre la misma estructura, para no desmontar la fila; en reposo
        // todo es neutro (sin altura fija, opacidad 1, sin recorte).
        double? height;
        var opacity = 1.0;
        var tint = 0.0;
        var fold = 0.0;
        if (_reduce || mode == _Mode.enteringQuiet) {
          // Solo se funde: la fila conserva su altura.
          opacity = v;
        } else if (mode == _Mode.leavingDelete) {
          final e = 1 - v;
          tint = (e / _tintShare).clamp(0.0, 1.0);
          fold = ((e - _tintShare) / (1 - _tintShare)).clamp(0.0, 1.0);
          height = opacity = 1 - RegalosCurves.fold.transform(fold);
        } else if (v < 1) {
          height = opacity = v;
        }
        final rowTint = tint > 0
            ? RegalosTokens.of(context).dangerRow
            : const Color(0x00000000);
        return IgnorePointer(
          ignoring: leaving,
          child: ExcludeSemantics(
            excluding: leaving,
            child: ClipRect(
              clipBehavior: height == null ? Clip.none : Clip.hardEdge,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                heightFactor: height?.clamp(0.0, 1.0),
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(-16 * fold, 0),
                    child: ColoredBox(
                      color: Color.lerp(
                        rowTint.withValues(alpha: 0),
                        rowTint,
                        tint,
                      )!,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
