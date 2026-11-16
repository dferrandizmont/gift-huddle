import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/regalos_motion.dart';
import '../application/board_metrics.dart';

/// Una fila de regalo que sabe si es la marcada con el teclado (↑ y ↓ recorren
/// los regalos de la pantalla). Al marcarse se desplaza hasta verse.
class BoardCursorTarget extends ConsumerStatefulWidget {
  /// Crea el objetivo para el regalo [giftId].
  const BoardCursorTarget({
    super.key,
    required this.giftId,
    required this.builder,
  });

  /// El regalo de la fila.
  final String giftId;

  /// Construye la fila; [marked] dice si es la del teclado.
  final Widget Function(BuildContext context, bool marked) builder;

  @override
  ConsumerState<BoardCursorTarget> createState() => _BoardCursorTargetState();
}

class _BoardCursorTargetState extends ConsumerState<BoardCursorTarget> {
  late final BoardGiftCursor _cursor = ref.read(boardGiftCursorProvider);
  late bool _marked = _cursor.current == widget.giftId;

  @override
  void initState() {
    super.initState();
    _cursor.addListener(_changed);
  }

  @override
  void dispose() {
    _cursor.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final marked = _cursor.current == widget.giftId;
    if (marked == _marked || !mounted) {
      return;
    }
    setState(() => _marked = marked);
    if (marked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final reduce = RegalosMotion.of(context).reduce;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _marked);
}
