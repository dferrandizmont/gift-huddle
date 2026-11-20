import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../web_device/application/web_app_provider.dart';
import '../application/web_board.dart';
import '../../family/application/family_providers.dart';
import '../../occasions/presentation/budget_parts.dart';
import 'board_budget_view.dart';

/// Elige el presupuesto de la web: el del tablero ([board]) desde 1280, esta
/// página ([WebBudgetPage]) en el resto de la web y la pantalla de siempre
/// ([classic]) fuera de la web (el móvil y la tablet nativos no cambian).
class WebBudgetGate extends ConsumerWidget {
  /// Crea la puerta.
  const WebBudgetGate({super.key, required this.board, required this.classic});

  /// El tablero de escritorio.
  final Widget board;

  /// La pantalla de siempre, fuera de la web.
  final Widget classic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webAppProvider)) {
      return classic;
    }
    return isWebBoard(context, ref) ? board : const WebBudgetPage();
  }
}

/// El presupuesto en la web por debajo de 1280: con raíl, su propia entrada de
/// navegación; con barra inferior, se abre desde la tarjeta de Ocasiones. Lleva
/// la cabecera de siempre de una pantalla de pestaña
/// y la vista nueva ([BoardBudgetView]) debajo, en una columna que se reparte
/// en dos o tres si la ventana da para ello.
class WebBudgetPage extends ConsumerWidget {
  /// Crea la página.
  const WebBudgetPage({super.key});

  /// El ancho máximo del contenido.
  static const double maxWidth = 960;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // A ancho de móvil no hay destino propio: se llega desde la tarjeta de
    // Ocasiones y la flecha vuelve a ella.
    final fromOccasions = !WindowClass.of(context).usesRail;
    return Scaffold(
      body: StaggerScope(
        child: SafeArea(
          bottom: false,
          child: ContentWidth(
            maxWidth: maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaggerItem(
                  index: 0,
                  child: ScreenHeader(
                    title: l10n.budgetTitle,
                    subtitle: budgetSubtitleText(
                      l10n,
                      ref.watch(budgetProvider),
                    ),
                    eyebrow: fromOccasions ? l10n.navOccasions : null,
                    backLabel: fromOccasions
                        ? l10n.backTo(l10n.navOccasions)
                        : null,
                    onBack: fromOccasions
                        ? () => context.canPop()
                              ? context.pop()
                              : context.go('/occasions')
                        : null,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: StaggerItem(
                      index: 1,
                      child: const BoardBudgetView(),
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
