import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/occasion_theme.dart';
import '../application/appearance_provider.dart';

/// Envuelve la pantalla de una ocasión con su tema (Navidad, cumpleaños),
/// siempre que el interruptor «Temas de ocasión» de Ajustes esté activo.
/// Si no, deja pasar el tema normal.
class OccasionScope extends ConsumerWidget {
  const OccasionScope({super.key, required this.occasion, required this.child});

  final OccasionTheme occasion;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appearanceProvider);
    if (!settings.occasionThemes) return child;
    return Theme(
      data: buildTheme(
        settings.accent.palette,
        Theme.of(context).brightness,
        occasion: occasion,
      ),
      child: child,
    );
  }
}
