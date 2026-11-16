import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/stagger.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';

/// Las pestañas con dos paneles: de cada una, la ruta de su lista.
enum PaneTab {
  /// Personas.
  people('/people'),

  /// Ocasiones (y Presupuesto, que es una fila más).
  occasions('/occasions'),

  /// Ajustes.
  settings('/settings');

  const PaneTab(this.root);

  /// La ruta de la lista (`/people`).
  final String root;
}

/// La fila elegida de una pestaña: la última que se abrió en la sesión y la
/// que puso la app sin que nadie tocara nada.
class _Choice {
  String? last;
  String? auto;
}

/// Quién está elegido en el panel de lista de Personas, Ocasiones y Ajustes y
/// cuándo lo eligió la app (la guía de diseño para tablet, §3.2).
///
/// La selección es la URL (`/people/:id`, `/occasions/:id`,
/// `/settings/appearance`). Este objeto solo recuerda lo que la URL no dice:
/// - la última fila abierta en la sesión, que es la que se elige al volver a
///   la pestaña con dos paneles;
/// - si la fila de la URL la puso la app (al entrar con dos paneles, sin que
///   nadie tocara nada) o la eligió el usuario: al estrechar la ventana la
///   elegida por la app se quita y se vuelve a la lista, la del usuario se
///   queda con su flecha de volver.
///
/// Y si la ventana tiene dos paneles ahora mismo (lo cuenta `AppShell`), para
/// que el router decida sin tener el tamaño de la ventana.
class PaneSelection {
  /// Si la ventana tiene dos paneles; lo avisa [reportTwoPanes].
  final ValueNotifier<bool> twoPanes = ValueNotifier<bool>(false);

  /// Donde Personas guarda la posición de su lista, para que no se pierda al
  /// pasar de una página a otra (con dos paneles, la lista de `/people` y la
  /// de `/people/:id` son dos).
  final PageStorageBucket listBucket = PageStorageBucket();

  final Map<PaneTab, _Choice> _choices = {
    for (final tab in PaneTab.values) tab: _Choice(),
  };
  final Set<PaneTab> _entered = <PaneTab>{};

  /// La última persona abierta en la sesión.
  String? get lastPerson => _choices[PaneTab.people]!.last;
  set lastPerson(String? id) => _choices[PaneTab.people]!.last = id;

  /// La persona que puso la app, mientras nadie haya elegido otra.
  String? get autoPerson => _choices[PaneTab.people]!.auto;
  set autoPerson(String? id) => _choices[PaneTab.people]!.auto = id;

  /// La última fila abierta de [tab] en la sesión.
  String? lastOf(PaneTab tab) => _choices[tab]!.last;

  bool _scheduled = false;
  bool _disposed = false;

  /// Cuenta si la ventana tiene dos paneles. Se aplica al acabar el
  /// fotograma: se llama desde `build` y avisa al router, que no se puede
  /// tocar a mitad de una construcción.
  void reportTwoPanes(bool value) {
    if (value == twoPanes.value || _scheduled) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) {
        twoPanes.value = value;
      }
    });
  }

  /// El usuario ha tocado a [id]: la selección deja de ser de la app.
  void userChose(String id) => choose(PaneTab.people, id);

  /// El usuario ha elegido la fila [id] de [tab].
  void choose(PaneTab tab, String id) {
    final choice = _choices[tab]!;
    choice.last = id;
    choice.auto = null;
  }

  /// Si [tab] tiene que hacer su entrada escalonada (la lista, el detalle y la
  /// tercera columna, una detrás de otra): solo la primera vez que se ve con
  /// dos paneles en la sesión. Contarla la gasta.
  bool takeEntrance(PaneTab tab) => _entered.add(tab);

  /// A dónde lleva el router a quien llega a [location] (la ruta, sin
  /// consulta) con la lista de [personIds] a la vista, o `null` si se queda.
  ///
  /// - `/people` con dos paneles: a la última persona abierta o, si no hay, a
  ///   la primera. La elige la app.
  /// - `/people/:id` sin dos paneles y elegida por la app: de vuelta a
  ///   `/people`.
  /// - `/people/:id` en cualquier otro caso: la anota como última abierta.
  String? redirectPeople(String location, List<String> personIds) =>
      redirectTab(PaneTab.people, location, personIds);

  /// Lo mismo que [redirectPeople] para cualquier pestaña: [ids] son las filas
  /// que se pueden elegir (por orden) y [fallback] la que se elige si no hay
  /// última (por defecto, la primera). `/occasions/budget` y los apartados de
  /// Ajustes (`/settings/appearance`) son filas más, con su segmento como id.
  String? redirectTab(
    PaneTab tab,
    String location,
    List<String> ids, {
    String? fallback,
  }) {
    final choice = _choices[tab]!;
    final root = tab.root;
    if (location == root) {
      if (!twoPanes.value || ids.isEmpty) {
        return null;
      }
      final last = choice.last;
      final target = last != null && ids.contains(last)
          ? last
          : (fallback != null && ids.contains(fallback) ? fallback : ids.first);
      choice.auto = target;
      choice.last = target;
      return '$root/${Uri.encodeComponent(target)}';
    }
    final segments = Uri.parse(location).pathSegments;
    if (segments.length != 2 || '/${segments.first}' != root) {
      return null;
    }
    final id = segments[1];
    if (!twoPanes.value && choice.auto == id) {
      choice.auto = null;
      return root;
    }
    if (choice.auto != id) {
      choice.auto = null;
    }
    choice.last = id;
    return null;
  }

  /// Suelta el aviso a los oyentes.
  void dispose() {
    _disposed = true;
    twoPanes.dispose();
  }
}

