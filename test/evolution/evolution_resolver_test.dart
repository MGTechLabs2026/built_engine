import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

RuleContext _contextFor(EntityId subject, {int seed = 1, ComponentStore? components}) {
  final events = EventBus();
  final store = components ?? ComponentStore();
  return RuleContext(
    subject: subject,
    triggerEvent: const Object(),
    entities: EntityRegistry(events),
    components: store,
    events: events,
    rng: RngService(seed),
    eventCounts: EventCounter(events),
  );
}

void main() {
  const trainee = EntityId(1);
  const resolver = EvolutionResolver();

  group('deterministic seed', () {
    test('the same seed and inputs yield the same chosen candidate', () {
      const current = EvolutionDefinition(
        id: 'basic_punch',
        tier: EvolutionTiers.basic,
        candidates: [
          EvolutionCandidate(targetId: 'light_punch', tags: {'speed'}),
          EvolutionCandidate(targetId: 'heavy_punch', tags: {'power'}),
        ],
      );
      const profile = TrainingProfile({
        TrainingDimensions.speed: 0.6,
        TrainingDimensions.power: 0.4,
      });

      final resultA = resolver.resolve(
        context: _contextFor(trainee, seed: 42),
        current: current,
        profile: profile,
      );
      final resultB = resolver.resolve(
        context: _contextFor(trainee, seed: 42),
        current: current,
        profile: profile,
      );

      expect(resultA.chosenCandidate?.targetId, equals(resultB.chosenCandidate?.targetId));
    });
  });

  group('branching evolution', () {
    test('resolves to exactly one of several branches', () {
      const current = EvolutionDefinition(
        id: 'basic_punch',
        tier: EvolutionTiers.basic,
        candidates: [
          EvolutionCandidate(targetId: 'light_punch', tags: {'speed'}),
          EvolutionCandidate(targetId: 'heavy_punch', tags: {'power'}),
          EvolutionCandidate(targetId: 'fast_punch', tags: {'reaction'}),
          EvolutionCandidate(targetId: 'counter_punch', tags: {'control'}),
        ],
      );
      const profile = TrainingProfile({TrainingDimensions.speed: 0.5});

      final result = resolver.resolve(
        context: _contextFor(trainee, seed: 7),
        current: current,
        profile: profile,
      );

      expect(result.evolved, isTrue);
      expect(
        current.candidates.map((c) => c.targetId),
        contains(result.chosenCandidate!.targetId),
      );
    });
  });

  group('profile influences candidate weighting', () {
    test('a candidate tagged with the trainee\'s strongest dimension wins '
        'meaningfully more often', () {
      const current = EvolutionDefinition(
        id: 'basic_punch',
        tier: EvolutionTiers.basic,
        candidates: [
          EvolutionCandidate(targetId: 'fast_punch', tags: {'speed'}),
          EvolutionCandidate(targetId: 'plain_punch', tags: {}),
        ],
      );
      const speedFavoringProfile = TrainingProfile({TrainingDimensions.speed: 0.95});

      var fastWins = 0;
      const trials = 50;
      for (var seed = 0; seed < trials; seed++) {
        final result = resolver.resolve(
          context: _contextFor(trainee, seed: seed),
          current: current,
          profile: speedFavoringProfile,
        );
        if (result.chosenCandidate?.targetId == 'fast_punch') fastWins++;
      }

      // Weight ratio is ~1.95:1 (roughly 66%/34%), so a clear majority
      // across a fixed, deterministic seed sweep proves real influence
      // without depending on any single draw.
      expect(fastWins, greaterThan(trials ~/ 2));
    });

    test('with no matching tags at all, weighting has no bias to prove '
        '(sanity: an untagged candidate set never throws)', () {
      const current = EvolutionDefinition(
        id: 'basic_punch',
        tier: EvolutionTiers.basic,
        candidates: [
          EvolutionCandidate(targetId: 'a'),
          EvolutionCandidate(targetId: 'b'),
        ],
      );
      const profile = TrainingProfile({TrainingDimensions.speed: 0.9});

      final result = resolver.resolve(
        context: _contextFor(trainee, seed: 1),
        current: current,
        profile: profile,
      );

      expect(result.evolved, isTrue);
    });
  });

  group('evolution can fail/no-op', () {
    test('no-ops when the current definition has no candidates at all', () {
      const current = EvolutionDefinition(id: 'master_punch', tier: EvolutionTiers.master);

      final result = resolver.resolve(
        context: _contextFor(trainee, seed: 1),
        current: current,
        profile: const TrainingProfile({}),
      );

      expect(result.evolved, isFalse);
      expect(result.chosenCandidate, isNull);
    });

    test('no-ops when every candidate\'s conditions fail', () {
      const current = EvolutionDefinition(
        id: 'basic_punch',
        tier: EvolutionTiers.basic,
        candidates: [
          EvolutionCandidate(
            targetId: 'advanced_punch',
            conditions: [MasteryAtLeast('technique:jab', 99)],
          ),
        ],
      );

      final result = resolver.resolve(
        context: _contextFor(trainee, seed: 1),
        current: current,
        profile: const TrainingProfile({}),
      );

      expect(result.evolved, isFalse);
      expect(result.eligibleCandidates, isEmpty);
    });

    test('only eligible candidates (passing conditions) can be chosen', () {
      final components = ComponentStore();
      final events = EventBus();
      final mastery = MasteryTracker(components: components, events: events);
      mastery.define(
        const MasteryDefinition(subject: 'technique:jab', thresholds: [10]),
      );
      mastery.increase(trainee, 'technique:jab', 20); // level 1

      const current = EvolutionDefinition(
        id: 'basic_punch',
        tier: EvolutionTiers.basic,
        candidates: [
          EvolutionCandidate(
            targetId: 'reachable',
            conditions: [MasteryAtLeast('technique:jab', 1)],
          ),
          EvolutionCandidate(
            targetId: 'unreachable',
            conditions: [MasteryAtLeast('technique:jab', 99)],
          ),
        ],
      );
      final context = RuleContext(
        subject: trainee,
        triggerEvent: const Object(),
        entities: EntityRegistry(events),
        components: components,
        events: events,
        rng: RngService(1),
        eventCounts: EventCounter(events),
        mastery: mastery,
      );

      final result = resolver.resolve(
        context: context,
        current: current,
        profile: const TrainingProfile({}),
      );

      expect(result.eligibleCandidates.map((c) => c.targetId), equals(['reachable']));
      expect(result.chosenCandidate?.targetId, equals('reachable'));
    });
  });

  group('evolution can be used by unrelated content domains', () {
    test('the same resolver serves an independent item upgrade tree', () {
      const itemTree = EvolutionDefinition(
        id: 'iron_sword',
        tier: EvolutionTiers.basic,
        candidates: [
          EvolutionCandidate(targetId: 'sharpened_sword', tags: {'precision'}),
          EvolutionCandidate(targetId: 'reinforced_sword', tags: {'power'}),
        ],
      );
      const profile = TrainingProfile({TrainingDimensions.precision: 0.8});

      final result = resolver.resolve(
        context: _contextFor(trainee, seed: 3),
        current: itemTree,
        profile: profile,
      );

      expect(result.evolved, isTrue);
      expect(['sharpened_sword', 'reinforced_sword'], contains(result.chosenCandidate!.targetId));
    });
  });
}
