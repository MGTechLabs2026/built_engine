# Item Combine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a player combine 2+ owned items sharing the same
`definitionId`/`class` into one surviving, upgraded item — either a
class upgrade (same item, next tier) or a grade upgrade (a different,
better item, chosen via the engine's existing multi-branch Evolution
machinery) — gated by a flat `upgrade_points` resource cost and a
class-scaled fail/normal/rare roll.

**Architecture:** A new Core module `lib/src/combine/` provides a
generic, content-agnostic `CombineResolver` (pure odds formula + one
roll + delegation to the existing `EvolutionResolver` for grade
branching) — mirroring `lib/src/evolution/`'s "pure resolver, no stored
state" shape exactly, so any future plugin can reuse it. The Item plugin
(`lib/src/plugins/item/`) wires this to `ItemInstance`/`ItemDefinition`,
adds the `upgrade_points` resource, and reflects a combined survivor's
new identity into the Tome if it's currently placed (reusing
`TomeService.replace`, the same primitive `game_run.dart`'s
`replaceWithEvolved` already uses for technique evolution).

**Tech Stack:** Dart, `package:test`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-item-combine-design.md`

## Global Constraints

- Combine odds formula (2 inputs, tier `t`): `fail = min(10+(t-1)*10, 60)`,
  `rare = max(15-(t-1)*2, 5)`, `normal = 100 - fail - rare`. Full 2-input
  table: t1→10/75/15, t2→20/67/13, t3→30/59/11, t4→40/51/9, t5→50/43/7,
  t6→60/35/5.
- Each input beyond 2: nominal `fail -6`/`normal +4`/`rare +2`; once
  `fail` would drop below its floor (5), the shortfall is pulled back out
  of the `normal`/`rare` gains proportionally 2:1 so the three always sum
  to exactly 100.
- Cost is flat per attempt = current `itemClass` (not multiplied by input
  count), paid in a new `upgrade_points` resource.
- On any outcome, exactly one input entity survives; the rest are
  destroyed (component removed + entity destroyed).
- Class upgrade: survivor's `itemClass += 1`, same `definitionId`. Grade
  upgrade: survivor's `definitionId` becomes an `EvolutionResolver`-chosen
  target from the item's own `gradeEvolutionCandidates`; `itemClass`
  unchanged.
- At a grade's `maxClass`, a rolled "normal" outcome is treated as "rare"
  instead. A rolled "rare" outcome with no eligible grade candidate right
  now falls back to "normal" instead.
- Terminal (Combine blocked entirely, nothing spent): `itemClass >=
  maxClass` **and** no eligible grade candidate.
- Stat scaling: `base * (1 + classScalingPercent/100 * (itemClass-1))`,
  `classScalingPercent` defaults to 15, per-item content data.
- No spatial/adjacency requirement — ownership only.
- Works identically whether the survivor is Tome-placed or not.
- Core (`lib/src/combine/`) must depend only on other Core modules
  (`evolution`, `rng`, `rule`, `training`) — no plugin/content vocabulary.

---

## Task 1: `CombineOdds` — the pure odds formula

**Files:**
- Create: `lib/src/combine/combine_odds.dart`
- Test: `test/combine/combine_odds_test.dart`

**Interfaces:**
- Produces: `CombineOdds.forAttempt({required int tier, required int inputCount}) -> CombineOdds`, `CombineOdds({required num failPercent, required num normalPercent, required num rarePercent})`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/combine/combine_odds_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('baseline (2 inputs) across every tier', () {
    const expected = {
      1: (fail: 10, normal: 75, rare: 15),
      2: (fail: 20, normal: 67, rare: 13),
      3: (fail: 30, normal: 59, rare: 11),
      4: (fail: 40, normal: 51, rare: 9),
      5: (fail: 50, normal: 43, rare: 7),
      6: (fail: 60, normal: 35, rare: 5),
    };

    for (final entry in expected.entries) {
      test('tier ${entry.key}', () {
        final odds = CombineOdds.forAttempt(tier: entry.key, inputCount: 2);
        expect(odds.failPercent, equals(entry.value.fail));
        expect(odds.normalPercent, equals(entry.value.normal));
        expect(odds.rarePercent, equals(entry.value.rare));
      });
    }

    test('fail caps at 60 beyond tier 6', () {
      final odds = CombineOdds.forAttempt(tier: 9, inputCount: 2);
      expect(odds.failPercent, equals(60));
    });

    test('rare floors at 5 beyond tier 6', () {
      final odds = CombineOdds.forAttempt(tier: 9, inputCount: 2);
      expect(odds.rarePercent, equals(5));
    });
  });

  group('every result always sums to exactly 100', () {
    for (var tier = 1; tier <= 9; tier++) {
      for (var inputCount = 2; inputCount <= 8; inputCount++) {
        test('tier $tier, $inputCount inputs', () {
          final odds = CombineOdds.forAttempt(tier: tier, inputCount: inputCount);
          expect(odds.failPercent + odds.normalPercent + odds.rarePercent, equals(100));
        });
      }
    }
  });

  group('extra inputs improve odds, with floor redistribution', () {
    test('tier 1 with 3 inputs shifts odds toward success', () {
      final odds = CombineOdds.forAttempt(tier: 1, inputCount: 3);
      expect(odds.failPercent, equals(5)); // 10 - 6, above the floor
      expect(odds.normalPercent, equals(79));
      expect(odds.rarePercent, equals(17));
    });

    test('tier 1 with 4 inputs hits the fail floor and redistributes '
        'the shortfall 2:1 into normal/rare', () {
      final odds = CombineOdds.forAttempt(tier: 1, inputCount: 4);
      expect(odds.failPercent, equals(5));
      expect(odds.normalPercent, equals(78));
      expect(odds.rarePercent, equals(17));
    });

    test('tier 6 (already at the fail cap) still benefits from extra inputs', () {
      final odds = CombineOdds.forAttempt(tier: 6, inputCount: 4);
      // baseline 60/35/5; extra=2 nominal fail=60-12=48 (no floor hit)
      expect(odds.failPercent, equals(48));
      expect(odds.normalPercent, equals(43));
      expect(odds.rarePercent, equals(9));
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/combine/combine_odds_test.dart`
Expected: FAIL — `CombineOdds` isn't defined (compile error), since
`lib/src/combine/combine_odds.dart` doesn't exist yet and isn't exported
from `lib/build_engine.dart`.

- [ ] **Step 3: Implement `CombineOdds`**

```dart
// lib/src/combine/combine_odds.dart

/// The pure fail/normal/rare odds for one Combine attempt, given the
/// shared `class` (tier) of the items being combined and how many items
/// are in the attempt. No randomness here — [CombineResolver] is what
/// actually rolls against these percentages.
///
/// Baseline (2 inputs) at tier `t`: `fail = min(10+(t-1)*10, 60)`,
/// `rare = max(15-(t-1)*2, 5)`, `normal` absorbs the remainder. Each
/// input beyond 2 nominally shifts 6 points off `fail` (4 to `normal`, 2
/// to `rare`); once `fail` would drop below its floor (5), the shortfall
/// is pulled back out of the `normal`/`rare` gains proportionally (2:1,
/// the same ratio as the per-item split) instead of just clamping `fail`
/// alone — this is what keeps the three summing to exactly 100 at every
/// input count, instead of overshooting past 100 once `fail` bottoms out.
/// See `docs/superpowers/specs/2026-08-24-item-combine-design.md`.
class CombineOdds {
  const CombineOdds({
    required this.failPercent,
    required this.normalPercent,
    required this.rarePercent,
  });

  final num failPercent;
  final num normalPercent;
  final num rarePercent;

  static CombineOdds forAttempt({required int tier, required int inputCount}) {
    final baseFail = (10 + (tier - 1) * 10).clamp(0, 60);
    final baseRare = (15 - (tier - 1) * 2).clamp(5, 100);
    final baseNormal = 100 - baseFail - baseRare;

    final extra = inputCount > 2 ? inputCount - 2 : 0;
    final nominalFail = baseFail - extra * 6;
    final fail = nominalFail < 5 ? 5 : nominalFail;
    final deficit = fail - nominalFail; // 0 until the floor is hit
    final nominalRare = baseRare + extra * 2;
    final rare = nominalRare - (deficit / 3).round();
    final normal = 100 - fail - rare; // absorbs any rounding remainder
    // silence "unused" for baseNormal, kept for readability of the derivation
    assert(baseNormal >= 0);

    return CombineOdds(failPercent: fail, normalPercent: normal, rarePercent: rare);
  }
}
```

