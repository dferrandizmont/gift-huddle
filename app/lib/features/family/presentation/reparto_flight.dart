import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import 'reparto_grid.dart' show RepartoAvatar;

/// El escenario de una vista de Reparto durante el cambio entre la rejilla y
/// la lista por ocasión (README, «Transición rejilla ↔ por ocasión»).
///
/// `Hero` solo vuela entre rutas, así que el viaje va a mano: cada vista
/// marca con una `GlobalKey` los sitios de sus regalos (anclas), el cambio
/// lee sus rectángulos y un `OverlayEntry` mueve un trozo por regalo del
/// origen al destino. Mientras tanto, los destinos se ocultan hasta que
/// aterriza su regalo.
///
/// Cada instancia de una vista tiene su propio escenario, así que nunca
/// coinciden dos `GlobalKey` iguales aunque la vista que se va y la que llega
/// estén a la vez en el árbol.
class RepartoStage {
  /// Crea un escenario; [hidden] son las anclas que empiezan ocultas.
  RepartoStage({Set<String> hidden = const <String>{}})
    : hidden = ValueNotifier<Set<String>>(hidden);

  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  final Map<String, VoidCallback> _landings = <String, VoidCallback>{};
  final Set<String> _fadeIn = <String>{};

  /// Las anclas que no se pintan (el regalo aún no ha llegado).
  final ValueNotifier<Set<String>> hidden;

  /// La clave del ancla [id] (se crea la primera vez).
  GlobalKey key(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  /// El rectángulo en pantalla del ancla [id], o `null` si no está pintada.
  Rect? rect(String id) {
    final box = _keys[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Qué hace el ancla [id] cuando le llega el último regalo (la celda
  /// rebota). Lo registra el widget del ancla y lo retira al irse.
  void onLanding(String id, VoidCallback? callback) {
    if (callback == null) {
      _landings.remove(id);
    } else {
      _landings[id] = callback;
    }
  }

  /// Muestra el ancla [id] y avisa de que ha llegado su regalo.
  void land(String id) {
    if (hidden.value.contains(id)) {
      hidden.value = {...hidden.value}..remove(id);
    }
    _landings[id]?.call();
  }

  /// Muestra el ancla [id] porque no le llega nada: con [fade] se funde en
  /// 150 ms en vez de aparecer de golpe (un nombre o un regalo sin origen).
  void reveal(String id, {bool fade = false}) {
    if (hidden.value.contains(id)) {
      if (fade) {
        _fadeIn.add(id);
      }
      hidden.value = {...hidden.value}..remove(id);
    }
  }

  /// Si el ancla [id] debe fundirse al mostrarse (y lo consume).
  bool takeFade(String id) => _fadeIn.remove(id);

  /// Libera los avisos.
  void dispose() => hidden.dispose();
}

/// El ancla del nombre de una persona que recibe (su fila en la rejilla, su
/// tarjeta en la lista por ocasión).
String repartoNameAnchor(String recipientId) => 'name:$recipientId';

/// El ancla del avatar de una persona que recibe.
String repartoAvatarAnchor(String recipientId) => 'avatar:$recipientId';

/// El ancla de la línea «Sin Navidad» bajo el nombre de una persona: no viaja,
/// pero se funde cuando llega su nombre.
String repartoSkipAnchor(String recipientId) => 'skip:$recipientId';

/// El ancla de la etiqueta «Yo» junto al nombre de la persona dueña de este
/// móvil: no viaja, pero se funde cuando llega su nombre.
String repartoSelfAnchor(String recipientId) => 'self:$recipientId';

/// El estilo del nombre de una persona en la rejilla.
TextStyle repartoGridNameStyle(RegalosTokens t) =>
    t.styles.metaStrong.copyWith(fontWeight: FontWeight.w600, height: 1.15);

/// El estilo del nombre de una persona en la cabecera de su tarjeta.
TextStyle repartoCardNameStyle(RegalosTokens t) =>
    t.styles.body.copyWith(fontWeight: FontWeight.w700);

/// Marca [child] como el ancla [id] del [stage] y lo oculta mientras el
/// escenario lo pida. Sin escenario no hace nada.
///
/// Un ancla que se muestra sin que le llegue nada (su origen no se ve) puede
/// fundirse en 150 ms ([RepartoStage.reveal] con `fade`); la que recibe un
/// vuelo aparece de golpe, justo debajo de lo que aterriza.
class RepartoAnchor extends StatefulWidget {
  /// Crea el ancla.
  const RepartoAnchor({
    super.key,
    required this.stage,
    required this.id,
    required this.child,
  });

  /// El escenario de la vista.
  final RepartoStage? stage;

  /// El nombre del ancla (`cell:persona|quien`, `gift:id`...).
  final String id;

  /// El contenido.
  final Widget child;

  @override
  State<RepartoAnchor> createState() => _RepartoAnchorState();
}

class _RepartoAnchorState extends State<RepartoAnchor>
    with SingleTickerProviderStateMixin {
  /// Opacidad del contenido: 0 mientras está oculto, 1 cuando se ve.
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: RegalosMotion.fade,
    value: 1,
  );
  RepartoStage? _stage;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.stage);
  }

  @override
  void didUpdateWidget(RepartoAnchor old) {
    super.didUpdateWidget(old);
    if (old.stage != widget.stage || old.id != widget.id) {
      _attach(widget.stage);
    }
  }

  void _attach(RepartoStage? stage) {
    _stage?.hidden.removeListener(_sync);
    _stage = stage;
    stage?.hidden.addListener(_sync);
    _hidden = stage?.hidden.value.contains(widget.id) ?? false;
    _opacity.value = _hidden ? 0 : 1;
  }

  void _sync() {
    final stage = _stage;
    if (stage == null) {
      return;
    }
    final hidden = stage.hidden.value.contains(widget.id);
    if (hidden == _hidden) {
      return;
    }
    _hidden = hidden;
    if (hidden) {
      _opacity.value = 0;
    } else if (stage.takeFade(widget.id)) {
      _opacity.forward(from: 0);
    } else {
      _opacity.value = 1;
    }
  }

  @override
  void dispose() {
    _stage?.hidden.removeListener(_sync);
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stage;
    if (s == null) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: KeyedSubtree(key: s.key(widget.id), child: widget.child),
    );
  }
}

