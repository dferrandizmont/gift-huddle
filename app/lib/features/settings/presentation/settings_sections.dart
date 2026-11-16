import 'package:flutter/widgets.dart';

import '../../recovery/presentation/recovery_screen.dart';
import '../../sharing/presentation/backup_screen.dart';
import '../../sharing/presentation/share_screen.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'archive_screen.dart';
import 'manage_screens.dart';
import 'security_screen.dart';

/// Los apartados de Ajustes que abren una pantalla, por orden de arriba abajo
/// en la lista. El id es el último segmento de su ruta
/// (`/settings/appearance`).
const List<String> kSettingsSections = <String>[
  'people',
  'givers',
  'occasions',
  'archive',
  'security',
  'appearance',
  'share',
  'backup',
  'recovery',
  'about',
];

/// Los de la web: sin protecciones del móvil, sin compartir ni copia de
/// seguridad (ADR 0003, §8).
const List<String> kWebSettingsSections = <String>[
  'people',
  'givers',
  'occasions',
  'archive',
  'appearance',
  'about',
];

/// Los apartados que se ven en la lista de Ajustes, en la web o fuera de ella.
List<String> settingsSectionIds({required bool web}) =>
    web ? kWebSettingsSections : kSettingsSections;

/// La pantalla de un apartado de Ajustes.
Widget settingsSectionScreen(String id) => switch (id) {
  'people' => const ManagePeopleScreen(),
  'givers' => const ManageGiversScreen(),
  'occasions' => const ManageOccasionsScreen(),
  'archive' => const ArchiveScreen(),
  'security' => const SecurityScreen(),
  'appearance' => const AppearanceScreen(),
  'share' => const ShareScreen(),
  'backup' => const BackupScreen(),
  'recovery' => const RecoveryScreen(),
  _ => const AboutScreen(),
};