- [ ] **Step 4: Add the barrel export**

In `lib/build_engine.dart`, insert this line alphabetically (after
`src/character/character_service.dart`, before `src/component/component_store.dart`):

```dart
export 'src/combine/combine_odds.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `dart test test/combine/combine_odds_test.dart`
Expected: PASS (all groups)

- [ ] **Step 6: Commit**

```bash
git add lib/src/combine/combine_odds.dart lib/build_engine.dart test/combine/combine_odds_test.dart
git commit -m "feat: add CombineOdds, the pure Combine odds formula"
```

---

## Task 2: `CombineResolver` and its supporting types

**Files:**
- Create: `lib/src/combine/combine_input.dart`
- Create: `lib/src/combine/combine_outcome.dart`
- Create: `lib/src/combine/combine_result.dart`
- Create: `lib/src/combine/combine_exceptions.dart`
- Create: `lib/src/combine/combine_resolver.dart`
- Modify: `lib/build_engine.dart`
- Test: `test/combine/combine_resolver_test.dart`

**Interfaces:**
- Consumes: `CombineOdds.forAttempt` (Task 1); `EvolutionResolver`, `EvolutionDefinition`, `EvolutionCandidate`, `EvolutionResult`, `RuleContext`, `RngService`, `TrainingProfile` (all existing Core types, already exported from `lib/build_engine.dart`).
- Produces: `CombineInput({required String matchKey, required int tier})`; `enum CombineOutcome { fail, classUpgrade, gradeUpgrade }`; `CombineResult({required CombineOutcome outcome, required int survivorIndex, String? chosenGradeTargetId})`; `CombineMismatchException(CombineInput first, CombineInput mismatched)`; `CombineResolver().resolve({required List<CombineInput> inputs, required bool atMaxTierForGrade, required RuleContext gradeContext, required EvolutionDefinition gradeEvolution, required TrainingProfile gradeProfile, required RngService rng}) -> CombineResult`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/combine/combine_resolver_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

RuleContext _contextFor(EntityId subject, {int seed = 1}) {
  final events = EventBus();
  final components = ComponentStore();
  return RuleContext(
    subject: subject,
    triggerEvent: const Object(),
    entities: EntityRegistry(events),
    components: components,
    events: events,
    rng: RngService(seed),
    eventCounts: EventCounter(events),
  );
}

/// Scans seeds until it finds one whose Combine roll (for the given
/// tier/inputCount) lands in [target]'s bucket — avoids hand-picking a
/// magic seed while staying fully deterministic once found. Mirrors how
/// `technique_evolution_test.dart` sweeps seeds to prove weighting.
int _seedForOutcome(
  CombineOutcome target, {
  required int tier,
  required int inputCount,
  int maxSeed = 1000,
}) {
  final odds = CombineOdds.forAttempt(tier: tier, inputCount: inputCount);
  for (var seed = 1; seed <= maxSeed; seed++) {
    final roll = RngService(seed).nextDouble() * 100;
    final outcome = roll < odds.failPercent
        ? CombineOutcome.fail
        : roll < odds.failPercent + odds.normalPercent
            ? CombineOutcome.classUpgrade
            : CombineOutcome.gradeUpgrade;
    if (outcome == target) return seed;
  }
  throw StateError('no seed up to $maxSeed produced $target');
}

void main() {
  const trainee = EntityId(1);
  const resolver = CombineResolver();
  const noGradePath = EvolutionDefinition(id: 'x', tier: 'weapon');

  test('mismatched matchKey throws CombineMismatchException', () {
    expect(
      () => resolver.resolve(
        inputs: const [
          CombineInput(matchKey: 'knife', tier: 1),
          CombineInput(matchKey: 'sword', tier: 1),
        ],
        atMaxTierForGrade: false,
        gradeContext: _contextFor(trainee),
        gradeEvolution: noGradePath,
        gradeProfile: const TrainingProfile({}),
        rng: RngService(1),
      ),
      throwsA(isA<CombineMismatchException>()),
    );
  });

  test('mismatched tier throws CombineMismatchException', () {
    expect(
      () => resolver.resolve(
        inputs: const [
          CombineInput(matchKey: 'knife', tier: 1),
          CombineInput(matchKey: 'knife', tier: 2),
        ],
        atMaxTierForGrade: false,
        gradeContext: _contextFor(trainee),
        gradeEvolution: noGradePath,
        gradeProfile: const TrainingProfile({}),
        rng: RngService(1),
      ),
      throwsA(isA<CombineMismatchException>()),
    );
  });

  test('fewer than 2 inputs throws ArgumentError', () {
    expect(
      () => resolver.resolve(
        inputs: const [CombineInput(matchKey: 'knife', tier: 1)],
        atMaxTierForGrade: false,
        gradeContext: _contextFor(trainee),
        gradeEvolution: noGradePath,
        gradeProfile: const TrainingProfile({}),
        rng: RngService(1),
      ),
      throwsArgumentError,
    );
  });

  test('a fail-bucket roll produces CombineOutcome.fail', () {
    final seed = _seedForOutcome(CombineOutcome.fail, tier: 1, inputCount: 2);

    final result = resolver.resolve(
      inputs: const [
        CombineInput(matchKey: 'knife', tier: 1),
        CombineInput(matchKey: 'knife', tier: 1),
      ],
      atMaxTierForGrade: false,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: noGradePath,
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );

    expect(result.outcome, equals(CombineOutcome.fail));
    expect(result.chosenGradeTargetId, isNull);
  });

  test('a normal-bucket roll produces CombineOutcome.classUpgrade when not at max tier', () {
    final seed = _seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);

    final result = resolver.resolve(
      inputs: const [
        CombineInput(matchKey: 'knife', tier: 1),
        CombineInput(matchKey: 'knife', tier: 1),
      ],
      atMaxTierForGrade: false,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: noGradePath,
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );

    expect(result.outcome, equals(CombineOutcome.classUpgrade));
  });

  test('a grade-bucket roll resolves the target via EvolutionResolver', () {
    final seed = _seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);
    const gradeEvolution = EvolutionDefinition(
      id: 'simple_knife',
      tier: 'weapon',
      candidates: [EvolutionCandidate(targetId: 'sharp_knife')],
    );

    final result = resolver.resolve(
      inputs: const [
        CombineInput(matchKey: 'simple_knife', tier: 1),
        CombineInput(matchKey: 'simple_knife', tier: 1),
      ],
      atMaxTierForGrade: false,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: gradeEvolution,
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );

    expect(result.outcome, equals(CombineOutcome.gradeUpgrade));
    expect(result.chosenGradeTargetId, equals('sharp_knife'));
  });

  test('a grade-bucket roll with no eligible candidate falls back to classUpgrade', () {
    final seed = _seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);

    final result = resolver.resolve(
      inputs: const [
        CombineInput(matchKey: 'simple_knife', tier: 1),
        CombineInput(matchKey: 'simple_knife', tier: 1),
      ],
      atMaxTierForGrade: false,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: noGradePath, // no candidates at all
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );

    expect(result.outcome, equals(CombineOutcome.classUpgrade));
    expect(result.chosenGradeTargetId, isNull);
  });

  test('at max tier, a normal-bucket roll escalates to gradeUpgrade', () {
    final seed = _seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);
    const gradeEvolution = EvolutionDefinition(
      id: 'simple_knife',
      tier: 'weapon',
      candidates: [EvolutionCandidate(targetId: 'sharp_knife')],
    );

    final result = resolver.resolve(
      inputs: const [
        CombineInput(matchKey: 'simple_knife', tier: 1),
        CombineInput(matchKey: 'simple_knife', tier: 1),
      ],
      atMaxTierForGrade: true,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: gradeEvolution,
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );

    expect(result.outcome, equals(CombineOutcome.gradeUpgrade));
    expect(result.chosenGradeTargetId, equals('sharp_knife'));
  });

  test('a fail-bucket roll at max tier is still a fail (escalation only applies to normal)', () {
    final seed = _seedForOutcome(CombineOutcome.fail, tier: 1, inputCount: 2);
    const gradeEvolution = EvolutionDefinition(
      id: 'simple_knife',
      tier: 'weapon',
      candidates: [EvolutionCandidate(targetId: 'sharp_knife')],
    );

    final result = resolver.resolve(
      inputs: const [
        CombineInput(matchKey: 'simple_knife', tier: 1),
        CombineInput(matchKey: 'simple_knife', tier: 1),
      ],
      atMaxTierForGrade: true,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: gradeEvolution,
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );

    expect(result.outcome, equals(CombineOutcome.fail));
  });

  test('survivorIndex is always a valid index into inputs, deterministically', () {
    final seed = _seedForOutcome(CombineOutcome.fail, tier: 1, inputCount: 3);
    final inputs = const [
      CombineInput(matchKey: 'knife', tier: 1),
      CombineInput(matchKey: 'knife', tier: 1),
      CombineInput(matchKey: 'knife', tier: 1),
    ];

    final resultA = resolver.resolve(
      inputs: inputs,
      atMaxTierForGrade: false,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: noGradePath,
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );
    final resultB = resolver.resolve(
      inputs: inputs,
      atMaxTierForGrade: false,
      gradeContext: _contextFor(trainee, seed: seed),
      gradeEvolution: noGradePath,
      gradeProfile: const TrainingProfile({}),
      rng: RngService(seed),
    );

    expect(resultA.survivorIndex, inInclusiveRange(0, 2));
    expect(resultA.survivorIndex, equals(resultB.survivorIndex)); // deterministic
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/combine/combine_resolver_test.dart`
Expected: FAIL — `CombineResolver`/`CombineInput`/`CombineOutcome`/
`CombineResult`/`CombineMismatchException` aren't defined.

