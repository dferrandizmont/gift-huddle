import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/soft_note.dart';
import '../../../l10n/app_localizations.dart';
import '../application/web_app_provider.dart';
import '../application/web_device_providers.dart';
import '../application/web_secrets.dart' show WebSecretsState;

/// Preferencia local del navegador (un booleano, sin nada sensible): el aviso
/// del ordenador compartido ya se cerró con «Entendido». Se borra al olvidar
/// este ordenador (`VaultService.onForgotten`), así que vuelve a salir tras
/// emparejarlo de nuevo.
const String kWebSecretsSharedNoticeSeenKey = 'webSecretsSharedNoticeSeen';

/// Lo que se ha cerrado ya: el aviso del ordenador compartido, en este
/// navegador; el de cambios descartados, en esta sesión desbloqueada.
class WebSecretsDismissals {
  /// Crea el estado.
  const WebSecretsDismissals({this.sharedComputer = false, this.dropped = 0});

  /// Se cerró el aviso del ordenador compartido (una vez por navegador).
  final bool sharedComputer;

  /// Cuántos cambios descartados se habían contado al cerrar el aviso: otro
  /// descarte posterior lo vuelve a abrir.
  final int dropped;
}

/// Qué avisos de los regalos en secreto se han cerrado. El del ordenador
/// compartido se recuerda por navegador en [kWebSecretsSharedNoticeSeenKey]
/// (se lee al crearse, sin parpadeo; sobrevive a bloqueos y recargas, y se
/// borra al olvidar este ordenador). El de cambios descartados vive en el
/// contenedor de la sesión desbloqueada: un desbloqueo nuevo parte de cero.
class WebSecretsNoticeDismissed extends Notifier<WebSecretsDismissals> {
  @override
  WebSecretsDismissals build() => WebSecretsDismissals(
    sharedComputer:
        ref
            .watch(sharedPreferencesProvider)
            .getBool(kWebSecretsSharedNoticeSeenKey) ??
        false,
  );

  /// Cierra el aviso del ordenador compartido y lo recuerda en este navegador.
  void dismissSharedComputer() {
    state = WebSecretsDismissals(sharedComputer: true, dropped: state.dropped);
    ref
        .read(sharedPreferencesProvider)
        .setBool(kWebSecretsSharedNoticeSeenKey, true)
        .catchError((Object _) => false);
  }

  /// Cierra el aviso de cambios descartados hasta [count].
  void dismissDropped(int count) => state = WebSecretsDismissals(
    sharedComputer: state.sharedComputer,
    dropped: count,
  );
}

/// Ver [WebSecretsNoticeDismissed].
final webSecretsNoticeDismissedProvider =
    NotifierProvider<WebSecretsNoticeDismissed, WebSecretsDismissals>(
      WebSecretsNoticeDismissed.new,
    );

/// Los avisos de la web sobre los regalos en secreto (1.0.6, ADR 0009), según
/// [WebSecretsState]:
///
/// - sin móvil que la avale: «vuelve a conectar este ordenador desde tu
///   móvil»;
/// - a la espera de las claves de su móvil: «abre la app en tu móvil…»;
/// - con los regalos en secreto a la vista: el bloqueo a los 5 minutos y que no
///   se deje abierta en un ordenador compartido (se puede cerrar y no vuelve a
///   salir en este navegador, ni tras bloquear ni tras recargar, hasta que se
///   olvide este ordenador);
/// - con el buzón de cambios retenido por el servidor: para quién, y que se
///   reintenta solo;
/// - con cambios descartados: cuántos y por qué (se puede cerrar; en la sesión
///   siguiente parte de cero).
///
/// Fuera de la web no ocupa nada. Cada aviso se funde y estira el hueco con
/// `fold`; con «Reducir movimiento», solo se funde.
class WebSecretsNotice extends ConsumerWidget {
  /// Crea los avisos.
  const WebSecretsNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webAppProvider)) return const SizedBox.shrink();
    final state = ref.watch(webDeviceStateProvider);
    final dismissed = ref.watch(webSecretsNoticeDismissedProvider);
    final notifier = ref.read(webSecretsNoticeDismissedProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final dropped = state.droppedSecretChanges;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoldingCard(
          show: state.secrets == WebSecretsState.reconnect,
          icon: SettingsIcons.computer,
          text: l10n.webSecretsReconnect,
        ),
        _FoldingCard(
          show: state.secrets == WebSecretsState.waitingKeys,
          icon: SettingsIcons.phone,
          text: l10n.webSecretsWaitingPhone,
        ),
        _FoldingCard(
          show:
              state.secrets == WebSecretsState.open &&
              !dismissed.sharedComputer,
          icon: SettingsIcons.lock,
          text: l10n.webSecretsSharedComputer,
          onDismiss: notifier.dismissSharedComputer,
        ),
        _FoldingCard(
          show: state.heldInboxNames.isNotEmpty,
          icon: SettingsIcons.phone,
          text: l10n.webSecretsHeld(state.heldInboxNames.join(', ')),
        ),
        // Los cambios de deseos cogidos esperan a que los demás móviles
        // estén en la 1.0.7 (ADR 0010); se aplican solos.
        _FoldingCard(
          show: state.heldPlanChanges > 0,
          icon: SettingsIcons.phone,
          text: l10n.webPlansHeld(state.heldPlanChanges),
        ),
        _FoldingCard(
          show: dropped > dismissed.dropped,
          icon: SettingsIcons.lock,
          text: l10n.webSecretsDropped(dropped),
          onDismiss: () => notifier.dismissDropped(dropped),
        ),
      ],
    );
  }
}

/// Un aviso suave que entra y sale con un fundido y estirando el hueco.
class _FoldingCard extends StatelessWidget {
  const _FoldingCard({
    required this.show,
    required this.icon,
    required this.text,
    this.onDismiss,
  });

  final bool show;
  final void Function(Path) icon;
  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final motion = RegalosMotion.of(context);
    return AnimatedSize(
      duration: motion.duration(RegalosCurves.foldDuration),
      curve: motion.curve(RegalosCurves.fold),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: RegalosMotion.fade,
        child: !show
            ? const SizedBox(key: ValueKey<bool>(false), width: double.infinity)
            : Padding(
                key: const ValueKey<bool>(true),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Semantics(
                  liveRegion: true,
                  child: SoftNote(
                    icon: icon,
                    text: text,
                    action: onDismiss == null
                        ? null
                        : TextButton(
                            onPressed: onDismiss,
                            child: Text(l10n.actionUnderstood),
                          ),
                  ),
                ),
              ),
      ),
    );
  }
}