/// Dice a los bloques de una vista si deben entrar escalonados (porque la
/// vista acaba de llegar con el cambio de vista) o aparecer sin más.
class RepartoEntrance extends InheritedWidget {
  /// Crea el aviso.
  const RepartoEntrance({
    super.key,
    required this.active,
    required super.child,
  });

  /// Si los bloques que se pinten ahora deben entrar escalonados.
  final bool active;

  /// Si hay entrada escalonada en este contexto.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepartoEntrance>()?.active ??
      false;

  @override
  bool updateShouldNotify(RepartoEntrance old) => old.active != active;
}

/// Un bloque de una vista que, tras un cambio de vista, entra escalonado:
/// 16 ms de retraso por bloque, `translateY` 8 → 0 y opacidad con el muelle
/// `flight`. Con «Reducir movimiento», solo se funde en 150 ms.
class RepartoBlock extends StatefulWidget {
  /// Crea el bloque; [index] es su posición en el escalonado.
  const RepartoBlock({
    super.key,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  /// Posición del bloque (el retraso es de 16 ms por posición, hasta 14).
  final int index;

  /// El contenido.
  final Widget child;

  /// Si este bloque entra escalonado; los que sirven de destino a un vuelo
  /// no se mueven (su rectángulo se lee en el primer fotograma).
  final bool enabled;

  @override
  State<RepartoBlock> createState() => _RepartoBlockState();
}

class _RepartoBlockState extends State<RepartoBlock>
    with SingleTickerProviderStateMixin {
  static const int _baseDelayMs = 40;
  static const int _stepMs = 16;
  AnimationController? _controller;
  bool _decided = false;
  bool _reduce = false;
  int _delayMs = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Solo se decide la primera vez: los bloques que ya estaban no entran.
    if (_decided) {
      return;
    }
    _decided = true;
    if (!widget.enabled || !RepartoEntrance.of(context)) {
      return;
    }
    _reduce = RegalosMotion.of(context).reduce;
    _delayMs = _reduce
        ? 0
        : _baseDelayMs + math.min(widget.index, 14) * _stepMs;
    final total = _reduce
        ? RegalosMotion.fade.inMilliseconds
        : _delayMs + RegalosSprings.flightDuration.inMilliseconds;
    _controller = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
      duration: Duration(milliseconds: total),
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) {
        if (c.isCompleted) {
          return child!;
        }
        if (_reduce) {
          return Opacity(opacity: c.value, child: child);
        }
        final elapsed = c.value * c.duration!.inMilliseconds;
        final t =
            ((elapsed - _delayMs) /
                    RegalosSprings.flightDuration.inMilliseconds)
                .clamp(0.0, 1.0);
        final s = RegalosCurves.flight.transform(t);
        return Opacity(
          opacity: s.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - s)),
            child: child,
          ),
        );
      },
    );
  }
}