- [ ] **Step 3: Implement the supporting types**

```dart
// lib/src/combine/combine_input.dart

/// One item being combined, described only by what [CombineResolver]
/// needs to check eligibility: a key identifying "the same thing" (e.g.
/// an `ItemInstance.definitionId`) and a numeric tier (e.g. its
/// `itemClass`). Core-generic — has no idea these came from an item.
class CombineInput {
  const CombineInput({required this.matchKey, required this.tier});

  final String matchKey;
  final int tier;
}
```

```dart
// lib/src/combine/combine_outcome.dart

/// The three possible results of one [CombineResolver.resolve] attempt.
enum CombineOutcome { fail, classUpgrade, gradeUpgrade }
```

```dart
// lib/src/combine/combine_result.dart
import 'combine_outcome.dart';

/// The outcome of one [CombineResolver.resolve] call — pure data, no
/// side effects of its own. [survivorIndex] is an index into the
/// caller's own input list (whichever position [RngService] happened to
/// pick, for determinism/audit — the inputs are interchangeable, so it
/// never matters *which* index wins). [chosenGradeTargetId] is set only
/// when [outcome] is [CombineOutcome.gradeUpgrade].
class CombineResult {
  const CombineResult({
    required this.outcome,
    required this.survivorIndex,
    this.chosenGradeTargetId,
  });

  final CombineOutcome outcome;
  final int survivorIndex;
  final String? chosenGradeTargetId;
}
```

```dart
// lib/src/combine/combine_exceptions.dart
import 'combine_input.dart';

/// Thrown by [CombineResolver.resolve] when the given [CombineInput]s
/// don't all share the same `matchKey`/`tier` — Combine requires every
/// input to be "the same thing, at the same tier."
class CombineMismatchException implements Exception {
  const CombineMismatchException(this.first, this.mismatched);

  final CombineInput first;
  final CombineInput mismatched;

  @override
  String toString() =>
      'CombineMismatchException: expected matchKey="${first.matchKey}" '
      'tier=${first.tier}, got matchKey="${mismatched.matchKey}" '
      'tier=${mismatched.tier}';
}
```

```dart
// lib/src/combine/combine_resolver.dart
import '../evolution/evolution_definition.dart';
import '../evolution/evolution_resolver.dart';
import '../evolution/evolution_result.dart';
import '../rng/rng_service.dart';
import '../rule/rule_context.dart';
import '../training/training_profile.dart';
import 'combine_exceptions.dart';
import 'combine_input.dart';
import 'combine_odds.dart';
import 'combine_outcome.dart';
import 'combine_result.dart';

/// The generic Combine resolver: N same-`matchKey`/same-`tier` [inputs]
/// roll once against [CombineOdds] into fail/classUpgrade/gradeUpgrade.
/// Grade branching is delegated entirely to the existing
/// [EvolutionResolver] — this class knows nothing about what a "grade"
/// or an "item" is, only that a `gradeUpgrade` roll may or may not have
/// somewhere to go (an [gradeEvolution] with no eligible candidates means
/// it never does, and the roll falls back to `classUpgrade`). Pure
/// function of its inputs plus [rng] — no stored state — mirroring
/// [EvolutionResolver]'s own shape exactly. Resource cost and the
/// upfront "is this even attemptable" terminal check are the caller's
/// job (see `combineItems` in the Item plugin), not this class's.
class CombineResolver {
  const CombineResolver();

  CombineResult resolve({
    required List<CombineInput> inputs,
    required bool atMaxTierForGrade,
    required RuleContext gradeContext,
    required EvolutionDefinition gradeEvolution,
    required TrainingProfile gradeProfile,
    required RngService rng,
  }) {
    if (inputs.length < 2) {
      throw ArgumentError.value(
        inputs.length, 'inputs', 'Combine requires at least 2 inputs');
    }
    final first = inputs.first;
    for (final input in inputs.skip(1)) {
      if (input.matchKey != first.matchKey || input.tier != first.tier) {
        throw CombineMismatchException(first, input);
      }
    }

    final odds = CombineOdds.forAttempt(tier: first.tier, inputCount: inputs.length);
    final roll = rng.nextDouble() * 100;
    var outcome = roll < odds.failPercent
        ? CombineOutcome.fail
        : roll < odds.failPercent + odds.normalPercent
            ? CombineOutcome.classUpgrade
            : CombineOutcome.gradeUpgrade;

    EvolutionResult? evolutionResult;
    if (outcome == CombineOutcome.gradeUpgrade) {
      evolutionResult = const EvolutionResolver().resolve(
        context: gradeContext,
        current: gradeEvolution,
        profile: gradeProfile,
      );
      if (!evolutionResult.evolved) {
        // No eligible grade branch right now -> falls back to a class
        // upgrade instead of wasting the attempt.
        outcome = CombineOutcome.classUpgrade;
      }
    }
    if (outcome == CombineOutcome.classUpgrade && atMaxTierForGrade) {
      // Nothing left to gain within this grade -> escalate to a grade
      // attempt. The caller (`combineItems`) guarantees this branch is
      // only reachable when a grade path IS eligible right now (its own
      // upfront terminal-item check already proved it), so this resolve
      // call is guaranteed to evolve.
      evolutionResult = const EvolutionResolver().resolve(
        context: gradeContext,
        current: gradeEvolution,
        profile: gradeProfile,
      );
      outcome = CombineOutcome.gradeUpgrade;
    }

    return CombineResult(
      outcome: outcome,
      survivorIndex: rng.nextInt(inputs.length),
      chosenGradeTargetId: evolutionResult?.chosenCandidate?.targetId,
    );
  }
}
```

- [ ] **Step 4: Add the barrel exports**

In `lib/build_engine.dart`, replace the single `combine_odds.dart` export
line added in Task 1 with the full set, alphabetically:

