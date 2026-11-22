import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/ui_scale.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/regalos_motion.dart';
import '../core/widgets/focus_ring.dart';
import '../features/family/presentation/own_gifts_notice_listener.dart';
import '../features/lock/presentation/lock_gate.dart';
import '../features/recovery/presentation/recovery_file_listener.dart';
import '../features/recovery/presentation/transferred_gate.dart';
import '../features/settings/application/appearance_provider.dart';
import '../features/settings/application/locale_provider.dart';
import '../features/sharing/presentation/share_dialogs.dart';
import '../features/sync/presentation/peer_connected_listener.dart';
import '../features/web_device/application/web_app_provider.dart';
import '../features/web_device/presentation/web_operation_guard.dart';
import '../l10n/app_localizations.dart';
import 'root_navigator.dart';
import 'router.dart';

/// Raíz de la app: tema «Tareas», idiomas, navegación y bloqueo.
class RegalosApp extends ConsumerWidget {
  const RegalosApp({super.key, this.webSession = false});

  /// The outer web session owns covering, invitations and locking.
  final bool webSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final locale = ref.watch(localeProvider);
    final palette = appearance.accent.palette;
    final web = ref.watch(webAppProvider);
    // `MaterialApp` crea su `MediaQuery` más abajo y el tema animado necesita
    // saber ya si hay que reducir el movimiento.
    final reduce = MediaQueryData.fromView(View.of(context)).disableAnimations;
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: buildTheme(palette, Brightness.light),
      darkTheme: buildTheme(palette, Brightness.dark),
      themeMode: appearance.themeMode,
      // Cambiar de tema o de acento se funde con `soft`; con «Reducir
      // movimiento», 150 ms lineales.
      themeAnimationStyle: reduce
          ? const AnimationStyle(
              duration: RegalosMotion.fade,
              curve: Curves.linear,
            )
          : AnimationStyle(
              duration: RegalosSprings.softDuration,
              curve: RegalosCurves.soft,
            ),
      routerConfig: ref.watch(routerProvider),
      // El filete del foco con teclado se pinta aquí, encima de todo (también
      // de las hojas y los diálogos). En la web, todo va dentro de la escala
      // de interfaz (hasta 1,3 en monitores grandes): así escalan también las
      // hojas, los diálogos y los avisos.
      builder: (context, child) {
        final app = FocusRingOverlay(
          child: WebOperationGuard(
            child: webSession
                ? child ?? const SizedBox()
                : LockGate(
                    child: TransferredGate(
                      child: IncomingShareListener(
                        navigatorKey: rootNavigatorKey,
                        child: RecoveryFileListener(
                          navigatorKey: rootNavigatorKey,
                          child: PeerConnectedListener(
                            navigatorKey: rootNavigatorKey,
                            child: OwnGiftsNoticeListener(
                              navigatorKey: rootNavigatorKey,
                              child: child ?? const SizedBox(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
        return web ? UiScale(child: app) : app;
      },
    );
  }
}
