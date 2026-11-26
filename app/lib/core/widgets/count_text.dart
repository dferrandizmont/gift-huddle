import '../../l10n/app_localizations.dart';

/// Los regalos y los deseos sin coger de una persona u ocasión, en un texto:
/// «2 regalos · 4 deseos». Solo deseos: «4 deseos» (no «Sin regalos»); sin
/// deseos: la cuenta de regalos de siempre (QA 1.0.7, m1).
String giftsAndWishesText(AppLocalizations l10n, int gifts, int wishes) {
  if (wishes <= 0) return l10n.giftCount(gifts);
  if (gifts <= 0) return l10n.wishCount(wishes);
  return '${l10n.giftCount(gifts)} · ${l10n.wishCount(wishes)}';
}