```dart
export 'src/combine/combine_exceptions.dart';
export 'src/combine/combine_input.dart';
export 'src/combine/combine_odds.dart';
export 'src/combine/combine_outcome.dart';
export 'src/combine/combine_resolver.dart';
export 'src/combine/combine_result.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `dart test test/combine/combine_resolver_test.dart`
Expected: PASS (all tests)

- [ ] **Step 6: Run the full test suite to confirm no regressions**

Run: `dart test`
Expected: PASS (every existing test still passes — this task only added
new files and new barrel exports)

- [ ] **Step 7: Commit**

```bash
git add lib/src/combine/ lib/build_engine.dart test/combine/combine_resolver_test.dart
git commit -m "feat: add CombineResolver, the generic Combine mechanic"
```

---

## Task 3: Item plugin data model — `class`, `maxClass`, grade branching, stat scaling

**Files:**
- Modify: `lib/src/plugins/item/item_instance.dart`
- Modify: `lib/src/plugins/item/item_definition.dart`
- Modify: `lib/src/plugins/item/item_content.dart`
- Modify: `lib/src/plugins/item/item_lifecycle.dart` (add `CombineNotAvailableException`)
- Test: `test/plugins/item/item_instance_test.dart`
- Test: `test/plugins/item/item_definition_test.dart`
- Test: `test/plugins/item/item_content_test.dart`

**Interfaces:**
- Consumes: `EvolutionCandidate`, `EvolutionDefinition` (existing Core types, already exported).
- Produces: `ItemInstance({required String definitionId, required EntityId owner, int itemClass = 1})`; `ItemDefinition` gains `int? maxClass`, `List<EvolutionCandidate> gradeEvolutionCandidates`, `num classScalingPercent`, `EvolutionDefinition toGradeEvolutionDefinition()`, `Map<String, num> scaledProperties(int itemClass)`; `CombineNotAvailableException(String definitionId)`.

- [ ] **Step 1: Write the failing tests**

```dart
// Add to test/plugins/item/item_instance_test.dart, inside main():

  test('ItemInstance defaults itemClass to 1', () {
    const instance = ItemInstance(definitionId: 'knife', owner: EntityId(1));
    expect(instance.itemClass, equals(1));
  });

  test('ItemInstance can be constructed at a higher itemClass', () {
    const instance = ItemInstance(definitionId: 'knife', owner: EntityId(1), itemClass: 3);
    expect(instance.itemClass, equals(3));
  });
```

```dart
// Add to test/plugins/item/item_definition_test.dart, inside main():

  test('maxClass/gradeEvolutionCandidates/classScalingPercent default to '
      'not-combinable/empty/15', () {
    const definition = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'item'}, properties: {'attack': 2},
    );

    expect(definition.maxClass, isNull);
    expect(definition.gradeEvolutionCandidates, isEmpty);
    expect(definition.classScalingPercent, equals(15));
  });

  test('scaledProperties applies +classScalingPercent% per class above 1', () {
    const definition = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'item'}, properties: {'attack': 10},
    );

    expect(definition.scaledProperties(1)['attack'], equals(10));
    expect(definition.scaledProperties(3)['attack'], closeTo(13.0, 0.001)); // 10 * 1.30
  });

  test('scaledProperties respects a custom classScalingPercent', () {
    const definition = ItemDefinition(
      id: 'knife', category: 'weapon', tags: {'item'}, properties: {'attack': 10},
      classScalingPercent: 25,
    );

    expect(definition.scaledProperties(3)['attack'], closeTo(15.0, 0.001)); // 10 * 1.50
  });

  test('toGradeEvolutionDefinition carries id/category/candidates through', () {
    const definition = ItemDefinition(
      id: 'simple_knife', category: 'weapon', tags: {'item'}, properties: {},
      gradeEvolutionCandidates: [EvolutionCandidate(targetId: 'sharp_knife')],
    );

    final evolution = definition.toGradeEvolutionDefinition();

    expect(evolution.id, equals('simple_knife'));
    expect(evolution.tier, equals('weapon'));
    expect(evolution.candidates.single.targetId, equals('sharp_knife'));
  });
```

```dart
// Add to test/plugins/item/item_content_test.dart, inside main():

  test('itemDefinitionFromContent parses maxClass/gradeEvolution/classScalingPercent', () {
    final registry = ContentRegistry();
    registry.load({
      'id': 'simple_knife',
      'type': 'weapon',
      'tags': ['item', 'weapon'],
      'properties': {'attack': 2},
      'maxClass': 3,
      'classScalingPercent': 20,
      'gradeEvolution': [
        {'targetId': 'sharp_knife', 'tags': ['precision']},
        {'targetId': 'heavy_knife', 'tags': ['power']},
      ],
    });

    final simpleKnife = itemDefinitionFromContent(registry.get('simple_knife'));

    expect(simpleKnife.maxClass, equals(3));
    expect(simpleKnife.classScalingPercent, equals(20));
    expect(
      simpleKnife.gradeEvolutionCandidates.map((c) => c.targetId),
      equals(['sharp_knife', 'heavy_knife']),
    );
    expect(simpleKnife.gradeEvolutionCandidates.first.tags, equals({'precision'}));
  });

  test('an item with no maxClass/gradeEvolution declared stays non-combinable', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    final knife = itemDefinitionFromContent(registry.get(ItemIds.knife));

    expect(knife.maxClass, isNull);
    expect(knife.gradeEvolutionCandidates, isEmpty);
    expect(knife.classScalingPercent, equals(15)); // default
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/plugins/item/item_instance_test.dart test/plugins/item/item_definition_test.dart test/plugins/item/item_content_test.dart`
Expected: FAIL — `itemClass`/`maxClass`/`gradeEvolutionCandidates`/
`classScalingPercent`/`scaledProperties`/`toGradeEvolutionDefinition`
don't exist yet.

- [ ] **Step 3: Update `ItemInstance`**

```dart
// lib/src/plugins/item/item_instance.dart
import 'package:build_engine/build_engine.dart';

/// One physical copy of an item an owner possesses — pure runtime state,
/// attached via `ComponentStore` to a freshly created entity per copy
/// (see `ownItem`), exactly like `TomeInstance`'s "two fields, no
/// methods" pattern. Deliberately does NOT store discovered/usable state
/// or a mastery level — `DiscoveryTracker`/`MasteryTracker` (keyed by
/// [owner] + the subject `itemSubject(definitionId)` derives) are the
/// single source of truth for those; duplicating them here would let the
/// copy silently desync from the tracker it's supposed to mirror.
///
/// [itemClass] is the only field `combineItems`
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`) mutates
/// in place after a class upgrade; every other field stays as
/// immutable-per-copy as before.
class ItemInstance {
  const ItemInstance({
    required this.definitionId,
    required this.owner,
    this.itemClass = 1,
  });

  final String definitionId;
  final EntityId owner;
  final int itemClass;
}
```

- [ ] **Step 4: Update `ItemDefinition`**

```dart
// lib/src/plugins/item/item_definition.dart
import 'package:build_engine/build_engine.dart';

import 'item_requirement.dart';

/// A piece of physical equipment's immutable, content-derived shape —
/// mirrors `MartialItemDefinition`/`ElementalItemDefinition`'s exact
/// shape (the third occurrence of an already-proven pattern, not a new
/// one). Instances are built from loaded content via
/// `itemDefinitionFromContent`/`itemDefinition` (`item_content.dart`),
/// never hand-written here. [category] is `ContentDefinition.type`
/// verbatim (`'weapon'`/`'armor'`/...) — no redundant second field.
/// [properties] are raw named values (`{'attack': 3}`) describing the
/// item; nothing here activates them as `Modifier`s automatically —
/// [modifiersFor] exposes that capability for a future pass (equip/
/// active-build interpretation) to call, per the milestone's "expose
/// enough information for ActiveBuild interpretation later, don't
/// implement full combat action conversion yet." [trainingWeights] is
/// content data too (`ARCHITECTURE_AUDIT.md`'s category-7 finding) —
/// previously a hand-written Dart constant in `item_training_weights.dart`
/// disconnected from `ContentRegistry`; now parsed the same way
/// [properties] is.
///
/// [maxClass]/[gradeEvolutionCandidates]/[classScalingPercent] are the
/// Combine feature's data
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`):
/// `maxClass == null` means this item never opted into Combine at all;
/// `gradeEvolutionCandidates` mirrors `TechniqueDefinition
/// .evolutionCandidates` byte-for-byte (candidates travel with the
/// content definition itself, no separate registry).
class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.category,
    required this.tags,
    required this.properties,
    this.requirement,
    this.trainingWeights = const {},
    this.modifiersFor = _noModifiers,
    this.maxClass,
    this.gradeEvolutionCandidates = const [],
    this.classScalingPercent = 15,
  });

  final String id;
  final String category;
  final Set<String> tags;
  final Map<String, num> properties;
  final ItemRequirement? requirement;
  final Map<String, double> trainingWeights;
  final List<Modifier> Function(EntityId owner) modifiersFor;
  final int? maxClass;
  final List<EvolutionCandidate> gradeEvolutionCandidates;
  final num classScalingPercent;

  static List<Modifier> _noModifiers(EntityId owner) => const [];

  /// Builds the `EvolutionDefinition` this item's grade branches
  /// represent, for `EvolutionResolver.resolve` to consume — exactly
  /// mirrors `TechniqueDefinition.toEvolutionDefinition()`
  /// (`technique_definition.dart`). `tier` is passed through as
  /// [category] purely for descriptive/organizational value —
  /// `EvolutionDefinition.tier` is never read by the resolver.
  EvolutionDefinition toGradeEvolutionDefinition() =>
      EvolutionDefinition(id: id, tier: category, candidates: gradeEvolutionCandidates);

  /// Pure per-class stat scaling: `base * (1 + classScalingPercent/100 *
  /// (itemClass-1))` per property. Used by `ItemActionInterpreter`
  /// instead of raw [properties] once it knows a placement's live
  /// `itemClass` — see Task 4.
  Map<String, num> scaledProperties(int itemClass) => {
        for (final entry in properties.entries)
          entry.key: entry.value * (1 + classScalingPercent / 100 * (itemClass - 1)),
      };
}
```

- [ ] **Step 5: Update `item_content.dart` parsing**

In `lib/src/plugins/item/item_content.dart`, inside
`itemDefinitionFromContent`, after the existing `requirement` block and
before the `modifiersFor` local function, add:

```dart
  final maxClass = definition.extra['maxClass'] as int?;

  final rawGradeEvolution = (definition.extra['gradeEvolution'] as List?) ?? const [];
  final gradeEvolutionCandidates = [
    for (final entry in rawGradeEvolution)
      EvolutionCandidate(
        targetId: (entry as Map)['targetId'] as String,
        tags: {
          for (final tag in (entry['tags'] as List? ?? const [])) tag as String,
        },
      ),
  ];

  final classScalingPercent =
      (definition.extra['classScalingPercent'] as num?) ?? 15;
