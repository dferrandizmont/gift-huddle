import '../../../core/sync/model.dart';
import '../../../core/sync/wish_plan.dart';
import '../../../l10n/app_localizations.dart';

/// La línea de estado de un plan visto como regalo: quién lo ha cogido, el
/// aviso de dos reservas o «Nora lo quitó de su lista». La usan la lista de la
/// persona, la ocasión y el buscador, para que un deseo cogido se vea igual en
/// todas. Es `null` si no hay fila (un regalo normal).
String? wishPlanNoteText(
  AppLocalizations l10n,
  WishPlanRow? row,
  String planId,
  Map<String, Recipient> people,
  String? reader,
) {
  if (row == null) return null;
  switch (row.state) {
    case WishPlanState.conflictingClaims:
      return l10n.wishConflict;
    case WishPlanState.removedFromList:
      return l10n.wishRemovedFromList(people[row.recipientId]?.name ?? '');
    case WishPlanState.claimed:
    case WishPlanState.available:
      final plan = row.plans.where((p) => p.planId == planId).firstOrNull;
      if (plan == null) return null;
      return plan.claimantPersonId == reader
          ? l10n.wishClaimedByYou
          : l10n.wishClaimedBy(people[plan.claimantPersonId]?.name ?? '');
  }
}