/// La entrada escalonada de la columna de una persona que recibe (avatar y
/// nombre) en la rejilla: `translateY` 8 → 0 y opacidad con el muelle
/// `flight`, 16 ms de retraso por fila, como las celdas.
///
/// Entra al montarse si [onMount] (la primera vez que se ve la rejilla, o al
/// volver de la lista por ocasión cuando no hay vuelo de nombres) y se repite
/// cuando cambia [trigger] (el filtro de ocasión), esta vez con el muelle
/// `soft` de las celdas que se refrescan y sin partir de la nada. Con
/// «Reducir movimiento», solo se funde en 150 ms.
class RepartoRowIntro extends StatefulWidget {
  /// Crea la entrada; [index] es la posición de la fila en el escalonado.
  const RepartoRowIntro({
    super.key,
    required this.index,
    required this.trigger,
    required this.onMount,
    required this.child,
  });

  /// Posición de la fila (16 ms de retraso por posición, hasta 14).
  final int index;

  /// Lo que, al cambiar, repite la entrada (el filtro de ocasión).
  final Object? trigger;

  /// Si la fila entra al montarse.
  final bool onMount;

  /// El contenido.
  final Widget child;

  /// El retraso con el que entra la fila [row], en ms.
  static int delayMs(int row) => 40 + math.min(row, 14) * 16;

  @override
  State<RepartoRowIntro> createState() => _RepartoRowIntroState();
}

class _RepartoRowIntroState extends State<RepartoRowIntro>
    with SingleTickerProviderStateMixin {
  static const int _baseDelayMs = 40;
  static const int _stepMs = 16;
  AnimationController? _controller;
  bool _decided = false;
  bool _reduce = false;
  bool _refresh = false;
  int _delayMs = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) {
      return;
    }
    _decided = true;
    if (widget.onMount) {
      _play(refresh: false);
    }
  }

  @override
  void didUpdateWidget(RepartoRowIntro old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _play(refresh: true);
    }
  }

  void _play({required bool refresh}) {
    _reduce = RegalosMotion.of(context).reduce;
    _refresh = refresh;
    final spring = refresh
        ? RegalosSprings.softDuration
        : RegalosSprings.flightDuration;
    _delayMs = _reduce
        ? 0
        : _baseDelayMs + math.min(widget.index, 14) * _stepMs;
    final total = _reduce
        ? RegalosMotion.fade.inMilliseconds
        : _delayMs + spring.inMilliseconds;
    final c = _controller ??= AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
    );
    c
      ..duration = Duration(milliseconds: total)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) {
        if (c.isCompleted) {
          return child!;
        }
        if (_reduce) {
          return Opacity(opacity: c.value, child: child);
        }
        final spring = _refresh
            ? RegalosSprings.softDuration
            : RegalosSprings.flightDuration;
        final elapsed = c.value * c.duration!.inMilliseconds;
        final t = ((elapsed - _delayMs) / spring.inMilliseconds).clamp(
          0.0,
          1.0,
        );
        final s = (_refresh ? RegalosCurves.soft : RegalosCurves.flight)
            .transform(t);
        // Al repetirse por el filtro, el nombre no desaparece: baja a 0,3 y
        // vuelve, como las celdas.
        final from = _refresh ? 0.3 : 0.0;
        return Opacity(
          opacity: (from + (1 - from) * s).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - s)),
            child: child,
          ),
        );
      },
    );
  }
}

