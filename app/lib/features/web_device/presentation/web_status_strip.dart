import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../application/web_app_provider.dart';
import '../application/web_device_providers.dart';
import '../application/web_sync_engine.dart'
    show WebSyncActivity, WebSyncStatus;
import 'failed_attempts_notice.dart';
import 'set_aside_notice.dart';
import 'web_secrets_notice.dart';

/// Lo que enseña la línea discreta de estado de la web.
enum WebSyncIndicator {
  /// Hay cambios que se están subiendo.
  saving,

  /// Todo guardado.
  saved,

  /// Sin conexión con el servidor.
  offline,

  /// Ningún móvil ha confirmado este ordenador: no sube nada hasta entonces.
  awaitingConfirm,

  /// Sesión desconectada (revocada o lista borrada): la puerta ya lo explica
  /// y esta línea no dice nada.
  hidden,
}

/// Qué línea corresponde al estado del motor. Sin confirmar manda siempre;
/// confirmada, la actividad del motor distingue «sin conexión» (red caída con
/// reintento), «guardando» (publicación en curso o cambios sin confirmar) y
/// «guardado». `saving` fuerza «guardando» si quien llama lo sabe. Una web
/// desconectada (revocada o lista borrada) no se pinta como «sin conexión»:
/// la puerta ya lo explica, así que la línea se oculta.
WebSyncIndicator webSyncIndicatorOf(
  WebDeviceState state, {
  bool saving = false,
}) => switch (state.status) {
  WebSyncStatus.pending => WebSyncIndicator.awaitingConfirm,
  WebSyncStatus.disconnected => WebSyncIndicator.hidden,
  WebSyncStatus.confirmed => switch (state.activity) {
    WebSyncActivity.offline => WebSyncIndicator.offline,
    WebSyncActivity.uploading => WebSyncIndicator.saving,
    WebSyncActivity.idle =>
      saving ? WebSyncIndicator.saving : WebSyncIndicator.saved,
  },
};

/// Si [indicator] va en el pie del raíl ([WebRailStatus]) cuando hay raíl.
/// «Sin confirmar» es una frase larga y se queda en la franja de arriba.
bool webSyncInRail(WebSyncIndicator indicator) =>
    indicator != WebSyncIndicator.hidden &&
    indicator != WebSyncIndicator.awaitingConfirm;

/// La franja de arriba del contenido de la web: el aviso de intentos fallidos
/// ([FailedAttemptsNotice]), los de los regalos en secreto
/// ([WebSecretsNotice]), el de cambios apartados ([SetAsideNotice]) y, debajo,
/// el estado de guardado en una línea discreta.
///
/// Con [syncInRail] (hay raíl lateral) el estado de guardado pasa al pie del
/// raíl ([WebRailStatus]) y la franja solo lo repite si es «sin confirmar»
/// ([webSyncInRail]).
///
/// Fuera de la web no ocupa nada. Dentro, lee `webDeviceStateProvider` (solo
/// existe dentro de la sesión desbloqueada).
class WebStatusStrip extends ConsumerWidget {
  /// Crea la franja.
  const WebStatusStrip({
    super.key,
    this.saving = false,
    this.syncInRail = false,
  });

  /// Si se están subiendo cambios ahora mismo.
  final bool saving;

  /// Si el estado de guardado va en el pie del raíl.
  final bool syncInRail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webAppProvider)) return const SizedBox.shrink();
    final state = ref.watch(webDeviceStateProvider);
    final indicator = webSyncIndicatorOf(state, saving: saving);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FailedAttemptsNotice(),
        const WebSecretsNotice(),
        SetAsideNotice(count: state.setAsideChanges),
        if (!syncInRail || !webSyncInRail(indicator))
          WebSyncLine(indicator: indicator),
      ],
    );
  }
}

/// El estado de guardado en el pie del raíl lateral: un punto y el texto,
/// centrados bajo los destinos. «Sin confirmar» no sale aquí: lo dice la
/// franja de arriba ([WebStatusStrip]).
///
/// Fuera de la web no ocupa nada.
class WebRailStatus extends ConsumerWidget {
  /// Crea el estado del raíl.
  const WebRailStatus({super.key, this.saving = false});

