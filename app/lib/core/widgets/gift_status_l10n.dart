import '../../l10n/app_localizations.dart';
import '../theme/gift_status.dart';

/// Nombre del estado en el idioma de la app.
extension GiftStatusL10n on GiftStatus {
  String label(AppLocalizations l10n) => switch (this) {
    GiftStatus.idea => l10n.statusIdea,
    GiftStatus.decided => l10n.statusDecided,
    GiftStatus.bought => l10n.statusBought,
    GiftStatus.arrived => l10n.statusArrived,
    GiftStatus.wrapped => l10n.statusWrapped,
    GiftStatus.delivered => l10n.statusDelivered,
  };
}