```

Then add the three new fields to the returned `ItemDefinition(...)` call:

```dart
    maxClass: maxClass,
    gradeEvolutionCandidates: gradeEvolutionCandidates,
    classScalingPercent: classScalingPercent,
```

(Insert these three lines alongside the existing `trainingWeights:`/
`modifiersFor:` lines in that same constructor call.)

- [ ] **Step 6: Add `CombineNotAvailableException`**

In `lib/src/plugins/item/item_lifecycle.dart`, add this class next to
the existing `ItemNotUsableException`:

```dart
/// Thrown when Combine is attempted on an item that either never opted
/// in (`ItemDefinition.maxClass == null`) or has genuinely nowhere left
/// to go (already at its grade's `maxClass`, with no eligible grade
/// candidate right now) — the true-terminal case
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`).
class CombineNotAvailableException implements Exception {
  const CombineNotAvailableException(this.definitionId);

  final String definitionId;

  @override
  String toString() => 'Combine not available for: $definitionId';
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `dart test test/plugins/item/item_instance_test.dart test/plugins/item/item_definition_test.dart test/plugins/item/item_content_test.dart`
Expected: PASS (all tests, including every pre-existing test in these
three files — the new fields are additive with defaults)

- [ ] **Step 8: Run the full test suite to confirm no regressions**

Run: `dart test`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/src/plugins/item/item_instance.dart lib/src/plugins/item/item_definition.dart lib/src/plugins/item/item_content.dart lib/src/plugins/item/item_lifecycle.dart test/plugins/item/item_instance_test.dart test/plugins/item/item_definition_test.dart test/plugins/item/item_content_test.dart
git commit -m "feat: add class/grade/scaling data model to Item plugin"
```

---

## Task 4: `BuildComponentRef` instance identity + `ItemActionInterpreter` scaling

**Files:**
- Modify: `lib/src/tome/build_component_ref.dart`
- Modify: `lib/src/plugins/item/item_lifecycle.dart` (`addItemToTome`)
- Modify: `lib/src/plugins/build_interpretation/item_action_interpreter.dart`
- Test: `test/plugins/item/item_lifecycle_test.dart`
- Test: `test/plugins/build_interpretation/item_action_interpreter_test.dart`

**Interfaces:**
- Consumes: `ItemInstance.itemClass`, `ItemDefinition.scaledProperties` (Task 3).
- Produces: `BuildComponentRef` gains `EntityId? instanceEntityId`; `addItemToTome` gains an optional `EntityId? instanceEntityId` parameter (default `null`, fully backward compatible).

- [ ] **Step 1: Write the failing tests**

```dart
// Add to test/plugins/item/item_lifecycle_test.dart, inside main():

  test('addItemToTome without an instance defaults instanceEntityId to null', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    final placement = context.tome.inspect(owner).single;
    expect(placement.buildComponentRef.instanceEntityId, isNull);
  });

  test('addItemToTome can carry a specific owned instance\'s id', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');
    final instanceEntity = ownItem(owner, ItemIds.ironSword, context);

    addItemToTome(owner, const SlotId('weapon'), ironSword, context,
        instanceEntityId: instanceEntity);

    final placement = context.tome.inspect(owner).single;
    expect(placement.buildComponentRef.instanceEntityId, equals(instanceEntity));
  });
```

