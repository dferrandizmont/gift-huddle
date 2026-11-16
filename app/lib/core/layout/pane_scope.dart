import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'content_width.dart';

/// Qué panel es este.
enum PaneRole {
  /// El único panel: el área de contenido entera (la ventana menos el raíl).
  single,

  /// El panel de lista, a la izquierda en dos paneles.
  list,

  /// El panel de detalle, a la derecha en dos paneles.
  detail,

  /// La tercera columna, a la derecha del detalle en escritorio ancho.
  aside,
}

/// Marca un panel y dice a lo que lleva dentro cuánto mide y dónde está.
///
/// Dentro de un panel, `MediaQuery.sizeOf(context).width` da el ancho de la
/// ventana, que ya no es el del sitio disponible (norma 2 del plan de tablet).
/// Lo que antes miraba la ventana para medirse usa [widthOf].
///
/// Sin ningún [PaneScope] por encima, [widthOf], [sizeOf] y [roleOf] contestan
/// con la ventana entera y [PaneRole.single]: los mismos números que
/// `MediaQuery`, así que cambiar una llamada por la otra no mueve nada en el
/// móvil.
///
/// Las hojas viven en la capa raíz, fuera del panel: para centrarlas en él se
/// coge su [PaneAnchor] con [anchorOf] al abrirlas y se pasa a [PaneAligned].
///
/// Tiene que estar siempre en el mismo sitio del árbol (también en compacto):
/// si se monta y se desmonta al cruzar un punto de corte, lo de dentro pierde
/// su estado y las hojas abiertas se quedan sin ancla.
class PaneScope extends StatefulWidget {
  const PaneScope({
    super.key,
    this.role = PaneRole.single,
    required this.child,
  });

  final PaneRole role;
  final Widget child;

  /// El ancho de este panel o, sin panel, el de la ventana.
  static double widthOf(BuildContext context) =>
      InheritedModel.inheritFrom<_PaneModel>(
        context,
        aspect: _PaneAspect.width,
      )?.size.width ??
      MediaQuery.sizeOf(context).width;

  /// El tamaño de este panel o, sin panel, el de la ventana.
  static Size sizeOf(BuildContext context) =>
      InheritedModel.inheritFrom<_PaneModel>(
        context,
        aspect: _PaneAspect.size,
      )?.size ??
      MediaQuery.sizeOf(context);

  /// Qué panel es este. Sin panel, [PaneRole.single].
  static PaneRole roleOf(BuildContext context) =>
      InheritedModel.inheritFrom<_PaneModel>(
        context,
        aspect: _PaneAspect.role,
      )?.role ??
      PaneRole.single;

  /// El ancla de este panel, para centrar en él algo que se pinta fuera (una
  /// hoja). `null` si no hay panel: entonces se centra en la ventana.
  ///
  /// En el panel de lista y en la tercera columna (más estrechos que una hoja)
  /// es la del área de contenido entera: una hoja abierta desde la lista no se
  /// encoge a 360, se centra en la pestaña como con un solo panel.
  ///
  /// Se llama al abrir la hoja, desde el manejador del toque: ahí vuelve a
  /// medir el panel, por si la última medida se hizo a mitad de una
  /// transición. No crea dependencia: el ancla avisa sola cuando el panel
  /// cambia.
  static PaneAnchor? anchorOf(BuildContext context) {
    final model = context.getInheritedWidgetOfExactType<_PaneModel>();
    final anchor =
        model != null &&
            (model.role == PaneRole.list || model.role == PaneRole.aside)
        ? (model.outerAnchor ?? model.anchor)
        : model?.anchor;
    if (anchor != null &&
        SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      anchor.refresh();
    }
    return anchor;
  }

  @override
  State<PaneScope> createState() => _PaneScopeState();
}

class _PaneScopeState extends State<PaneScope> {
  late final PaneAnchor _anchor = PaneAnchor._(_measure);
  bool _measureScheduled = false;

  /// El ancla del panel de fuera (el área de contenido), si lo hay.
  PaneAnchor? _outer;

  Rect? _measure() {
    if (!mounted) {
      return null;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Mide al acabar el fotograma: durante la maquetación todavía no se sabe
  /// dónde ha quedado el panel.
  void _scheduleMeasure() {
    if (_measureScheduled) {
      return;
    }
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      _anchor.refresh();
    });
  }

  @override
  void dispose() {
    // Una hoja abierta en este panel sigue escuchando su ancla: al irse el
    // panel (dos paneles que pasan a uno al girar), sigue la del área de
    // contenido en vez de quedarse con la medida de antes.
    _anchor._retire(_outer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Depender de la ventana hace que el panel se vuelva a medir cuando
    // cambia, aunque a él le lleguen las mismas restricciones.
    final window = MediaQuery.maybeSizeOf(context) ?? Size.zero;
    _outer = context.getInheritedWidgetOfExactType<_PaneModel>()?.anchor;
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleMeasure();
        return _PaneModel(
          outerAnchor: _outer,
          role: widget.role,
          size: Size(
            constraints.hasBoundedWidth ? constraints.maxWidth : window.width,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : window.height,
          ),
          anchor: _anchor,
          child: widget.child,
        );
      },
    );
  }
}

enum _PaneAspect { role, width, size }

class _PaneModel extends InheritedModel<_PaneAspect> {
  const _PaneModel({
    required this.outerAnchor,
    required this.role,
    required this.size,
    required this.anchor,
    required super.child,
  });

  final PaneRole role;
  final Size size;
  final PaneAnchor anchor;

