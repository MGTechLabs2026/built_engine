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
