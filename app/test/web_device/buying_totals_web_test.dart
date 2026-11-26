import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/web_device/data/web_family_store.dart';

import 'web_engine_support.dart';
import 'web_secrets_test.dart' show protectNora;

void main() {
  test('web buying totals include an authorized household wish plan', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    const occasionId = 'kings';
    final clock = h.phone.clock;
    h.phone.doc = h.phone.doc
        .set(clock, Collections.givers, 'nosotros', {
          'name': 'Nosotros',
          'colorIndex': 0,
          'householdPays': true,
          'archived': false,
        })
        .set(clock, Collections.occasions, occasionId, {
          'kind': 'kings',
          'name': 'Reyes',
          'month': 1,
          'day': 6,
          'recurring': true,
          'archived': false,
          'budgetCents': 10000,
        })
        .set(clock, Collections.wishes, 'w1', {
          'recipientId': 'nora',
          'authorPersonId': 'nora',
          'suggested': false,
          'title': 'Bicicleta',
          'occasionId': occasionId,
          'year': 2026,
        });
    await h.phone.engine(h.client).sync();
    await h.engine.sync();

    final container = ProviderContainer(
      overrides: [
        familyStoreProvider.overrideWithValue(
          WebFamilyStore(h.vault, h.engine),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(familyControllerProvider.future);
    final baseline = container.read(budgetProvider);
    expect(baseline.total, const BudgetTotals(budgetCents: 10000));

    final claim = await h.engine.claimWish('w1', giverId: 'nosotros');
    expect(claim.ok, isTrue, reason: '${claim.error}');
    final planId = claim.planId!;
    final edit = await h.engine.editPlan(
      'nora',
      planId,
      const PrivatePlanPatch(
        status: GiftStatus.bought,
        plannedCents: 2500,
        actualCents: 2800,
      ),
    );
    expect(edit.ok, isTrue, reason: '${edit.error}');
    await container
        .read(familyControllerProvider.notifier)
        .reloadStoredCandidate();

    expect(
      container.read(giftsForProvider('nora')).map((gift) => gift.id),
      contains(planId),
    );
    final budget = container.read(budgetProvider);
    // Un plan de la casa cuenta en lo previsto, lo gastado y lo comprado, igual
    // que en el móvil (presupuesto 1.0.7: los deseos cogidos por la casa o sin
    // asignar suman una vez, con la misma regla que las filas).
    const plan = BudgetTotals(
      plannedCents: 2500,
      spentCents: 2800,
      expectedCents: 2800,
      boughtCents: 2800,
    );
    expect(budget.ofRecipientAllGivers('nora'), plan);
    expect(budget.ofRecipient('nora'), plan);
    expect(budget.ofOccasion(occasionId).spentCents, 2800);
    expect(budget.total, baseline.total + plan);
    expect(budget.budgeted.budgetCents, baseline.budgeted.budgetCents);

    container.read(yearFilterProvider.notifier).set(2025);
    final otherYear = container.read(budgetProvider);
    expect(otherYear.ofRecipientAllGivers('nora').expectedCents, 0);
    expect(otherYear.total.expectedCents, 0);
  });
}
