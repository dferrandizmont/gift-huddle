import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart' show routerProvider;
import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/danger_button.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/tag_label.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../sync/application/recovery_providers.dart';
import '../../settings/presentation/erase_all_dialog.dart';
import 'recovery_parts.dart';
import 'recovery_restore_screen.dart';

/// Tapa la app con la pantalla de solo lectura cuando la lista se ha pasado a
/// otro móvil o a otra app (`transferred`). La app queda montada debajo, sin
/// manos ni lectores de pantalla: no hay ninguna acción de edición.
class TransferredGate extends ConsumerStatefulWidget {
  /// Crea la puerta.
  const TransferredGate({super.key, required this.child});

  /// La app.
  final Widget child;

  @override
  ConsumerState<TransferredGate> createState() => _TransferredGateState();
}

class _TransferredGateState extends ConsumerState<TransferredGate> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>(
    debugLabel: 'transferred-gate',
  );

  /// Dentro de «Recuperar con mi código», atrás vuelve a la pantalla de solo
  /// lectura (o pregunta, si la recuperación está a medias); en la pantalla de
  /// solo lectura, sale de la app.
  ///
  /// Lo recibe un [_BackPriority] que envuelve el navegador de la puerta: toma
  /// la prioridad del despachador del router, así que atrás es de la puerta
  /// mientras esté puesta, con cualquier ruta apilada debajo y sea cual sea el
  /// orden en que se registraron los observadores del binding.
  Future<bool> _onBack() async {
    final navigator = _navigator.currentState;
    if (navigator == null) {
      return false;
    }
    if (navigator.canPop()) {
      await navigator.maybePop();
    } else {
      await SystemNavigator.pop();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // La instalación pasada a otro móvil se mantiene durante las fases y los
    // errores de una recuperación que se lanza desde aquí: la puerta no se
    // retira a mitad. Se quita al activar la recuperada o al borrar todo.
    final transferred = ref.watch(
      recoveryStatusProvider.select(
        (status) =>
            status.installationTransferred ||
            status.readiness == RecoveryReadiness.transferred,
      ),
    );
    final motion = RegalosMotion.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        TickerMode(
          enabled: !transferred,
          // Tapada, la app no recibe ni puntero ni foco (el Tab no entra en
          // su buscador) ni lectura de pantalla.
          child: ExcludeSemantics(
            excluding: transferred,
            child: ExcludeFocus(
              excluding: transferred,
              child: IgnorePointer(ignoring: transferred, child: widget.child),
            ),
          ),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: motion.duration(RegalosSprings.softDuration),
            switchInCurve: motion.curve(RegalosCurves.soft),
            switchOutCurve: motion.curve(RegalosCurves.fold),
            // A pantalla completa y con restricciones firmes: el navegador de
            // dentro ocupa todo el sitio.
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            // Un navegador propio: la app (y su router) quedan debajo, tapados, y
            // desde aquí se puede abrir «Recuperar con mi código».
            child: transferred
                ? _BackPriority(
                    dispatcher: ref.read(routerProvider).backButtonDispatcher,
                    onBackButtonPressed: _onBack,
                    child: Navigator(
                      key: _navigator,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => const TransferredScreen(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('open')),
          ),
        ),
      ],
    );
  }
}

/// Lo que hace un `BackButtonListener`, para un sitio que no está dentro de un
/// `Router`: la puerta envuelve a la app y a su router, así que no puede pedir
/// el despachador con `Router.of`; se le da el del router ([dispatcher]).
///
/// Mientras esté puesto, el atrás del sistema llega a [onBackButtonPressed]
/// antes que al router de la app (un despachador hijo con prioridad).
class _BackPriority extends StatefulWidget {
  const _BackPriority({
    required this.dispatcher,
    required this.onBackButtonPressed,
    required this.child,
  });

  final BackButtonDispatcher dispatcher;
  final ValueGetter<Future<bool>> onBackButtonPressed;
  final Widget child;

  @override
  State<_BackPriority> createState() => _BackPriorityState();
}

class _BackPriorityState extends State<_BackPriority> {
  late final ChildBackButtonDispatcher _child;

  @override
  void initState() {
    super.initState();
    _child = widget.dispatcher.createChildBackButtonDispatcher()
      ..addCallback(widget.onBackButtonPressed);
    // El router de la app ya está registrado (nace en el mismo fotograma, en
    // un hijo anterior de la pila); si no, se espera a que lo esté.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _child.takePriority();
      }
    });
  }

  @override
  void dispose() {
    _child.removeCallback(widget.onBackButtonPressed);
    widget.dispatcher.forget(_child);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Esta app ya no se usa para la lista: se dice con calma y se deja ver lo que
/// había, sin ninguna acción.
class TransferredScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const TransferredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(familyViewProvider);
    return Scaffold(
      body: SafeArea(
        child: StaggerScope(
          maxItems: 4,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
            children: [
              ContentWidth(
                maxWidth: RegalosLayout.onboardingColumn,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StaggerItem(
                        index: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: RecoveryBadge(
                            icon: SettingsIcons.devices,
                            size: 56,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      StaggerItem(
                        index: 1,
                        child: Semantics(
                          liveRegion: true,
                          child: RecoveryHeading(
                            title: l10n.transferredTitle,
                            body: l10n.transferredBody,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const RecoveryRestoreScreen(embedded: true),
                          ),
                        ),
                        child: Text(l10n.transferredRecover),
                      ),
                      const SizedBox(height: 12),
                      DangerButton(
                        label: l10n.transferredErase,
                        onPressed: () => runEraseAll(context, ref),
                      ),
                      const SizedBox(height: 24),
                      StaggerItem(
                        index: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TagLabel(l10n.transferredReadOnly),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final person in view.recipients)
                        _PersonRow(
                          name: person.name,
                          colorIndex: person.colorIndex,
                          titles: [
                            for (final g in view.giftsFor(person.id)) g.title,
                          ],
                        ),
                    ],
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

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.colorIndex,
    required this.titles,
  });

  final String name;
  final int colorIndex;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: RegalosShape.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonAvatar(name: name, colorIndex: colorIndex),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: t.styles.rowTitle),
                const SizedBox(height: 2),
                Text(l10n.giftCount(titles.length), style: t.styles.meta),
                for (final title in titles)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      title,
                      style: t.styles.body.copyWith(color: t.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