/// La entrada de una celda de la rejilla: llega tras el nombre de su fila y
/// de izquierda a derecha, como una onda que baja en diagonal por la
/// rejilla. `translateY` 8 → 0 y opacidad con el muelle `flight`; las celdas
/// con regalos ([landing]) además aterrizan: crecen de 0,88 a 1 con el muelle
/// `bounce`, con un rebote leve. Las vacías solo se asientan (0,96 → 1).
///
/// Entra al montarse si [onMount] (la primera vez que se ve la rejilla, o al
/// volver de la lista por ocasión cuando la celda no espera un vuelo) y se
/// repite cuando cambia [trigger] (el filtro de ocasión), sin partir de la
/// nada: baja a 0,3 y vuelve. Con «Reducir movimiento», solo se funde en
/// 150 ms. Nunca bloquea los toques: es solo pintura.
class RepartoCellIntro extends StatefulWidget {
  /// Crea la entrada; [row] y [column] fijan su sitio en la onda.
  const RepartoCellIntro({
    super.key,
    required this.row,
    required this.column,
    required this.trigger,
    required this.onMount,
    required this.landing,
    required this.child,
  });

  /// Fila de la celda (16 ms de retraso por fila, hasta 14).
  final int row;

  /// Columna de la celda (20 ms más por columna, hasta 8).
  final int column;

  /// Lo que, al cambiar, repite la entrada (el filtro de ocasión).
  final Object? trigger;

  /// Si la celda entra al montarse.
  final bool onMount;

  /// Si la celda tiene regalos (aterriza con rebote).
  final bool landing;

  /// El contenido.
  final Widget child;

  /// El retraso con el que entra la celda [column] de la fila [row], en ms.
  static int delayMs(int row, int column) =>
      RepartoRowIntro.delayMs(row) + 30 + math.min(column, 8) * 20;

  @override
  State<RepartoCellIntro> createState() => _RepartoCellIntroState();
}

class _RepartoCellIntroState extends State<RepartoCellIntro>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;
  bool _reduce = false;
  bool _refresh = false;
  int _delayMs = 0;
  late int _flightMs;
  late int _bounceMs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) {
      return;
    }
    _decided = true;
    if (widget.onMount) {
      _play(refresh: false);
    }
  }

  @override
  void didUpdateWidget(RepartoCellIntro old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _play(refresh: true);
    }
  }

  void _play({required bool refresh}) {
    _reduce = RegalosMotion.of(context).reduce;
    _refresh = refresh;
    _flightMs =
        (refresh ? RegalosSprings.softDuration : RegalosSprings.flightDuration)
            .inMilliseconds;
    _bounceMs = RegalosSprings.bounceDuration.inMilliseconds;
    _delayMs = _reduce
        ? 0
        : RepartoCellIntro.delayMs(widget.row, widget.column);
    final settle = widget.landing && _bounceMs > _flightMs
        ? _bounceMs
        : _flightMs;
    final total = _reduce
        ? RegalosMotion.fade.inMilliseconds
        : _delayMs + settle;
    final c = _controller ??= AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
    );
    c
      ..duration = Duration(milliseconds: total)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) {
        if (c.isCompleted || c.isDismissed) {
          return child!;
        }
        if (_reduce) {
          return Opacity(opacity: c.value, child: child);
        }
        final elapsed = c.value * c.duration!.inMilliseconds - _delayMs;
        final tf = (elapsed / _flightMs).clamp(0.0, 1.0);
        final s = (_refresh ? RegalosCurves.soft : RegalosCurves.flight)
            .transform(tf);
        final from = _refresh ? 0.3 : 0.0;
        final double scale;
        if (widget.landing) {
          final tb = (elapsed / _bounceMs).clamp(0.0, 1.0);
          scale = 0.88 + 0.12 * RegalosCurves.bounce.transform(tb);
        } else {
          scale = 0.96 + 0.04 * s;
        }
        return Opacity(
          opacity: (from + (1 - from) * s).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - s)),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