/// La selección de los paneles de la sesión.
final paneSelectionProvider = Provider<PaneSelection>((ref) {
  final selection = PaneSelection();
  ref.onDispose(selection.dispose);
  return selection;
});

/// Lo que dura el viaje del recuadro de selección de una fila a otra.
const Duration kSelectionTravel = Duration(milliseconds: 160);

/// El muelle del recuadro: crítico, sin rebote (rigidez 900, amortiguación
/// 60), asentado en unos 160 ms. La navegación de escritorio tiene que
/// notarse inmediata (la guía de diseño de escritorio, §3).
const SpringDescription kSelectionSpring = SpringDescription(
  mass: 1,
  stiffness: 900,
  damping: 60,
);

/// El recuadro de selección que viaja entre las filas de un panel de lista
/// (§4.1 del plan de tablet).
///
/// Envuelve las filas y pinta, detrás de ellas, un rectángulo de radio 8 con el
/// [fill] de la fila elegida y un borde de 1 px de [border]. Cada fila se da
/// de alta envolviéndose en un [SelectionRow] con su id; el recuadro mide la
/// de [selectedId] al pintar, así que sigue a la fila aunque cambie de alto o
/// se desplace el panel.
///
/// Al cambiar [selectedId] viaja de una fila a la otra con un muelle de
/// 160 ms, y el color pasa de un pastel al otro. Con «Reducir movimiento» no
/// viaja: aparece en la fila nueva con un fundido de 150 ms. Sin [selectedId]
/// (móvil, tablet en vertical) no pinta nada y las filas no cambian.
///
/// Las filas tienen que dejar su fondo transparente cuando están elegidas, o
/// taparían el recuadro.
class SelectionScope extends StatefulWidget {
  /// Crea el recuadro alrededor de [child].
  const SelectionScope({
    super.key,
    required this.selectedId,
    required this.fill,
    required this.border,
    required this.child,
  });

  /// El id de la fila elegida, o `null` si no hay recuadro.
  final Object? selectedId;

  /// El fondo de la fila elegida.
  final Color fill;

  /// El borde de 1 px de la fila elegida.
  final Color border;

  /// Las filas.
  final Widget child;

  @override
  State<SelectionScope> createState() => _SelectionScopeState();
}

