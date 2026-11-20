import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_link.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../l10n/app_localizations.dart';

/// Abre el enlace de un regalo en el navegador del sistema. Solo `https`
/// ([ExternalLinkOpener.openUserLink] lo comprueba); si no se puede abrir
/// (no hay navegador, o el texto no es un enlace que valga), copia el texto y
/// lo dice, como la política de privacidad de «Acerca de».
Future<void> openGiftLink(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final l10n = AppLocalizations.of(context);
  final text = url.trim();
  final opened = await ref.read(externalLinkOpenerProvider).openUserLink(text);
  if (opened) {
    return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    showRegalosSnackBar(context, SnackBar(content: Text(l10n.giftLinkCopied)));
  }
}