/// Un regalo que viaja: de [from] a [to], con su pastel y su título.
class RepartoFlyer {
  /// Crea un regalo que viaja.
  const RepartoFlyer({
    required this.giftId,
    required this.landId,
    required this.from,
    required this.to,
    required this.fill,
    required this.title,
  });

  /// El regalo.
  final String giftId;

  /// El ancla de destino que se muestra cuando aterriza.
  final String landId;

  /// Rectángulo de salida, en pantalla.
  final Rect from;

  /// Rectángulo de llegada, en pantalla.
  final Rect to;

  /// El pastel de la persona que recibe (el color del vuelo desde la celda).
  final Color fill;

  /// El título del regalo, que se ve en la fila.
  final String title;
}

/// El nombre o el avatar de una persona que recibe, que viaja de su fila en
/// la rejilla a su tarjeta en la lista por ocasión (o al revés).
class RepartoPersonFlyer {
  /// Crea un nombre o un avatar que viaja.
  const RepartoPersonFlyer({
    required this.landId,
    required this.order,
    required this.from,
    required this.to,
    required this.name,
    required this.colorIndex,
    required this.avatar,
    required this.fromStyle,
    required this.toStyle,
  });

  /// El ancla de destino que se muestra cuando aterriza.
  final String landId;

  /// Posición de la persona en el escalonado (el avatar y el nombre de la
  /// misma persona salen a la vez).
  final int order;

  /// Rectángulo de salida, en pantalla.
  final Rect from;

  /// Rectángulo de llegada, en pantalla.
  final Rect to;

  /// El nombre de la persona.
  final String name;

  /// Su color.
  final int colorIndex;

  /// Si viaja el avatar (cuadrado) o el nombre.
  final bool avatar;

  /// Estilo del nombre en el origen.
  final TextStyle fromStyle;

  /// Estilo del nombre en el destino.
  final TextStyle toStyle;
}

/// Lanza el vuelo de [flyers] sobre la pantalla (un `OverlayEntry` en la
/// ventana, recortado a [clip]) y devuelve la entrada para poder retirarla.
///
/// [toOccasion] es de la rejilla a la lista (la celda pastel se convierte en
/// fila); a la inversa, la fila se encoge hasta su celda. Cada vuelo usa el
/// muelle `flight` y sale 26 ms después del anterior. [onLanded] se llama
/// cuando aterriza cada regalo y [onDone] cuando acaba todo.
///
/// [people] son los nombres y avatares de quienes reciben: salen a la vez que
/// los regalos, 18 ms después de la persona anterior, con el mismo muelle, y
/// avisan con [onPersonLanded].
///
/// Si la ventana cambia de tamaño a mitad de vuelo (girar la tablet, pantalla
/// partida), los rectángulos ya no valen: el vuelo se acaba en el acto, sin
/// aterrizajes, y avisa con [onDone] al terminar ese fotograma.
OverlayEntry startRepartoFlight(
  BuildContext context, {
  required List<RepartoFlyer> flyers,
  required bool toOccasion,
  required Rect clip,
  required ValueChanged<RepartoFlyer> onLanded,
  required VoidCallback onDone,
  List<RepartoPersonFlyer> people = const <RepartoPersonFlyer>[],
  ValueChanged<RepartoPersonFlyer>? onPersonLanded,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final origin = (overlay.context.findRenderObject()! as RenderBox)
      .localToGlobal(Offset.zero);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FlightLayer(
      key: kRepartoFlightKey,
      flyers: flyers,
      people: people,
      toOccasion: toOccasion,
      origin: origin,
      clip: clip,
      onLanded: onLanded,
      onPersonLanded: onPersonLanded ?? (_) {},
      onDone: () {
        entry.remove();
        entry.dispose();
        onDone();
      },
    ),
  );
  overlay.insert(entry);
  return entry;
}

