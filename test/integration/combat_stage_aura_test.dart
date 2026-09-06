/// SP2 §9/§11 — the headless run must actually exercise the aura path.
///
/// `CombatStage.runFight` binds per-active auras right after
/// `tome.resolve` and disposes them in its `finally`. Nothing else in the
/// suite drives that call, so without this file deleting the
/// `AuraBinder().bind(...)` line from `runFight` would leave the suite
/// green.
///
/// The observable signal is `EntityHealed` published *between*
/// `EncounterStarted` and `EncounterResolved`. `cloth_armor` is in
/// `RunStartingKit.itemIds` and carries `aura.regen_weave` (self /
/// `TurnStarted` / heal 1); it is the only in-fight heal in the run —
/// enemies never heal, and the between-cycle rest heal lands outside
/// every encounter window.
library;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:test/test.dart';

const _seed = 6;

/// One run's aura evidence, gathered live off the passed-in `EventBus`.
typedef _AuraTrace = ({
  int inFightHeals,
  int outOfFightHeals,
  Set<EntityId> healedInFight,
  Set<num> inFightAmounts,
  int sumTurnsUsed,
  int encounterCount,
});

_AuraTrace _trace(int seed) {
  final bus = EventBus();
  var inFight = false;
  var inFightHeals = 0;
  var outOfFightHeals = 0;
  final healedInFight = <EntityId>{};
  final amounts = <num>{};

  // Subscribe BEFORE runGame — telemetry publishes live, not on return.
  bus.subscribe<EncounterStarted>((_) => inFight = true);
  bus.subscribe<EncounterResolved>((_) => inFight = false);
  bus.subscribe<EntityHealed>((e) {
    if (!inFight) {
      outOfFightHeals++;
      return;
    }
    inFightHeals++;
    healedInFight.add(e.id);
    amounts.add(e.amount);
  });

  final result = runGame(seed, eventBus: bus);
  return (
    inFightHeals: inFightHeals,
    outOfFightHeals: outOfFightHeals,
    healedInFight: healedInFight,
    inFightAmounts: amounts,
    sumTurnsUsed: result.encounters.fold<int>(0, (a, e) => a + e.turnsUsed),
    encounterCount: result.encounters.length,
  );
}

void main() {
  test('runFight binds auras: the starting cloth_armor heals in-fight', () {
    final trace = _trace(_seed);

    expect(trace.encounterCount, greaterThan(0), reason: 'the run must fight');
    // THE assertion that dies if `AuraBinder().bind(...)` leaves runFight.
    expect(trace.inFightHeals, greaterThan(0),
        reason: 'aura.regen_weave must tick on the player\'s turns');
    // One healer only: the aura owner. Enemies never heal.
    expect(trace.healedInFight, hasLength(1));
    // Heal(1), clamped: 1 while damaged, 0 at full health. Never anything
    // bigger — that would be some other (non-aura) heal sneaking in.
    expect(trace.inFightAmounts.every((a) => a == 0 || a == 1), isTrue,
        reason: 'in-fight heals are aura.regen_weave only, saw ${trace.inFightAmounts}');
  });

  test('runFight disposes auras: aura ticks stay bounded by turns taken', () {
    final trace = _trace(_seed);

    // A leaked binding is cumulative: fight N would carry N copies of the
    // aura, so the tick count would grow as turns x fights-so-far and blow
    // straight past the total turn count. One live binding per fight keeps
    // it at most one tick per turn.
    expect(trace.inFightHeals, lessThanOrEqualTo(trace.sumTurnsUsed),
        reason: 'aura ticks (${trace.inFightHeals}) exceed total turns '
            '(${trace.sumTurnsUsed}) — bindings from earlier fights leaked');

    // The between-cycle rest heals are the only heals outside a fight, and
    // there is one fewer of them than cycles — they are not aura ticks.
    expect(trace.outOfFightHeals, lessThan(trace.inFightHeals));
  });

  test('the aura tick count is reproducible from the seed', () {
    final first = _trace(_seed);
    final second = _trace(_seed);

    expect(second.inFightHeals, first.inFightHeals);
    expect(second.sumTurnsUsed, first.sumTurnsUsed);
    expect(second.encounterCount, first.encounterCount);
  });
}
