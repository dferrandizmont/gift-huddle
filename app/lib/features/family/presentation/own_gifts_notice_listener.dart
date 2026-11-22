import '../../web_device/application/web_app_provider.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../application/own_gifts_notice.dart';

/// Avisa, una sola vez, de que en este móvil ya no se ven los regalos para su
/// persona (tras actualizar o al conectar otro móvil), y de que el móvil se ha
/// quedado solo y los regalos que estaban en secreto no están en él
/// ([OwnGiftsNoticeKind]). Lo visto se apunta en las preferencias locales.
///
/// El aviso es un diálogo con un solo botón, por encima de cualquier pantalla.
/// Si hay una hoja o un diálogo abiertos (por ejemplo la del emparejamiento),
/// espera a que se cierren.
class OwnGiftsNoticeListener extends ConsumerStatefulWidget {
  /// Crea el escuchador. [navigatorKey] es el navegador raíz.
  const OwnGiftsNoticeListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// Navegador raíz: su contexto tiene los textos y abre el diálogo.
  final GlobalKey<NavigatorState> navigatorKey;

  /// La app.
  final Widget child;

  @override
  ConsumerState<OwnGiftsNoticeListener> createState() =>
      _OwnGiftsNoticeListenerState();
}

class _OwnGiftsNoticeListenerState
    extends ConsumerState<OwnGiftsNoticeListener> {
  Timer? _retry;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _check() {
    if (_open) return;
    final navigator = widget.navigatorKey.currentState;
    final context = widget.navigatorKey.currentContext;
    if (navigator == null || context == null) return;
    final situation = ref.read(ownGiftsSituationProvider);
    // Con una hoja o un diálogo abiertos, se espera sin apuntar nada.
    if (_overlayOnTop(navigator)) {
      if (situation != null) {
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 2), () {
          if (mounted) _check();
        });
      }
      return;
    }
    final notice = nextOwnGiftsNotice(
      ref.read(sharedPreferencesProvider),
      situation,
    );
    if (notice == null) return;
    _open = true;
    unawaited(
      showRegalosDialog<void>(
        context,
        builder: (_) =>
            OwnGiftsNoticeDialog(notice: notice, web: ref.read(webAppProvider)),
      ).whenComplete(() => _open = false),
    );
  }

  /// Si lo de más arriba es una hoja o un diálogo y no una pantalla.
  bool _overlayOnTop(NavigatorState navigator) {
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top != null && top is! PageRoute;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OwnGiftsSituation?>(ownGiftsSituationProvider, (_, _) {
      // Fuera de la construcción del árbol.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check();
      });
    });
    return widget.child;
  }
}

/// El diálogo del aviso: título con el nombre, la frase y «Entendido».
class OwnGiftsNoticeDialog extends StatelessWidget {
  /// Crea el diálogo.
  const OwnGiftsNoticeDialog({
    super.key,
    required this.notice,
    this.web = false,
  });

  /// Qué se avisa.
  final OwnGiftsNotice notice;

  /// Si es la web: la frase dice «este ordenador» en lugar de «este móvil».
  final bool web;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final name = notice.personName;
    final body = switch (notice.kind) {
      OwnGiftsNoticeKind.hidden =>
        web ? l10n.ownGiftsHiddenBodyWeb(name) : l10n.ownGiftsHiddenBody(name),
      OwnGiftsNoticeKind.alone =>
        web
            ? l10n.ownGiftsAloneNoticeWeb(name)
            : l10n.ownGiftsAloneNotice(name),
    };
    return RegalosDialogSurface(
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.ownGiftsNoticeTitle(name),
              style: t.styles.screenTitleSmall,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: t.styles.body),
          const SizedBox(height: 20),
          FilledButton(
            style: regalosDialogPrimaryStyle(t),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionUnderstood),
          ),
        ],
      ),
    );
  }
}