/// La capa en la que viajan los regalos, nombres y avatares mientras dura el
/// vuelo entre vistas (para las pruebas).
const Key kRepartoFlightKey = ValueKey<String>('repartoFlight');

class _FlightLayer extends StatefulWidget {
  const _FlightLayer({
    super.key,
    required this.flyers,
    required this.people,
    required this.toOccasion,
    required this.origin,
    required this.clip,
    required this.onLanded,
    required this.onPersonLanded,
    required this.onDone,
  });

  final List<RepartoFlyer> flyers;
  final List<RepartoPersonFlyer> people;
  final bool toOccasion;
  final Offset origin;
  final Rect clip;
  final ValueChanged<RepartoFlyer> onLanded;
  final ValueChanged<RepartoPersonFlyer> onPersonLanded;
  final VoidCallback onDone;

  @override
  State<_FlightLayer> createState() => _FlightLayerState();
}

class _FlightLayerState extends State<_FlightLayer>
    with SingleTickerProviderStateMixin {
  static const int _stepMs = 26;
  static const int _personStepMs = 18;
  static const int _fadeOutMs = 140;
  late final AnimationController _controller;
  late final int _totalMs;
  final Set<int> _landed = <int>{};
  final Set<int> _peopleLanded = <int>{};

  /// La ventana con la que salió el vuelo.
  Size? _window;

  /// La ventana cambió a mitad de vuelo: ya no se pinta nada.
  bool _aborted = false;
  bool _done = false;

  /// Cuándo sale una persona (ms desde el principio).
  static int _personStart(RepartoPersonFlyer f) =>
      math.min(f.order, 12) * _personStepMs;

  @override
  void initState() {
    super.initState();
    final flightMs = RegalosSprings.flightDuration.inMilliseconds;
    var lastStart = widget.flyers.isEmpty
        ? 0
        : (widget.flyers.length - 1) * _stepMs;
    for (final f in widget.people) {
      lastStart = math.max(lastStart, _personStart(f));
    }
    _totalMs = lastStart + flightMs + _fadeOutMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
    )..addListener(_tick);
    _controller.forward().whenComplete(_finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = MediaQuery.sizeOf(context);
    final changed = _window != null && _window != window;
    _window = window;
    if (!changed || _aborted || _done) {
      return;
    }
    // Los rectángulos del vuelo son de la ventana de antes. Se corta aquí y
    // la capa se retira al acabar el fotograma: mientras se construye no se
    // puede avisar a la pantalla.
    _aborted = true;
    _controller.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  /// Avisa, una sola vez, de que el vuelo ha terminado (y la capa se retira).
  void _finish() {
    if (_done || !mounted) {
      return;
    }
    _done = true;
    widget.onDone();
  }

  void _tick() {
    final elapsed = _controller.value * _totalMs;
    final flightMs = RegalosSprings.flightDuration.inMilliseconds;
    for (var i = 0; i < widget.flyers.length; i++) {
      if (!_landed.contains(i) && elapsed >= i * _stepMs + flightMs) {
        _landed.add(i);
        widget.onLanded(widget.flyers[i]);
      }
    }
    for (var i = 0; i < widget.people.length; i++) {
      final f = widget.people[i];
      if (!_peopleLanded.contains(i) && elapsed >= _personStart(f) + flightMs) {
        _peopleLanded.add(i);
        widget.onPersonLanded(f);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_aborted) {
      return const SizedBox.shrink();
    }
    final t = RegalosTokens.of(context);
    final titleStyle = t.styles.rowTitleCompact.copyWith(
      fontWeight: FontWeight.w500,
    );
    // Sin `Material` el texto del vuelo saldría subrayado y sin la fuente del
    // tema: el `OverlayEntry` cuelga de la ventana, no de una pantalla.
    return Material(
      type: MaterialType.transparency,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: ClipRect(
            clipper: _RectClipper(widget.clip.shift(-widget.origin)),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final elapsed = _controller.value * _totalMs;
                return Stack(
                  children: [
                    for (var i = 0; i < widget.flyers.length; i++)
                      _flyer(i, widget.flyers[i], elapsed, t, titleStyle),
                    for (final f in widget.people) _person(f, elapsed),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// El avatar o el nombre de una persona: su rectángulo y, en el nombre, su
  /// estilo pasan del origen al destino con el muelle `flight`. Al aterrizar
  /// se funde encima del real, que ya se ve.
  Widget _person(RepartoPersonFlyer f, double elapsed) {
    final flightMs = RegalosSprings.flightDuration.inMilliseconds;
    final local = elapsed - _personStart(f);
    final p = (local / flightMs).clamp(0.0, 1.0);
    final s = RegalosCurves.flight.transform(p);
    final fade = local <= flightMs
        ? 1.0
        : (1 - (local - flightMs) / _fadeOutMs).clamp(0.0, 1.0);
    final rect = Rect.lerp(f.from, f.to, s)!.shift(-widget.origin);
    final Widget face;
    if (f.avatar) {
      face = RepartoAvatar(
        name: f.name,
        colorIndex: f.colorIndex,
        size: math.max(rect.width, 1),
      );
    } else {
      // Sin límite de ancho: el texto viaja entero y no se parte ni se
      // recorta a mitad de camino.
      face = OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Text(
          f.name,
          maxLines: 1,
          softWrap: false,
          style: TextStyle.lerp(f.fromStyle, f.toStyle, s),
        ),
      );
    }
    return Positioned.fromRect(
      rect: rect,
      child: Opacity(opacity: fade, child: face),
    );
  }

  Widget _flyer(
    int i,
    RepartoFlyer f,
    double elapsed,
    RegalosTokens t,
    TextStyle titleStyle,
  ) {
    final flightMs = RegalosSprings.flightDuration.inMilliseconds;
    final local = elapsed - i * _stepMs;
    final p = (local / flightMs).clamp(0.0, 1.0);
    final s = RegalosCurves.flight.transform(p);
    final fade = local <= flightMs
        ? 1.0
        : (1 - (local - flightMs) / _fadeOutMs).clamp(0.0, 1.0);
    final rect = Rect.lerp(f.from, f.to, s)!.shift(-widget.origin);
    final toOccasion = widget.toOccasion;
    final color = toOccasion ? Color.lerp(f.fill, t.bg, s)! : t.bg;
    final radius = toOccasion ? 8 * (1 - s) : 8 * s;
    // La sombra sube y baja: en la ida se apaga; en la vuelta, sube a mitad.
    final lift = (toOccasion ? (1 - s) : math.sin(math.pi * s)).clamp(0.0, 1.0);
    final titleOpacity = toOccasion
        ? ((s - 0.5) / 0.5).clamp(0.0, 1.0)
        : ((0.5 - s) / 0.5).clamp(0.0, 1.0);
    return Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: fade,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius.clamp(0.0, 8.0)),
            border: toOccasion
                ? null
                : Border.all(
                    color: t.chipBorder.withValues(alpha: s.clamp(0.0, 1.0)),
                  ),
            boxShadow: [
              BoxShadow(
                color: t.shadow.withValues(alpha: 0.16 * lift),
                blurRadius: 16 * lift,
                offset: Offset(0, 6 * lift),
              ),
            ],
          ),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: 44,
                  top: 0,
                  bottom: 0,
                  width: math.max(
                    (toOccasion ? f.to : f.from).width - 44 - 12,
                    0,
                  ),
                  child: Opacity(
                    opacity: titleOpacity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        f.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RectClipper extends CustomClipper<Rect> {
  const _RectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClipper old) => old.rect != rect;
}
