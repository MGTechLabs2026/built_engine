import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const resolver = RewardResolver();
  const ironSword = RewardCandidate(
    ref: BuildComponentRef(referenceType: 'item', contentId: 'iron_sword'),
    weight: 1,
  );
  const jabTechnique = RewardCandidate(
    ref: BuildComponentRef(referenceType: 'technique', contentId: 'jab'),
    weight: 1,
  );

  group('deterministic reward', () {
    test('the same seed and definition yield the same reward', () {
      const definition = RewardDefinition(id: 'chest', candidates: [ironSword, jabTechnique]);

      final resultA = resolver.resolve(rng: RngService(42), definition: definition);
      final resultB = resolver.resolve(rng: RngService(42), definition: definition);

      expect(
        resultA.rewards.single.ref.contentId,
        equals(resultB.rewards.single.ref.contentId),
      );
    });
  });

  group('weighted candidates', () {
    test('a heavily-weighted candidate wins meaningfully more often', () {
      const heavy = RewardCandidate(
        ref: BuildComponentRef(referenceType: 'item', contentId: 'common_drop'),
        weight: 9,
      );
      const light = RewardCandidate(
        ref: BuildComponentRef(referenceType: 'item', contentId: 'rare_drop'),
        weight: 1,
      );
      const definition = RewardDefinition(id: 'chest', candidates: [heavy, light]);

      var heavyWins = 0;
      const trials = 50;
      for (var seed = 0; seed < trials; seed++) {
        final result = resolver.resolve(rng: RngService(seed), definition: definition);
        if (result.rewards.single.ref.contentId == 'common_drop') heavyWins++;
      }

      // Weight ratio is 9:1 (90%/10%), so an overwhelming majority across
      // a fixed, deterministic seed sweep proves real weighting, not luck.
      expect(heavyWins, greaterThan(trials * 3 ~/ 4));
    });
  });

  group('empty result', () {
    test('no candidates at all yields no rewards', () {
      const definition = RewardDefinition(id: 'empty_chest', candidates: []);

      final result = resolver.resolve(rng: RngService(1), definition: definition);

      expect(result.rewards, isEmpty);
    });

    test('candidates with zero total weight yield no rewards', () {
      const definition = RewardDefinition(
        id: 'broken_chest',
        candidates: [
          RewardCandidate(
            ref: BuildComponentRef(referenceType: 'item', contentId: 'unreachable'),
            weight: 0,
          ),
        ],
      );

      final result = resolver.resolve(rng: RngService(1), definition: definition);

      expect(result.rewards, isEmpty);
    });
  });

  group('multiple rewards', () {
    test('rollCount produces that many independent draws', () {
      const definition = RewardDefinition(id: 'chest', candidates: [ironSword, jabTechnique]);

      final result = resolver.resolve(
        rng: RngService(1),
        definition: definition,
        rollCount: 5,
      );

      expect(result.rewards, hasLength(5));
    });

    test('rollCount 0 yields no rewards without error', () {
      const definition = RewardDefinition(id: 'chest', candidates: [ironSword]);

      final result = resolver.resolve(rng: RngService(1), definition: definition, rollCount: 0);

      expect(result.rewards, isEmpty);
    });
  });

  group('arbitrary content references', () {
    test('item/technique/currency/consumable/trinket all resolve the same way',
        () {
      const definition = RewardDefinition(
        id: 'grab_bag',
        candidates: [
          RewardCandidate(
            ref: BuildComponentRef(referenceType: 'item', contentId: 'iron_sword'),
            weight: 1,
          ),
          RewardCandidate(
            ref: BuildComponentRef(referenceType: 'technique', contentId: 'jab'),
            weight: 1,
          ),
          RewardCandidate(
            ref: BuildComponentRef(referenceType: 'currency', contentId: 'gold'),
            weight: 1,
          ),
          RewardCandidate(
            ref: BuildComponentRef(referenceType: 'consumable', contentId: 'potion'),
            weight: 1,
          ),
          RewardCandidate(
            ref: BuildComponentRef(referenceType: 'trinket', contentId: 'lucky_coin'),
            weight: 1,
          ),
        ],
      );

      final result = resolver.resolve(
        rng: RngService(1),
        definition: definition,
        rollCount: 20,
      );

      final seenTypes = result.rewards.map((c) => c.ref.referenceType).toSet();
      expect(seenTypes.length, greaterThan(1));
      expect(
        seenTypes,
        everyElement(
          isIn(const {'item', 'technique', 'currency', 'consumable', 'trinket'}),
        ),
      );
    });
  });
}
