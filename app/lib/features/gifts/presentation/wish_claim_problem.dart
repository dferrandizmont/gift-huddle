import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/sync/protected_doc.dart' show ProtectedPersonReason;
import '../../../core/theme/regalos_motion.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/wish_service.dart';

/// Lo que la lista de una persona deja libre al pie mientras se ve el aviso de
/// «Cómo conectarlo»: su alto. Con la lista corta, sin ese hueco no habría a
/// dónde subir la fila para que el aviso no la tape.
final wishNoticeInsetProvider = NotifierProvider<_NoticeInset, double>(
  _NoticeInset.new,
);

class _NoticeInset extends Notifier<double> {
  @override
  double build() => 0;

  void set(double value) => state = value;
}

/// Si [result] es «este móvil aún no está conectado a la familia con la
/// versión nueva» al coger un deseo (en la web, ese motivo remite al móvil y
/// no lo cambia este aviso).
bool wishClaimNeedsFamily(WishResult result, {required bool web}) =>
    !web &&
    result.problem == WishProblem.blockUnavailable &&
    result.reason == ProtectedPersonReason.requiresV2;

/// Dice por qué no se pudo coger un deseo cuando este móvil no está
/// conectado a la familia con la versión nueva: un texto de deseos (no de
/// «regalos en secreto»), con la acción «Cómo conectarlo» que lleva a
/// «Móviles de la familia», donde se conecta.
///
/// El aviso no tapa el botón: si la fila [rowContext] quedaría bajo él, la
/// lista sube hasta dejarla a la vista.
void showWishClaimNeedsFamily(
  BuildContext context,
  WidgetRef ref, {
  BuildContext? rowContext,
}) {
  final l10n = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final noticeKey = GlobalKey();
  final container = ProviderScope.containerOf(context);
  ref.read(hapticsProvider).medium();
  final notice = showRegalosSnackBar(
    context,
    SnackBar(
      key: noticeKey,
      persist: false,
      duration: const Duration(seconds: 8),
      content: Text(l10n.wishClaimNeedsFamily),
      action: SnackBarAction(
        label: l10n.wishClaimHowToConnect,
        onPressed: () {
          // Si el deseo se abrió desde una hoja, se cierra antes de ir.
          navigator.popUntil((route) => route.settings is Page);
          router.go('/settings/share');
        },
      ),
    ),
  );
  notice.closed.whenComplete(() {
    container.read(wishNoticeInsetProvider.notifier).set(0);
  });
  if (rowContext != null) {
    _liftAboveNotice(rowContext, noticeKey, container);
  }
}

/// El margen entre la fila y el aviso.
const double _kNoticeGap = 12;

/// Cuántos fotogramas se espera a que el aviso acabe de entrar (crece
/// mientras entra) para saber lo que mide.
const int _kNoticeFrames = 60;

/// Sube la lista lo justo para que la fila [rowContext] no quede bajo el
/// aviso [noticeKey], que sale pegado al borde de abajo de la lista.
void _liftAboveNotice(
  BuildContext rowContext,
  GlobalKey noticeKey,
  ProviderContainer container,
) {
  var last = -1.0;
  var frames = 0;
  void check(Duration _) {
    if (!rowContext.mounted) {
      return;
    }
    // El aviso mide lo que mide su texto (más con letra grande) y crece
    // mientras entra: se espera a que deje de crecer.
    final height = noticeKey.currentContext?.size?.height ?? 0;
    final settled = height > 20 && (height - last).abs() < 0.5;
    last = height;
    if (!settled && ++frames < _kNoticeFrames) {
      WidgetsBinding.instance
        ..addPostFrameCallback(check)
        ..scheduleFrame();
      return;
    }
    _lift(rowContext, height > 20 ? height : 190, container);
  }

  WidgetsBinding.instance.addPostFrameCallback(check);
}

void _lift(
  BuildContext rowContext,
  double notice,
  ProviderContainer container,
) {
  final row = rowContext.findRenderObject();
  final view = Scrollable.maybeOf(rowContext)?.context.findRenderObject();
  if (row is! RenderBox || view is! RenderBox) {
    return;
  }
  if (!row.hasSize || !view.hasSize) {
    return;
  }
  final rowBottom = row.localToGlobal(Offset(0, row.size.height)).dy;
  final listBottom = view.localToGlobal(Offset(0, view.size.height)).dy;
  if (rowBottom <= listBottom - notice - _kNoticeGap) {
    return;
  }
  // Hueco al pie (para poder subir la fila) y, ya con él, la subida.
  container.read(wishNoticeInsetProvider.notifier).set(notice + _kNoticeGap);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!rowContext.mounted) {
      return;
    }
    Scrollable.ensureVisible(
      rowContext,
      alignment: 0.3,
      duration: RegalosMotion.of(rowContext).reduce
          ? Duration.zero
          : RegalosSprings.snapDuration,
      curve: RegalosCurves.snap,
    );
  });
}