  /// Si se están subiendo cambios ahora mismo.
  final bool saving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webAppProvider)) return const SizedBox.shrink();
    final state = ref.watch(webDeviceStateProvider);
    final indicator = webSyncIndicatorOf(state, saving: saving);
    if (!webSyncInRail(indicator)) return const SizedBox.shrink();
    return WebSyncLine(indicator: indicator, inRail: true);
  }
}

/// El estado de guardado al pie de la barra lateral del tablero de la web de
/// escritorio (`reglas-escritorio.md`, M1): un punto y el texto, alineados a la
/// izquierda. Con [compact] (la barra plegada a un raíl), solo el punto.
/// «Sin confirmar» no sale aquí: lo dice la franja de arriba.
///
/// Fuera de la web no ocupa nada.
class WebSidebarStatus extends ConsumerWidget {
  /// Crea el estado de la barra lateral.
  const WebSidebarStatus({super.key, this.compact = false});

  /// Si la barra está plegada: solo el punto.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webAppProvider)) return const SizedBox.shrink();
    final state = ref.watch(webDeviceStateProvider);
    final indicator = webSyncIndicatorOf(state);
    if (!webSyncInRail(indicator)) return const SizedBox.shrink();
    return WebSyncLine(indicator: indicator, inSidebar: true, compact: compact);
  }
}

/// La línea de estado: un punto y el texto, alineados a la derecha. Un cambio
/// de estado se funde en 150 ms. Con [inRail], el punto y el texto van
/// centrados uno bajo otro, para los 80 de ancho del raíl.
class WebSyncLine extends StatelessWidget {
  /// Crea la línea para [indicator].
  const WebSyncLine({
    super.key,
    required this.indicator,
    this.inRail = false,
    this.inSidebar = false,
    this.compact = false,
  });

  /// Si va al pie de la barra lateral del tablero: alineada a la izquierda.
  final bool inSidebar;

  /// Con [inSidebar], si la barra está plegada: solo el punto.
  final bool compact;

  /// Qué se enseña.
  final WebSyncIndicator indicator;

  /// Si va en el pie del raíl lateral.
  final bool inRail;

  @override
  Widget build(BuildContext context) {
    if (indicator == WebSyncIndicator.hidden) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final text = switch (indicator) {
      WebSyncIndicator.saving => l10n.webGateSaving,
      WebSyncIndicator.saved => l10n.webSyncSaved,
      WebSyncIndicator.offline => l10n.webSyncOffline,
      WebSyncIndicator.awaitingConfirm => l10n.webSyncAwaitingConfirm,
      WebSyncIndicator.hidden => '',
    };
    final muted = indicator == WebSyncIndicator.saved;
    final dotColor = switch (indicator) {
      WebSyncIndicator.saved => t.ink,
      WebSyncIndicator.saving => t.textSecondary,
      _ => t.danger,
    };
    final dot = DecoratedBox(
      decoration: BoxDecoration(
        color: dotColor,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
      child: const SizedBox.square(dimension: RegalosSizes.dot),
    );
    if (inSidebar) {
      return Semantics(
        container: true,
        liveRegion: indicator != WebSyncIndicator.saved,
        label: compact ? text : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 0 : 20,
            8,
            compact ? 0 : 16,
            12,
          ),
          child: AnimatedSwitcher(
            duration: RegalosMotion.fade,
            child: Row(
              key: ValueKey<WebSyncIndicator>(indicator),
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                dot,
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.styles.meta.copyWith(
                        color: muted ? t.textSecondary : t.text,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    if (inRail) {
      return Semantics(
        container: true,
        liveRegion: indicator != WebSyncIndicator.saved,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: AnimatedSwitcher(
            duration: RegalosMotion.fade,
            child: Column(
              key: ValueKey<WebSyncIndicator>(indicator),
              mainAxisSize: MainAxisSize.min,
              children: [
                dot,
                const SizedBox(height: 6),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.styles.meta.copyWith(
                    fontSize: 12,
                    color: muted ? t.textSecondary : t.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      liveRegion: indicator != WebSyncIndicator.saved,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: AnimatedSwitcher(
          duration: RegalosMotion.fade,
          child: Row(
            key: ValueKey<WebSyncIndicator>(indicator),
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              dot,
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.end,
                  style: t.styles.meta.copyWith(
                    color: muted ? t.textSecondary : t.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