class _SelectionScopeState extends State<SelectionScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: kSelectionTravel,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final Map<Object, BuildContext> _rows = <Object, BuildContext>{};
  late final SpringCurve _curve = SpringCurve(
    kSelectionSpring,
    kSelectionTravel,
  );

  // De dónde parte el viaje: el rectángulo y los colores de la fila anterior.
  Rect? _fromRect;
  Color? _fromFill;
  Color? _fromBorder;
  bool _repaintScheduled = false;

  // La entrada escalonada de la pantalla, si la hay. Las filas que entran se
  // mueven en capas propias: el fotograma en el que se asientan repinta la
  // fila pero no el recuadro, que se quedaba donde estaba la fila un fotograma
  // antes (unos 4 px más abajo: sin hueco con la fila de debajo y
  // descentrado). El recuadro se repinta con cada fotograma de la entrada,
  // también en sus repeticiones.
  Listenable? _stagger;

  @override
  void initState() {
    super.initState();
    _stagger = StaggerScope.animationOf(context);
  }

  @override
  void didUpdateWidget(SelectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId == widget.selectedId) {
      return;
    }
    final reduce = RegalosMotion.of(context).reduce;
    final oldId = oldWidget.selectedId;
    // Hasta que llega, el recuadro sigue en la fila de la que sale.
    _fromRect = oldId == null || reduce ? null : (_measure(oldId) ?? _fromRect);
    _fromFill = _currentFill ?? oldWidget.fill;
    _fromBorder = _currentBorder ?? oldWidget.border;
    _travel
      ..duration = reduce ? RegalosMotion.fade : kSelectionTravel
      ..forward(from: widget.selectedId == null ? 1 : 0);
  }

  @override
  void dispose() {
    _travel.dispose();
    _repaint.dispose();
    super.dispose();
  }

  Color? get _currentFill =>
      _fromFill == null ? null : Color.lerp(_fromFill, widget.fill, _progress);
  Color? get _currentBorder => _fromBorder == null
      ? null
      : Color.lerp(_fromBorder, widget.border, _progress);

  double get _progress =>
      _travel.isCompleted ? 1 : _curve.transform(_travel.value);

  /// Altas y bajas de las filas.
  void _attach(Object id, BuildContext context) {
    _rows[id] = context;
    _requestRepaint();
  }

  void _detach(Object id, BuildContext context) {
    if (identical(_rows[id], context)) {
      _rows.remove(id);
    }
  }

  /// Vuelve a pintar el recuadro al acabar el fotograma, por si una fila ha
  /// cambiado de sitio o de tamaño sin que cambie la elegida.
  void _requestRepaint() {
    if (_repaintScheduled || !mounted) {
      return;
    }
    _repaintScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _repaintScheduled = false;
      if (mounted) {
        _repaint.value++;
      }
    });
  }

  /// El rectángulo de la fila [id] en las coordenadas del recuadro.
  Rect? _measure(Object id) {
    final row = _rows[id];
    final scope = context.findRenderObject();
    if (row == null || !row.mounted || scope is! RenderBox || !scope.attached) {
      return null;
    }
    final box = row.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: scope) & box.size;
  }

  void _paint(Canvas canvas) {
    final id = widget.selectedId;
    if (id == null) {
      return;
    }
    final target = _measure(id);
    if (target == null) {
      return;
    }
    final reduce = RegalosMotion.of(context).reduce;
    final t = _progress.clamp(0.0, 1.0).toDouble();
    final from = _fromRect;
    Rect rect = target;
    if (from != null && t < 1) {
      rect = Rect.lerp(from, target, t)!;
    }
    final fill = Color.lerp(_fromFill, widget.fill, t) ?? widget.fill;
    final border = Color.lerp(_fromBorder, widget.border, t) ?? widget.border;
    final fade = reduce ? t : 1.0;
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(RegalosShape.cardRadius),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = fill.withValues(alpha: fill.a * fade),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = border.withValues(alpha: border.a * fade),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SelectionInherited(
      state: this,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SelectionPainter(
                  this,
                  Listenable.merge([_travel, _repaint, ?_stagger]),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this._state, Listenable repaint) : super(repaint: repaint);

  final _SelectionScopeState _state;

  @override
  void paint(Canvas canvas, Size size) => _state._paint(canvas);

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) => true;
}

class _SelectionInherited extends InheritedWidget {
  const _SelectionInherited({required this.state, required super.child});

  final _SelectionScopeState state;

  @override
  bool updateShouldNotify(_SelectionInherited oldWidget) => false;
}

/// Una fila de un [SelectionScope]: se da de alta con su [id] para que el
/// recuadro la encuentre. Sin recuadro por encima no hace nada.
class SelectionRow extends StatefulWidget {
  /// Crea la fila.
  const SelectionRow({super.key, required this.id, required this.child});

  /// El id con el que el recuadro la busca.
  final Object id;

  final Widget child;

  @override
  State<SelectionRow> createState() => _SelectionRowState();
}

class _SelectionRowState extends State<SelectionRow> {
  _SelectionScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope?._detach(widget.id, context);
    _scope = context
        .getInheritedWidgetOfExactType<_SelectionInherited>()
        ?.state;
  }

  @override
  void didUpdateWidget(SelectionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _scope?._detach(oldWidget.id, context);
    }
  }

  @override
  void dispose() {
    _scope?._detach(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scope?._attach(widget.id, context);
    return widget.child;
  }
}
