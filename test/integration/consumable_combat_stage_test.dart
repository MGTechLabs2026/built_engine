/// SP3 §5.7 / §9 — the headless run exercises the consumable path end to
/// end (a rewarded `heal_potion` is hung in the Tome and actually used in
/// a fight), and per-fight setup is exception-safe.
library;

import 'dart:io';

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

/// Fights every cycle (`DefaultRunDecisionPolicy` never trains) and always
/// takes the `itemOrTechnique` reward when it is offered — so a rewarded
/// consumable lands in the Tome rather than being passed over for an
/// upgrade point. Mirrors `_ForceItemReward` in
/// `almanac_run_history_test.dart`.
class _FightAndTakeItems extends DefaultRunDecisionPolicy {
  const _FightAndTakeItems();

  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.itemOrTechnique);
    return index == -1 ? 0 : index;
  }
}

void main() {
  test('CombatStage.runFight declares the aura/consumable/subscription locals '
      'before one try and disposes them in reverse order in the finally', () {
    // §5.7 exception-safety is proved behaviourally by
    // `per_fight_consumable_test.dart` row 7 (AuraBinder.bind live →
    // ConsumableBinder.grant throws → the aura binding is disposed, no
    // consumable pool survives). Wiring a throwing interpreter through a
    // real CombatStage additionally needs full Tome scaffolding; this
    // structural guard catches a reordered/dropped dispose in the seam
    // itself, which the behavioural test cannot see.
    final src = File('lib/src/plugins/game/combat_stage.dart').readAsStringSync();

    // Locals declared before the try.
    final tryAt = src.indexOf('try {');
    expect(tryAt, greaterThan(0));
    for (final decl in [
      'AuraBinding? auraBinding;',
      'ConsumableCharges? consumableCharges;',
      'EventSubscription? subscription;',
    ]) {
      final at = src.indexOf(decl);
      expect(at, greaterThan(0), reason: 'missing local: $decl');
      expect(at, lessThan(tryAt), reason: '$decl must precede the try');
    }

    // finally disposes in reverse acquisition order:
    // subscription → consumableCharges → auraBinding.
    final cancelAt = src.indexOf('subscription?.cancel()');
    final consumableDisposeAt = src.indexOf('consumableCharges?.dispose()');
    final auraDisposeAt = src.indexOf('auraBinding?.dispose()');
    expect(cancelAt, greaterThan(tryAt));
    expect(cancelAt, lessThan(consumableDisposeAt));
    expect(consumableDisposeAt, lessThan(auraDisposeAt));
  });

  test('a rewarded heal_potion is hung in the Tome and used for a Heal(20) '
      'on the player during a fight', () {
    // Seed sweep (`technique_variant_run_test.dart` convention): find a
    // seed where `_FightAndTakeItems` gets a `heal_potion` into the Tome
    // and the `ConsumableAwareActionScorer` (heal_potion is priority 8)
    // actually spends it in a fight. Seed 10 is the first hit in 1..20 —
    // pinned here so the assertion is meaningful rather than a scan that
    // could silently find nothing.
    const seed = 10;

    final bus = EventBus();
    var inFight = false;
    // `ActionStarted` fires before the action's effects; `ActionCompleted`
    // after. So capture the heal_potion consumable's actor on start and
    // clear it on completion — any `EntityHealed` in that window is the
    // potion healing its user (self-target), and enemies carry no
    // consumables.
    EntityId? healPotionUser;
    var inFightPotionHeals = 0;

    bus.subscribe<EncounterStarted>((_) => inFight = true);
    bus.subscribe<EncounterResolved>((_) => inFight = false);
    bus.subscribe<ActionStarted>((e) {
      final ref = e.action.sourceRef;
      if (inFight &&
          ref?.referenceType == consumableReferenceType &&
          ref?.contentId == ConsumableIds.healPotion) {
        healPotionUser = e.actor;
      }
    });
    bus.subscribe<ActionCompleted>((e) {
      final ref = e.action.sourceRef;
      if (ref?.referenceType == consumableReferenceType &&
          ref?.contentId == ConsumableIds.healPotion) {
        healPotionUser = null;
      }
    });
    bus.subscribe<EntityHealed>((e) {
      if (inFight && e.amount == 20 && e.id == healPotionUser) {
        inFightPotionHeals++;
      }
    });

    final result = runGame(seed, policy: const _FightAndTakeItems(), eventBus: bus);

    // The reward pool did hand over a heal_potion this run …
    expect(result.rewardsGranted,
        contains('consumable:${ConsumableIds.healPotion}'));
    // … and it was used at least once, in a fight, for exactly Heal(20) on
    // the entity that invoked it.
    expect(inFightPotionHeals, greaterThanOrEqualTo(1),
        reason: 'expected at least one in-fight heal_potion Heal(20)');

    // Determinism: same seed + same policy => identical RunResult fields.
    RunResult run() => runGame(seed, policy: const _FightAndTakeItems());
    final a = run();
    final b = run();
    expect(a.won, equals(b.won));
    expect(a.cyclesCompleted, equals(b.cyclesCompleted));
    expect(a.rewardsGranted, equals(b.rewardsGranted));
    expect(a.techniquesLearned, equals(b.techniquesLearned));
    expect(a.itemsDiscovered, equals(b.itemsDiscovered));
    expect(
      a.encounters.map((e) => (e.name, e.enemyId, e.won, e.playerHealthAfter)),
      equals(
          b.encounters.map((e) => (e.name, e.enemyId, e.won, e.playerHealthAfter))),
    );
    expect(
      a.finalBuild.map((c) => (c.referenceType, c.contentId)),
      equals(b.finalBuild.map((c) => (c.referenceType, c.contentId))),
    );
  });
}