```dart
// Add to test/plugins/build_interpretation/item_action_interpreter_test.dart, inside main():

  test('a placed item with a class-3 instance scales its attack modifier', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final instanceEntity = context.entities.create();
    context.components.add(
      instanceEntity,
      ItemInstance(definitionId: ItemIds.ironSword, owner: actor, itemClass: 3),
    );
    final build = ActiveBuild(owner: actor, components: [
      BuildComponentRef(
        referenceType: itemReferenceType,
        contentId: ItemIds.ironSword,
        instanceEntityId: instanceEntity,
      ),
    ]);

    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);

    final active =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components).toList();
    expect(active, hasLength(1));
    expect(active.single.value, closeTo(3.9, 0.001)); // 3 attack * (1 + 0.15*2)
  });

  test('a placed item with no instanceEntityId falls back to class 1 (unscaled)', () {
    final context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    final actor = context.entities.create();
    final build = ActiveBuild(owner: actor, components: const [
      BuildComponentRef(referenceType: itemReferenceType, contentId: ItemIds.ironSword),
    ]);

    interpreter.interpret(build: build, actor: actor, targets: const [], context: context);

    final active =
        context.modifiers.activeModifiersFor(actor, 'blade', context.components).toList();
    expect(active.single.value, equals(3)); // unscaled
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/plugins/item/item_lifecycle_test.dart test/plugins/build_interpretation/item_action_interpreter_test.dart`
Expected: FAIL — `instanceEntityId` isn't a parameter of `BuildComponentRef`/`addItemToTome` yet; the interpreter doesn't scale by class yet (the first new test's `closeTo(3.9, ...)` assertion fails against the current unscaled `3`).

- [ ] **Step 3: Extend `BuildComponentRef`**

```dart
// lib/src/tome/build_component_ref.dart
import '../entity/entity_id.dart';

/// An opaque reference to a piece of content a Tome placement represents —
/// an item, a technique, a modifier, a tag, or anything a future plugin
/// invents. Core never interprets [referenceType] or [contentId]; it only
/// carries them through from a Tome placement into an [ActiveBuild] for
/// whatever consumes that snapshot to resolve.
///
/// Also serves directly as the ECS component attached to the placeholder
/// [EntityId] `TomeService.insert` creates for each placement — no
/// redundant wrapper component needed.
///
/// [instanceEntityId] is additive, optional data: the entity id of the
/// specific owned copy this placement represents, when the referenced
/// content has per-copy runtime state a consumer needs (e.g. the Item
/// plugin's `ItemInstance.itemClass` for Combine's stat scaling — see
/// `docs/superpowers/specs/2026-08-24-item-combine-design.md`). `null`
/// for every reference type that has no such state (technique, and any
/// item placement made without an owned copy).
class BuildComponentRef {
  const BuildComponentRef({
    required this.referenceType,
    required this.contentId,
    this.instanceEntityId,
  });

  final String referenceType;
  final String contentId;
  final EntityId? instanceEntityId;
}
```

- [ ] **Step 4: Extend `addItemToTome`**

In `lib/src/plugins/item/item_lifecycle.dart`, change the signature and
body:

```dart
/// Inserts [item] into [owner]'s Tome at [slot] — but only if
/// [isItemUsable] first. Throws [ItemNotUsableException] (leaving the
/// Tome untouched) rather than calling `TomeService.insert` for an
/// unusable item; on success, publishes [ItemAddedToTome] and returns
/// normally exactly like `TomeService.insert` would (including
/// propagating its own `InvalidPlacementException`/`StateError` for a
/// bad slot/missing Tome). [instanceEntityId], when supplied, is the
/// specific owned [ItemInstance] this placement represents — carried
/// through to `BuildComponentRef.instanceEntityId` so `ItemActionInterpreter`
/// can read its live `itemClass` for stat scaling; omitted, placement
/// still works exactly as before (no per-copy state to resolve).
void addItemToTome(
  EntityId owner,
  SlotId slot,
  ItemDefinition item,
  PluginContext context, {
  EntityId? instanceEntityId,
}) {
  if (!isItemUsable(owner, item, context)) {
    throw ItemNotUsableException(item.id);
  }
  context.tome.insert(
    owner,
    slot,
    BuildComponentRef(
      referenceType: itemReferenceType,
      contentId: item.id,
      instanceEntityId: instanceEntityId,
    ),
  );
  context.events.publish(ItemAddedToTome(owner, item.id, slot));
}
```

- [ ] **Step 5: Update `ItemActionInterpreter`**

In `lib/src/plugins/build_interpretation/item_action_interpreter.dart`,
replace the body of the `for` loop:

```dart
    for (final ref in build.components) {
      if (ref.referenceType != itemReferenceType) continue;
      final definition = context.content.find(ref.contentId);
      if (definition == null) continue; // unknown/invalid item -> no modifier, not a crash
      final item = itemDefinitionFromContent(definition);
      final itemClass = ref.instanceEntityId == null
          ? 1
          : context.components.get<ItemInstance>(ref.instanceEntityId!)?.itemClass ?? 1;
      final attack = item.scaledProperties(itemClass)['attack'];
      if (attack == null) continue;

      final source = ModifierSource('build:${item.id}:${actor.value}');
      context.modifiers.removeBySource(source);
      context.modifiers.add(Modifier(
        source: source,
        target: actor,
        stat: _statFor(item),
        operation: ModifierOperation.add,
        value: attack,
      ));
    }
```

(Only the `attack` lookup changes — `item.properties['attack']` becomes
`item.scaledProperties(itemClass)['attack']`, preceded by resolving
`itemClass` from `ref.instanceEntityId`. `ItemInstance` is already
reachable here via the existing `package:build_engine/item_plugin.dart`
import.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `dart test test/plugins/item/item_lifecycle_test.dart test/plugins/build_interpretation/item_action_interpreter_test.dart`
Expected: PASS (all tests, including every pre-existing test in both
files — the field/parameter are additive, and class defaults to 1 which
reproduces the old unscaled behavior exactly)

- [ ] **Step 7: Run the full test suite to confirm no regressions**

Run: `dart test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add lib/src/tome/build_component_ref.dart lib/src/plugins/item/item_lifecycle.dart lib/src/plugins/build_interpretation/item_action_interpreter.dart test/plugins/item/item_lifecycle_test.dart test/plugins/build_interpretation/item_action_interpreter_test.dart
git commit -m "feat: carry item instance identity through Tome placements for class-scaled stats"
```

---

## Task 5: `combineItems` orchestration, `upgrade_points` resource, events

**Files:**
- Modify: `lib/src/plugins/item/item_vocabulary.dart` (add `ItemResources`)
- Modify: `lib/src/plugins/item/item_plugin.dart` (register the resource)
- Modify: `lib/src/plugins/item/item_events.dart` (add `ItemCombineSucceeded`/`ItemCombineFailed`)
- Modify: `lib/src/plugins/item/item_lifecycle.dart` (add `combineItems`)
- Test: `test/plugins/item/item_lifecycle_test.dart`
- Test: `test/plugins/item/item_plugin_test.dart`

**Interfaces:**
- Consumes: `CombineResolver`, `CombineInput`, `CombineOutcome`, `CombineMismatchException` (Task 2); `ItemInstance.itemClass`, `ItemDefinition.maxClass`/`toGradeEvolutionDefinition`/`gradeEvolutionCandidates` (Task 3); `BuildComponentRef.instanceEntityId` (Task 4); `EvolutionResolver`, `TrainingProfile`, `ResourcePool.consume` (existing Core).
- Produces: `ItemResources.upgradePoints` (`String` constant); `ItemCombineSucceeded(EntityId owner, String fromDefinitionId, CombineOutcome outcome, String toDefinitionId, int newClass)`; `ItemCombineFailed(EntityId owner, String definitionId, int itemClass)`; `combineItems(EntityId owner, List<EntityId> instanceEntities, PluginContext context) -> EntityId` (returns the surviving instance entity).

- [ ] **Step 1: Write the failing tests**

```dart
// Add to test/plugins/item/item_lifecycle_test.dart, inside main():

  group('combineItems', () {
    // A standalone combinable item (not part of the shipped 6-item
    // content set), loaded fresh in each test that needs it, mirroring
    // how test/combine/combine_resolver_test.dart uses inline content
    // rather than touching itemContentDefinitions.
    void loadSimpleKnife(PluginContext ctx, {int maxClass = 3, List<Map<String, dynamic>>? gradeEvolution}) {
      ctx.content.load({
        'id': 'simple_knife',
        'type': 'weapon',
        'tags': ['item', 'weapon'],
        'properties': {'attack': 2},
        'maxClass': maxClass,
        if (gradeEvolution != null) 'gradeEvolution': gradeEvolution,
      });
      if (gradeEvolution != null) {
        for (final entry in gradeEvolution) {
          ctx.content.load({
            'id': entry['targetId'],
            'type': 'weapon',
            'tags': ['item', 'weapon'],
            'properties': {'attack': 4},
          });
        }
      }
    }

    int seedForOutcome(
      CombineOutcome target, {
      required int tier,
      required int inputCount,
      int maxSeed = 1000,
    }) {
      final odds = CombineOdds.forAttempt(tier: tier, inputCount: inputCount);
      for (var seed = 1; seed <= maxSeed; seed++) {
        final roll = RngService(seed).nextDouble() * 100;
        final outcome = roll < odds.failPercent
            ? CombineOutcome.fail
            : roll < odds.failPercent + odds.normalPercent
                ? CombineOutcome.classUpgrade
                : CombineOutcome.gradeUpgrade;
        if (outcome == target) return seed;
      }
      throw StateError('no seed up to $maxSeed produced $target');
    }

    test('combining fewer than 2 instances throws ArgumentError', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final only = ownItem(owner, 'simple_knife', context);

      expect(
        () => combineItems(owner, [only], context),
        throwsArgumentError,
      );
    });

    test('mismatched definitionId throws CombineMismatchException', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, ItemIds.knife, context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<CombineMismatchException>()),
      );
    });

    test('a non-combinable item (no maxClass declared) throws CombineNotAvailableException', () {
      final owner = context.entities.create();
      final a = ownItem(owner, ItemIds.knife, context);
      final b = ownItem(owner, ItemIds.knife, context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<CombineNotAvailableException>()),
      );
    });

    test('insufficient upgrade_points throws InsufficientResourceException and consumes nothing', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      // no upgrade_points granted at all

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<InsufficientResourceException>()),
      );
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(0));
    });

    test('a fail outcome destroys exactly N-1 inputs and leaves the survivor unchanged', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.fail, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      ItemCombineFailed? published;
      context.events.subscribe<ItemCombineFailed>((e) => published = e);

      final survivor = combineItems(owner, [a, b], seededContext);

      final survivingInstances =
          [a, b].where((e) => context.components.get<ItemInstance>(e) != null).toList();
      expect(survivingInstances, equals([survivor]));
      expect(context.components.get<ItemInstance>(survivor)!.itemClass, equals(1));
      expect(context.components.get<ItemInstance>(survivor)!.definitionId, equals('simple_knife'));
      expect(published, isNotNull);
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(9));
    });

    test('a classUpgrade outcome increments the survivor\'s itemClass', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      ItemCombineSucceeded? published;
      context.events.subscribe<ItemCombineSucceeded>((e) => published = e);

      final survivor = combineItems(owner, [a, b], seededContext);

      final instance = context.components.get<ItemInstance>(survivor)!;
      expect(instance.itemClass, equals(2));
      expect(instance.definitionId, equals('simple_knife'));
      expect(published!.outcome, equals(CombineOutcome.classUpgrade));
      expect(published!.newClass, equals(2));
    });

    test('a gradeUpgrade outcome swaps the survivor\'s definitionId, itemClass unchanged', () {
      loadSimpleKnife(context, gradeEvolution: [
        {'targetId': 'sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      final seed = seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      final instance = context.components.get<ItemInstance>(survivor)!;
      expect(instance.definitionId, equals('sharp_knife'));
      expect(instance.itemClass, equals(1));
    });

    test('a Tome-placed survivor\'s placement is transparently updated', () {
      loadSimpleKnife(context, gradeEvolution: [
        {'targetId': 'sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
      );
      context.tome.createTome(owner, 'basic_tome');
      context.tome.insert(
        owner,
        const SlotId('weapon'),
        BuildComponentRef(
          referenceType: itemReferenceType, contentId: 'simple_knife', instanceEntityId: a),
      );
      final seed = seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      final placement = context.tome.inspect(owner).single;
      expect(placement.buildComponentRef.contentId, equals('sharp_knife'));
      expect(placement.buildComponentRef.instanceEntityId, equals(survivor));
      expect(placement.slot, equals(const SlotId('weapon'))); // slot preserved
    });

    test('combining an unplaced item leaves the Tome untouched', () {
      loadSimpleKnife(context);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
      );
      context.tome.createTome(owner, 'basic_tome');

      combineItems(owner, [a, b], context);

      expect(context.tome.inspect(owner), isEmpty);
    });

    test('at maxClass with no grade path, combine throws CombineNotAvailableException', () {
      loadSimpleKnife(context, maxClass: 1); // already at its own cap, no gradeEvolution
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);

      expect(
        () => combineItems(owner, [a, b], context),
        throwsA(isA<CombineNotAvailableException>()),
      );
      expect(context.resources.currentOf(owner, ItemResources.upgradePoints), equals(10)); // untouched
    });

    test('at maxClass with a grade path available, combine proceeds toward grade upgrades only', () {
      loadSimpleKnife(context, maxClass: 1, gradeEvolution: [
        {'targetId': 'sharp_knife'},
      ]);
      final owner = context.entities.create();
      final a = ownItem(owner, 'simple_knife', context);
      final b = ownItem(owner, 'simple_knife', context);
      context.resources.set(owner, ItemResources.upgradePoints, 10);
      // any seed that is NOT a fail-bucket roll should still succeed as a
      // gradeUpgrade thanks to the at-max escalation:
      final seed = seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(seed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);

      expect(context.components.get<ItemInstance>(survivor)!.definitionId, equals('sharp_knife'));
    });
  });
```

```dart
// Add to test/plugins/item/item_plugin_test.dart, inside main() (create
// the file first with `import` + a `_newContext()` matching
// item_lifecycle_test.dart's if it doesn't already exist — check first):

  test('ItemPlugin registers the upgrade_points resource', () {
    final context = _newContext();
    ItemPlugin().initialize(context);

    // unbounded by default: adding a large amount never clamps
    context.resources.add(const EntityId(1), ItemResources.upgradePoints, 999999);
    expect(context.resources.currentOf(const EntityId(1), ItemResources.upgradePoints),
        equals(999999));
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/plugins/item/item_lifecycle_test.dart test/plugins/item/item_plugin_test.dart`
Expected: FAIL — `combineItems`/`ItemResources`/`ItemCombineSucceeded`/
`ItemCombineFailed` don't exist yet.

- [ ] **Step 3: Add `ItemResources`**

In `lib/src/plugins/item/item_vocabulary.dart`, add:

```dart
/// Resource ids the Item plugin registers via `ResourcePool` — currently
/// just the Combine feature's cost
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`).
abstract final class ItemResources {
  static const upgradePoints = 'upgrade_points';
}
```

- [ ] **Step 4: Register the resource in `ItemPlugin.initialize`**

In `lib/src/plugins/item/item_plugin.dart`, add this line inside
`initialize` (right after `sdk.registerComponentCleanup<ItemInstance>();`):

```dart
    context.resources.define(
      const ResourceDefinition(id: ItemResources.upgradePoints, max: double.infinity),
    );
```

- [ ] **Step 5: Add the Combine events**

In `lib/src/plugins/item/item_events.dart`, add:

```dart
/// Published by `combineItems` when a combine attempt succeeds — either
/// [CombineOutcome.classUpgrade] (same [toDefinitionId] as
/// [fromDefinitionId], [newClass] = old class + 1) or
/// [CombineOutcome.gradeUpgrade] ([toDefinitionId] is the chosen grade
/// target, [newClass] unchanged from the inputs' shared class).
class ItemCombineSucceeded {
  const ItemCombineSucceeded(
    this.owner,
    this.fromDefinitionId,
    this.outcome,
    this.toDefinitionId,
    this.newClass,
  );

  final EntityId owner;
  final String fromDefinitionId;
  final CombineOutcome outcome;
  final String toDefinitionId;
  final int newClass;
}

/// Published by `combineItems` when a combine attempt fails — the
/// survivor is left unchanged at [itemClass]; N-1 of the inputs were
/// destroyed regardless.
class ItemCombineFailed {
  const ItemCombineFailed(this.owner, this.definitionId, this.itemClass);

  final EntityId owner;
  final String definitionId;
  final int itemClass;
}
```

- [ ] **Step 6: Implement `combineItems`**

In `lib/src/plugins/item/item_lifecycle.dart`, add:

```dart
/// Combines [instanceEntities] — 2+ owned copies sharing the same
/// `definitionId`/`itemClass` — into one surviving, upgraded copy. Costs
/// `ItemResources.upgradePoints` flat per attempt (= the shared
/// `itemClass`), consumed via the generic `ResourcePool` *before* rolling
/// (an `InsufficientResourceException` leaves nothing mutated). One
/// `CombineResolver` roll then decides fail/classUpgrade/gradeUpgrade;
/// exactly one input entity survives (the rest destroyed), mutated in
/// place. If the survivor is currently Tome-placed, its placement is
/// transparently updated to the new definitionId via `TomeService.replace`
/// — mirrors `game_run.dart`'s `replaceWithEvolved` pattern exactly.
/// Returns the surviving instance's entity id. See
/// `docs/superpowers/specs/2026-08-24-item-combine-design.md`.
EntityId combineItems(
  EntityId owner,
  List<EntityId> instanceEntities,
  PluginContext context,
) {
  if (instanceEntities.length < 2) {
    throw ArgumentError.value(
      instanceEntities.length, 'instanceEntities', 'Combine requires at least 2 items');
  }

  final instances = [
    for (final e in instanceEntities) context.components.get<ItemInstance>(e)!,
  ];
  final first = instances.first;
  for (var i = 1; i < instances.length; i++) {
    if (instances[i].definitionId != first.definitionId ||
        instances[i].itemClass != first.itemClass) {
      throw CombineMismatchException(
        CombineInput(matchKey: first.definitionId, tier: first.itemClass),
        CombineInput(matchKey: instances[i].definitionId, tier: instances[i].itemClass),
      );
    }
  }

  final definition = itemDefinition(first.definitionId, context);
  if (definition.maxClass == null) {
    throw CombineNotAvailableException(first.definitionId);
  }
  final atMax = first.itemClass >= definition.maxClass!;
  final gradeEvolution = definition.toGradeEvolutionDefinition();
  final ruleContext = context.ruleContextFor(owner);
  final gradeProfile = TrainingProfile(definition.trainingWeights);
  final hasGradePath = const EvolutionResolver()
      .resolve(context: ruleContext, current: gradeEvolution, profile: gradeProfile)
      .evolved;
  if (atMax && !hasGradePath) {
    throw CombineNotAvailableException(first.definitionId);
  }

  context.resources.consume(owner, ItemResources.upgradePoints, first.itemClass);

  final result = const CombineResolver().resolve(
    inputs: [
      for (final i in instances) CombineInput(matchKey: i.definitionId, tier: i.itemClass),
    ],
    atMaxTierForGrade: atMax,
    gradeContext: ruleContext,
    gradeEvolution: gradeEvolution,
    gradeProfile: gradeProfile,
    rng: context.rng,
  );

  final survivor = instanceEntities[result.survivorIndex];
  for (final e in instanceEntities) {
    if (e != survivor) {
      context.components.remove<ItemInstance>(e);
      context.entities.destroy(e);
    }
  }

  switch (result.outcome) {
    case CombineOutcome.fail:
      context.events.publish(
        ItemCombineFailed(owner, first.definitionId, first.itemClass),
      );
    case CombineOutcome.classUpgrade:
      final newClass = first.itemClass + 1;
      context.components.add(
        survivor,
        ItemInstance(definitionId: first.definitionId, owner: owner, itemClass: newClass),
      );
      _reflectCombineInTome(owner, first.definitionId, first.definitionId, survivor, context);
      context.events.publish(ItemCombineSucceeded(
        owner, first.definitionId, CombineOutcome.classUpgrade, first.definitionId, newClass,
      ));
    case CombineOutcome.gradeUpgrade:
      final newId = result.chosenGradeTargetId!;
      context.components.add(
        survivor,
        ItemInstance(definitionId: newId, owner: owner, itemClass: first.itemClass),
      );
      _reflectCombineInTome(owner, first.definitionId, newId, survivor, context);
      context.events.publish(ItemCombineSucceeded(
        owner, first.definitionId, CombineOutcome.gradeUpgrade, newId, first.itemClass,
      ));
  }
  return survivor;
}

/// Updates [owner]'s Tome placement for [oldId] (if any) to point at
/// [newId]/[survivorInstance] instead — a no-op if the survivor wasn't
/// placed. Mirrors `game_run.dart`'s `replaceWithEvolved` exactly: find
/// the placement by matching `contentId`, then `TomeService.replace`.
void _reflectCombineInTome(
  EntityId owner,
  String oldId,
  String newId,
  EntityId survivorInstance,
  PluginContext context,
) {
  final placement = context.tome.inspect(owner).where((p) =>
      p.buildComponentRef.referenceType == itemReferenceType &&
      p.buildComponentRef.contentId == oldId);
  if (placement.isEmpty) return;
  context.tome.replace(
    owner,
    placement.single.slot,
    BuildComponentRef(
      referenceType: itemReferenceType,
      contentId: newId,
      instanceEntityId: survivorInstance,
    ),
  );
}
```

- [ ] **Step 7: Check whether `test/plugins/item/item_plugin_test.dart` already exists**

Run: `ls test/plugins/item/item_plugin_test.dart`

If it doesn't exist, create it following the exact `_newContext()`
pattern from `test/plugins/item/item_lifecycle_test.dart` (Task 3's test
file), with just the one new test from Step 1 inside `main()`. If it
already exists, add the test from Step 1 into its existing `main()`
alongside whatever's already there.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `dart test test/plugins/item/item_lifecycle_test.dart test/plugins/item/item_plugin_test.dart`
Expected: PASS (every test, including all pre-existing ones)

- [ ] **Step 9: Run the full test suite to confirm no regressions**

Run: `dart test`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add lib/src/plugins/item/ test/plugins/item/item_lifecycle_test.dart test/plugins/item/item_plugin_test.dart
git commit -m "feat: implement combineItems — the full Item Combine flow"
```

---

## Task 6: End-to-end integration coverage

**Files:**
- Create: `test/integration/item_combine_end_to_end_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-5 — `combineItems`, `CombineOdds`, `CombineOutcome`, `ItemPlugin`, `ItemActionInterpreter`, `ActiveBuild`/`TomeService`.

- [ ] **Step 1: Write the integration tests**

```dart
// test/integration/item_combine_end_to_end_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events, rng: rng, shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

int _seedForOutcome(
  CombineOutcome target, {
  required int tier,
  required int inputCount,
  int maxSeed = 1000,
}) {
  final odds = CombineOdds.forAttempt(tier: tier, inputCount: inputCount);
  for (var seed = 1; seed <= maxSeed; seed++) {
    final roll = RngService(seed).nextDouble() * 100;
    final outcome = roll < odds.failPercent
        ? CombineOutcome.fail
        : roll < odds.failPercent + odds.normalPercent
            ? CombineOutcome.classUpgrade
            : CombineOutcome.gradeUpgrade;
    if (outcome == target) return seed;
  }
  throw StateError('no seed up to $maxSeed produced $target');
}

void loadDagger(PluginContext ctx) {
  ctx.content.load({
    'id': 'dagger',
    'type': 'weapon',
    'tags': ['item', 'weapon', 'blade'],
    'properties': {'attack': 4},
    'maxClass': 6,
  });
}

void main() {
  test('combining a Tome-placed item scales its live combat stat via ActiveBuild', () {
    final seed = _seedForOutcome(CombineOutcome.classUpgrade, tier: 1, inputCount: 2);
    final context = _newContext(seed);
    ItemPlugin().initialize(context);
    loadDagger(context);
    final owner = context.entities.create();
    final a = ownItem(owner, 'dagger', context);
    final b = ownItem(owner, 'dagger', context);
    context.resources.add(owner, ItemResources.upgradePoints, 10);
    context.tome.defineTome(TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']));
    context.tome.createTome(owner, 'basic_tome');
    context.tome.insert(
      owner,
      const SlotId('weapon'),
      BuildComponentRef(referenceType: itemReferenceType, contentId: 'dagger', instanceEntityId: a),
    );

    combineItems(owner, [a, b], context);

    const interpreter = ItemActionInterpreter();
    final build = context.tome.resolve(owner);
    interpreter.interpret(build: build, actor: owner, targets: const [], context: context);

    final active = context.modifiers.activeModifiersFor(owner, 'blade', context.components).toList();
    expect(active, hasLength(1));
    expect(active.single.value, closeTo(4.6, 0.001)); // 4 attack * (1 + 0.15*1) at class 2
  });

  test('a multi-candidate grade branch picks among targets according to trainingWeights', () {
    var sharpWins = 0;
    const trials = 60;
    for (var seed = 1; seed <= trials; seed++) {
      final context = _newContext(seed);
      ItemPlugin().initialize(context);
      context.content.load({
        'id': 'branching_knife',
        'type': 'weapon',
        'tags': ['item', 'weapon'],
        'properties': {'attack': 2},
        'maxClass': 3,
        'training': {'precision': 0.9},
        'gradeEvolution': [
          {'targetId': 'sharp_knife', 'tags': ['precision']},
          {'targetId': 'heavy_knife', 'tags': ['power']},
        ],
      });
      final owner = context.entities.create();
      final a = ownItem(owner, 'branching_knife', context);
      final b = ownItem(owner, 'branching_knife', context);
      context.resources.add(owner, ItemResources.upgradePoints, 10);
      final gradeSeed = _seedForOutcome(CombineOutcome.gradeUpgrade, tier: 1, inputCount: 2);
      final seededContext = PluginContext(
        entities: context.entities, components: context.components, events: context.events,
        rng: RngService(gradeSeed), rules: context.rules, queries: context.queries,
        modifiers: context.modifiers, content: context.content, resources: context.resources,
        mastery: context.mastery, progression: context.progression, discovery: context.discovery,
        tome: context.tome,
      );

      final survivor = combineItems(owner, [a, b], seededContext);
      if (context.components.get<ItemInstance>(survivor)!.definitionId == 'sharp_knife') {
        sharpWins++;
      }
    }

    // precision-weighted profile heavily favors sharp_knife; a clear
    // majority across the sweep proves real influence, mirroring
    // technique_evolution_test.dart's statistical assertion style.
    expect(sharpWins, greaterThan(trials ~/ 2));
  });

  test('a fully terminal item (maxClass reached, no grade path) cannot be combined', () {
    final context = _newContext(1);
    ItemPlugin().initialize(context);
    context.content.load({
      'id': 'masterwork_knife',
      'type': 'weapon',
      'tags': ['item', 'weapon'],
      'properties': {'attack': 10},
      'maxClass': 1,
    });
    final owner = context.entities.create();
    final a = ownItem(owner, 'masterwork_knife', context);
    final b = ownItem(owner, 'masterwork_knife', context);
    context.resources.add(owner, ItemResources.upgradePoints, 10);

    expect(
      () => combineItems(owner, [a, b], context),
      throwsA(isA<CombineNotAvailableException>()),
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/integration/item_combine_end_to_end_test.dart`
Expected: FAIL only if any Task 1-5 step was skipped; if Tasks 1-5 are
complete, this should already PASS on first run (it exercises no new
production code, only combinations of what already exists) — treat an
unexpected failure here as a signal to re-check Tasks 1-5, not as an
expected red step.

- [ ] **Step 3: Run the tests to verify they pass**

Run: `dart test test/integration/item_combine_end_to_end_test.dart`
Expected: PASS (all 3 tests)

- [ ] **Step 4: Run the full test suite one final time**

Run: `dart test`
Expected: PASS — every test in the repository, old and new.

- [ ] **Step 5: Commit**

```bash
git add test/integration/item_combine_end_to_end_test.dart
git commit -m "test: add end-to-end integration coverage for Item Combine"
```