  /// El ancla del `PaneScope` de fuera, si lo hay (el área de contenido).
  final PaneAnchor? outerAnchor;

  @override
  bool updateShouldNotify(_PaneModel oldWidget) =>
      role != oldWidget.role || size != oldWidget.size;

  @override
  bool updateShouldNotifyDependent(
    _PaneModel oldWidget,
    Set<_PaneAspect> dependencies,
  ) => dependencies.any(
    (aspect) => switch (aspect) {
      _PaneAspect.role => role != oldWidget.role,
      _PaneAspect.width => size.width != oldWidget.size.width,
      _PaneAspect.size => size != oldWidget.size,
    },
  );
}

/// El rectángulo de un panel en coordenadas de la ventana, para lo que se
/// pinta fuera de él. Avisa cuando el panel cambia de tamaño o de sitio.
///
/// El valor es el de la última medida, que se hace al acabar el fotograma en
/// el que cambia la maquetación: quien lo escucha se recoloca en el fotograma
/// siguiente. Antes de la primera medida vale `Rect.zero`.
class PaneAnchor extends ChangeNotifier implements ValueListenable<Rect> {
  PaneAnchor._(this._measure);

  final Rect? Function() _measure;
  Rect _rect = Rect.zero;
  bool _disposed = false;

  /// Cuando su panel ya no está: el ancla de fuera a la que sigue, o ninguna.
  PaneAnchor? _successor;
  bool _retired = false;

  @override
  Rect get value {
    final successor = _successor;
    if (successor != null) {
      return successor.value;
    }
    // Sin panel ni ancla de fuera: la ventana entera (`PaneAligned` cuenta
    // un rectángulo vacío como la ventana).
    return _retired ? Rect.zero : _rect;
  }

  /// Vuelve a medir el panel ahora. Solo fuera de la construcción y de la
  /// maquetación (en un manejador de toque o al acabar un fotograma).
  void refresh() {
    if (_disposed) {
      return;
    }
    final successor = _successor;
    if (successor != null) {
      successor.refresh();
      return;
    }
    if (_retired) {
      return;
    }
    final rect = _measure();
    if (rect == null || rect == _rect) {
      return;
    }
    _rect = rect;
    notifyListeners();
  }

  /// Su panel se ha ido. Si nadie la escucha, se libera; si una hoja abierta
  /// la escucha todavía, pasa a seguir a [outer] (el área de contenido) hasta
  /// que la hoja se cierre.
  void _retire(PaneAnchor? outer) {
    if (_disposed || _retired) {
      return;
    }
    _retired = true;
    if (!hasListeners) {
      dispose();
      return;
    }
    if (outer != null && !outer._disposed) {
      _successor = outer;
      outer.addListener(_relay);
    }
    // En el fotograma de después, cuando el área ya se ha vuelto a medir.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) {
        return;
      }
      _successor?.refresh();
      notifyListeners();
    });
  }

  void _relay() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) {
      return;
    }
    super.removeListener(listener);
    if (_retired && !hasListeners) {
      dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final successor = _successor;
    _successor = null;
    if (successor != null && !successor._disposed) {
      successor.removeListener(_relay);
    }
    super.dispose();
  }
}

/// Coloca [child] en una columna de [maxWidth] centrada en el panel de
/// [anchor], dentro de algo que ocupa la ventana entera (la capa de una hoja).
///
/// Solo fija la posición y el ancho en horizontal; en vertical no toca nada.
/// Con [anchor] `null` centra en la ventana. Si el panel es más estrecho que
/// [maxWidth], la columna ocupa el panel entero: en el móvil, de lado a lado
/// como hoy.
class PaneAligned extends StatelessWidget {
  const PaneAligned({
    super.key,
    required this.anchor,
    required this.maxWidth,
    required this.child,
  });

  /// El ancla que dio `PaneScope.anchorOf` al abrir la hoja.
  final ValueListenable<Rect>? anchor;

  /// Ancho máximo de la columna (`RegalosLayout.sheetWidth`…).
  final double maxWidth;

  final Widget child;

  /// Los márgenes izquierdo y derecho que dejan una columna de [maxWidth]
  /// centrada en [pane], dentro de una ventana de [windowWidth].
  ///
  /// Un [pane] que se sale de la ventana (la medida de antes de girar) se
  /// recorta a ella; uno vacío (sin medir todavía) o que queda fuera del todo
  /// cuenta como la ventana entera.
  static EdgeInsets insetsFor({
    required Rect pane,
    required double windowWidth,
    required double maxWidth,
  }) {
    var left = pane.left.clamp(0.0, windowWidth).toDouble();
    var right = pane.right.clamp(left, windowWidth).toDouble();
    if (pane.isEmpty || right <= left) {
      left = 0;
      right = windowWidth;
    }
    final gutter = ContentWidth.gutter(right - left, maxWidth);
    return EdgeInsets.only(
      left: left + gutter,
      right: windowWidth - right + gutter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final anchor = this.anchor;
    if (anchor == null) {
      return Padding(
        padding: insetsFor(
          pane: Rect.zero,
          windowWidth: windowWidth,
          maxWidth: maxWidth,
        ),
        child: child,
      );
    }
    return ValueListenableBuilder<Rect>(
      valueListenable: anchor,
      child: child,
      builder: (context, pane, child) => Padding(
        padding: insetsFor(
          pane: pane,
          windowWidth: windowWidth,
          maxWidth: maxWidth,
        ),
        child: child,
      ),
    );
  }
}
