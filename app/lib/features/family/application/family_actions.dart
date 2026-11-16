import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../../l10n/app_localizations.dart';
import 'family_controller.dart';

/// Guarda una persona y, si tiene cumpleaños, crea su ocasión.
Future<void> saveRecipient(
  WidgetRef ref,
  AppLocalizations l10n,
  Recipient recipient,
) async {
  final controller = ref.read(familyControllerProvider.notifier);
  await controller.upsertRecipient(recipient);
  if (recipient.birthMonth != null && recipient.birthDay != null) {
    await controller.ensureBirthdayOccasions();
  }
}
