import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_inspiration.dart';
import 'package:test/test.dart';

void main() {
  test('InspirationResult.none is an empty, not-discovered result', () {
    expect(InspirationResult.none.discovered, isFalse);
    expect(InspirationResult.none.familyId, '');
    expect(InspirationResult.none.descriptorIds, isEmpty);
    expect(InspirationResult.none.inspirerInstanceIds, isEmpty);
  });

  test('Inspirer holds its instance, profile, mastery and usage', () {
    const i = Inspirer(
      instanceId: EntityId(3),
      axisProfile: {'power': 6, 'speed': -1},
      masteryLevel: 2,
      usage: 9,
    );
    expect(i.instanceId, const EntityId(3));
    expect(i.axisProfile['power'], 6);
    expect(i.masteryLevel, 2);
    expect(i.usage, 9);
  });

  test('TechniqueVariantInspired carries descriptors and inspirer ids', () {
    const e = TechniqueVariantInspired(
      owner: EntityId(1),
      instanceId: EntityId(2),
      familyId: 'basic_kick',
      descriptorIds: {'strong', 'swift'},
      inspirerInstanceIds: [EntityId(3), EntityId(4)],
    );
    expect(e.familyId, 'basic_kick');
    expect(e.descriptorIds, {'strong', 'swift'});
    expect(e.inspirerInstanceIds, [const EntityId(3), const EntityId(4)]);
  });

  _resolverTests();
  _compatibilityTests();
}

TechniqueDescriptor _d(String id, Map<String, num> axes,
        {Set<String> tags = const {}}) =>
    TechniqueDescriptor(id: id, axes: axes, tags: tags);

Inspirer _insp(int id, Map<String, num> axes, {int mastery = 2, int usage = 9}) =>
    Inspirer(
        instanceId: EntityId(id),
        axisProfile: axes,
        masteryLevel: mastery,
        usage: usage);

const _resolver = TechniqueInspirationResolver();

void _resolverTests() {
  group('eligibility', () {
    test('zero inspirers → none, and the rng is not drawn', () {
      final rng = RngService(7);
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: const [],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: rng,
      );
      expect(res.discovered, isFalse);
      // no draw happened: first value matches a fresh generator
      expect(rng.nextDouble(), RngService(7).nextDouble());
    });

    test('an inspirer below the mastery OR usage bar is filtered out', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 0, usage: 30), // mastery too low
          _insp(2, {'speed': 5}, mastery: 3, usage: 1), // usage too low
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: RngService(1),
      );
      expect(res.discovered, isFalse); // nothing eligible
    });

    test('exactly one eligible inspirer can still discover; concentration is 1',
        () {
      // base 0.05 + gain 0.55 * 1.0 = 0.60 → a seed whose first draw < 0.60 hits
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.discovered, isTrue);
      expect(res.inspirerInstanceIds, [const EntityId(1)]);
    });
  });

  group('damped weighting', () {
    test('weight grows with mastery at equal usage', () {
      // Verified indirectly: with two equal-usage inspirers on different
      // axes, the higher-mastery one dominates emphasis → its axis is the
      // one drawn under a fixed seed.
      //
      // eligible: i1 w = 3*sqrt(9) = 9, i2 w = 1*sqrt(9) = 3 → ΣW = 12,
      // c = 9/12 = 0.75 → p = 0.05 + 0.55*0.75 = 0.4625. The discovery
      // seed must land below that p (not merely below 0.60).
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 3, usage: 9),
          _insp(2, {'speed': 5}, mastery: 1, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4}), _d('swift', {'speed': 5})],
        rng: _seedThatDiscoversAndDraws(),
      );
      expect(res.descriptorIds.contains('strong'), isTrue);
    });

    test('usage contributes with diminishing returns (√usage)', () {
      // Two eligible power-inspirers, equal mastery, different usage — both
      // above kMinUsageToInspire (3), so both survive step 0:
      //   A {power:5} m1 u16 → w = 1*sqrt(16) = 4
      //   B {power:5} m1 u4  → w = 1*sqrt(4)  = 2   (w(u16)/w(u4) == 2, NOT 4)
      //   ΣW = 6, c = 4/6 = 0.6667 → p_√ = 0.05 + 0.55*0.6667 ≈ 0.41667
      // Under LINEAR usage weighting the same inputs give wA=16, wB=4,
      //   ΣW = 20, c = 0.8 → p_linear = 0.05 + 0.55*0.8 = 0.49.
      final inspirers = [
        _insp(1, {'power': 5}, mastery: 1, usage: 16),
        _insp(2, {'power': 5}, mastery: 1, usage: 4),
      ];
      // Three non-overlapping descriptors so k (== 2 here: meanMastery 1 <
      // kInspirationStrongMasteryBar, so not a strong blend) leaves the
      // draw meaningful.
      final pool = [
        _d('strong', {'power': 4}),
        _d('swift', {'speed': 5}),
        _d('iron', {'endurance': 5}),
      ];

      // Discriminating leg: a first draw in [0.41667, 0.49). Under √ this
      // is >= p_√ ⇒ MISS. Under linear `usage` weighting p would be ≈0.49
      // and this same draw would discover — so this assertion FAILS if
      // `sqrt(usage)` is replaced with linear `usage`.
      final discriminating = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: inspirers,
        descriptorPool: pool,
        rng: _seedWithFirstDrawBetween(0.4167, 0.49),
      );
      expect(discriminating.discovered, isFalse);

      // Monotone leg: a first draw < p_√ still discovers under √, and the
      // power-only emphasis routes the weighted draw to `strong` (swift /
      // iron have zero positive overlap, so the k=2 draw stops early with
      // one descriptor — a real weighted outcome, not a k-capped tautology).
      final hit = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: inspirers,
        descriptorPool: pool,
        rng: _seedWithFirstDrawBelow(0.41),
      );
      expect(hit.discovered, isTrue);
      expect(hit.descriptorIds.contains('strong'), isTrue);
    });

    test('usage == 0 contributes nothing; all-zero-usage eligible → none', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 5}, mastery: 3, usage: 0)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: RngService(1),
      );
      // usage 0 fails kMinUsageToInspire (3) anyway → none
      expect(res.discovered, isFalse);
    });
  });

  group('emphasis uses positive axes only', () {
    test("a bear-like inspirer's negative speed never suppresses a speed draw",
        () {
      // Single eligible inspirer {power: 6, speed: -1}. Emphasis = {power: 1.0}
      // (speed dropped, not -x). With only a speed descriptor available and
      // no positive overlap, the draw finds nothing → none (not a
      // "negative pushed it away" artefact — verified by the pool-swap below).
      final noOverlap = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 6, 'speed': -1}, mastery: 3, usage: 30)],
        descriptorPool: [_d('swift', {'speed': 5})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(noOverlap.discovered,
          isFalse); // rolled a hit, but 0 positive-overlap candidates

      final withOverlap = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 6, 'speed': -1}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(withOverlap.descriptorIds, {'strong'});
    });
  });

  group('damping is sub-linear (√usage)', () {
    // CONTROLLER RULING: the brief's `concentrationFor` reference-value
    // expects asserted pure `math.sqrt` arithmetic (√4/(√4+1) == 2/3) and
    // nothing about production code — dropped. The behavioural coverage
    // that the resolver's `mastery * sqrt(usage)` weighting stays
    // sub-linear is kept by the seed-sweep test below, plus the
    // "mastery increases weight" / "usage" tests above.

    test(
        'a fixed seed: high-usage inspirer does NOT dominate the draw as it would linearly',
        () {
      // A: mastery 1, usage 100 on `power`; B: mastery 1, usage 4 on `speed`.
      // √: wA=10, wB=2 → emphasis power:speed ≈ 5:1 (a speed draw is still
      // reachable). Linear: wA=100, wB=4 → 25:1 (speed all but impossible).
      // Over a spread of discovering seeds, at least one draws `swift`.
      var sawSpeed = false;
      for (var s = 1; s < 400 && !sawSpeed; s++) {
        final rng = RngService(s);
        if (rng.nextDouble() >= 0.05 + 0.55 * (10 / 12)) {
          continue; // not a discovery
        }
        final res = _resolver.resolve(
          trainedFamilyId: 'basic_punch',
          inspirers: [
            _insp(1, {'power': 5}, mastery: 1, usage: 100),
            _insp(2, {'speed': 5}, mastery: 1, usage: 4),
          ],
          descriptorPool: [_d('strong', {'power': 4}), _d('swift', {'speed': 5})],
          rng: RngService(s),
        );
        if (res.descriptorIds.contains('swift')) sawSpeed = true;
      }
      expect(sawSpeed, isTrue,
          reason: 'speed became unreachable — usage weighting is not damped');
    });

    test('mastery 0 → weight 0 (also filtered by eligibility)', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 5}, mastery: 0, usage: 50)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.discovered, isFalse);
    });
  });

  group('single-source concentration', () {
    test('exactly one eligible inspirer → c == 1.0 → p == 0.60 exactly', () {
      // p = kInspirationBaseChance + kInspirationConcentrationGain * 1.0
      //   = 0.05 + 0.55 = 0.60
      final hit = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      final miss = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawAtLeast(0.60),
      );
      expect(hit.discovered, isTrue); // first draw < 0.60
      expect(miss.discovered,
          isFalse); // first draw >= 0.60 → exactly at the boundary misses
    });
  });

  group('source attribution', () {
    test('an eligible inspirer that shapes no drawn descriptor is omitted', () {
      // power-inspirer + speed-inspirer + endurance-inspirer, all eligible.
      // Pool has only a `power` descriptor → only the power inspirer can be
      // attributed.
      //
      // 3 equal-weight eligible inspirers (w = 3*sqrt(9) = 9 each) → ΣW = 27,
      // c = 9/27 = 1/3 → p = 0.05 + 0.55*(1/3) ≈ 0.23333. The discovery
      // seed must land below that p, so the bound is 0.23 (< p), not 0.30.
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 3, usage: 9),
          _insp(2, {'speed': 6}, mastery: 3, usage: 9),
          _insp(3, {'endurance': 6}, mastery: 3, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.23),
      );
      expect(res.discovered, isTrue);
      expect(res.inspirerInstanceIds, [const EntityId(1)]);
    });

    test('higher-support inspirer wins a single-descriptor attribution', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 2}, mastery: 1, usage: 9), // low support
          _insp(2, {'power': 9}, mastery: 3, usage: 9), // high support
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.30),
      );
      expect(res.inspirerInstanceIds, [const EntityId(2)]);
    });

    test('exact support tie → lowest eligible index; swapping order swaps id',
        () {
      List<EntityId> attrFor(List<Inspirer> ins) => _resolver.resolve(
            trainedFamilyId: 'basic_punch',
            inspirers: ins,
            descriptorPool: [_d('strong', {'power': 4})],
            rng: _seedWithFirstDrawBelow(0.30),
          ).inspirerInstanceIds;
      final a = _insp(1, {'power': 5}, mastery: 2, usage: 9);
      final b = _insp(2, {'power': 5}, mastery: 2, usage: 9); // identical support
      expect(attrFor([a, b]), [const EntityId(1)]);
      expect(attrFor([b, a]), [const EntityId(2)]);
    });

    test('multi-id attribution is a list in ascending eligible-index order', () {
      // Two equal-weight eligible inspirers (each mastery 3, usage 9 →
      // w = 3*3 = 9): one on power, one on speed. ΣW = 18, c = 0.5 →
      // p = 0.05 + 0.55*0.5 = 0.325. meanMastery 3 >= 2, ΣW 18 >= 6.0,
      // eligible.length 2 → strong → k = 3, capped to min(3, 2) = 2 → BOTH
      // descriptors drawn. `strong` (pure power) is attributed to the power
      // inspirer, `swift` (pure speed) to the speed inspirer.
      List<EntityId> attrFor(List<Inspirer> ins) => _resolver.resolve(
            trainedFamilyId: 'basic_punch',
            inspirers: ins,
            descriptorPool: [
              _d('strong', {'power': 4}),
              _d('swift', {'speed': 5}),
            ],
            rng: _seedWithFirstDrawBelow(0.30),
          ).inspirerInstanceIds;
      final power = _insp(1, {'power': 6}, mastery: 3, usage: 9);
      final speed = _insp(2, {'speed': 6}, mastery: 3, usage: 9);
      // A List (not a Set), and ascending by eligible index == position in
      // the passed iterable, regardless of draw order.
      expect(attrFor([power, speed]), [const EntityId(1), const EntityId(2)]);
      // swapped order → result follows the NEW eligible index, [#2, #1].
      expect(attrFor([speed, power]), [const EntityId(2), const EntityId(1)]);
    });

    test('attribution adds no rng draw', () {
      // Two runs from the same seed: the rng state after resolve is
      // identical, and equals a hand-advanced generator that made exactly
      // (1 discovery roll + k weightedPick draws).
      //
      // 2 eligible inspirers, w = 3*sqrt(9) = 9 each → ΣW = 18, c = 0.5 →
      // p = 0.05 + 0.55*0.5 = 0.325. The brief's literal seed 20260903 has
      // a first draw of 0.3776 (> p → no discovery), so scan for a seed
      // whose first draw is below p instead. k == 2 here (strong blend over
      // a 2-descriptor pool) → 1 discovery roll + 2 weightedPick draws = 3.
      final seed = _seedIntWithFirstDrawBelow(0.325);
      final r1 = RngService(seed);
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 3, usage: 9),
          _insp(2, {'speed': 6}, mastery: 3, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4}), _d('swift', {'speed': 5})],
        rng: r1,
      );
      expect(res.discovered, isTrue);
      // k == 2 here → 1 + 2 == 3 draws total from r1.
      final r2 = RngService(seed);
      for (var i = 0; i < 3; i++) {
        r2.nextDouble();
      }
      expect(r1.nextDouble(), r2.nextDouble());
    });
  });

  group('concentration & roll bounds', () {
    test('p stays in [0,1] and is monotonic in concentration', () {
      // even 3-way spread → c == 1/3 → p = 0.05 + 0.55*(1/3) ≈ 0.23333.
      // hit seed < 0.23 (< p); miss seed >= 0.24 (> p).
      final spread = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 2, usage: 9),
          _insp(2, {'power': 5}, mastery: 2, usage: 9),
          _insp(3, {'power': 5}, mastery: 2, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.23),
      );
      expect(spread.discovered, isTrue);
      final spreadMiss = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 2, usage: 9),
          _insp(2, {'power': 5}, mastery: 2, usage: 9),
          _insp(3, {'power': 5}, mastery: 2, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawAtLeast(0.24),
      );
      expect(spreadMiss.discovered, isFalse);
    });
  });

  group('determinism', () {
    test('identical inputs + RngService(seed) → identical result twice', () {
      InspirationResult run() => _resolver.resolve(
            trainedFamilyId: 'basic_punch',
            inspirers: [
              _insp(1, {'power': 6}, mastery: 3, usage: 16),
              _insp(2, {'speed': 5}, mastery: 2, usage: 9),
            ],
            descriptorPool: [
              _d('strong', {'power': 4}),
              _d('swift', {'speed': 5}),
              _d('iron', {'power': 5, 'endurance': 2}),
            ],
            rng: RngService(20260903),
          );
      final a = run();
      final b = run();
      expect(a.discovered, b.discovered);
      expect(a.descriptorIds, b.descriptorIds);
      expect(a.inspirerInstanceIds, b.inspirerInstanceIds);
    });
  });
}

void _compatibilityTests() {
  group('descriptorCompatibleWithFamily', () {
    test('no family tag → universal', () {
      expect(descriptorCompatibleWithFamily(_d('strong', {'power': 4}), 'basic_kick'), isTrue);
    });
    test('matching family tag → compatible', () {
      expect(
        descriptorCompatibleWithFamily(
          _d('kicker', {'power': 4}, tags: {'family:basic_kick'}), 'basic_kick'),
        isTrue);
    });
    test('non-matching family tag → incompatible', () {
      expect(
        descriptorCompatibleWithFamily(
          _d('puncher', {'power': 4}, tags: {'family:basic_punch'}), 'basic_kick'),
        isFalse);
    });
  });

  group('draw respects compatibility', () {
    test('a family:basic_kick descriptor is never drawn for basic_punch training', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [
          _d('kickonly', {'power': 9}, tags: {'family:basic_kick'}),
          _d('strong', {'power': 4}),
        ],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.descriptorIds, {'strong'});
    });

    test('all pooled descriptors restricted away → none', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('kickonly', {'power': 9}, tags: {'family:basic_kick'})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.discovered, isFalse);
    });
  });

  group('descriptor count k', () {
    List<TechniqueDescriptor> pool() => [
          _d('strong', {'power': 4}),
          _d('swift', {'speed': 5}),
          _d('iron', {'power': 5, 'endurance': 2}),
          _d('bull', {'power': 6}),
        ];

    test('single ordinary source → 1', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 5}, mastery: 1, usage: 9)],
        descriptorPool: pool(),
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.descriptorIds, hasLength(1));
    });

    test('single strong source → still 1 (strong needs 2+ eligible)', () {
      // ONE eligible inspirer, mastery 3 + usage 30 → w = 3*sqrt(30) ≈ 16.4
      // (>= kInspirationStrongWeightBar 6.0) and mastery 3 >=
      // kInspirationStrongMasteryBar 2 — both "strong" sub-conditions are
      // met, but `strong` also requires eligible.length >= 2, so k stays 1.
      // Single inspirer → c = 1.0 → p = 0.60.
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 6}, mastery: 3, usage: 30)],
        descriptorPool: pool(),
        rng: _seedWithFirstDrawBelow(0.60),
      );
      expect(res.discovered, isTrue);
      expect(res.descriptorIds, hasLength(1));
    });

    test('two ordinary sources → 2', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 1, usage: 9),
          _insp(2, {'speed': 5}, mastery: 1, usage: 9),
        ],
        descriptorPool: pool(),
        rng: _seedWithFirstDrawBelow(0.30),
      );
      expect(res.descriptorIds, hasLength(2));
    });

    test('two strong sources → 3 (mean mastery ≥ 2 and Σw ≥ 6.0)', () {
      // each: mastery 3, usage 9 → w = 3*3 = 9; Σw = 18; mean mastery 3
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 3, usage: 9),
          _insp(2, {'speed': 6}, mastery: 3, usage: 9),
        ],
        descriptorPool: pool(),
        rng: _seedWithFirstDrawBelow(0.30),
      );
      expect(res.descriptorIds, hasLength(3));
    });

    test('k never exceeds the compatible pool size', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 3, usage: 9),
          _insp(2, {'speed': 6}, mastery: 3, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4})], // only 1 compatible
        rng: _seedWithFirstDrawBelow(0.30),
      );
      expect(res.descriptorIds, hasLength(1));
      expect(res.discovered, isTrue);
    });
  });

  group('exclusion retry', () {
    test('the only reachable blend is excluded → none after the retries', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
        exclude: {
          {'strong'}
        },
      );
      expect(res.discovered, isFalse);
    });

    test('a non-matching exclude set does not block the draw', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [_insp(1, {'power': 8}, mastery: 3, usage: 30)],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
        exclude: {
          {'swift'}
        },
      );
      expect(res.descriptorIds, {'strong'});
    });

    test('a near-duplicate ({strong,fast} vs owned {strong,swift}) is allowed', () {
      final res = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 6}, mastery: 2, usage: 9),
          _insp(2, {'speed': 6}, mastery: 2, usage: 9),
        ],
        descriptorPool: [_d('strong', {'power': 4}), _d('fast', {'speed': 4})],
        rng: _seedWithFirstDrawBelow(0.30),
        exclude: {
          {'strong', 'swift'}
        },
      );
      expect(res.discovered, isTrue);
      expect(res.descriptorIds, {'strong', 'fast'});
    });
  });
}

// --- seed helpers: RngService is a deterministic LCG-ish stream; scan
// seeds until the first nextDouble() lands where the test needs it. Keep
// the scan bounded and assert it found one.
RngService _seedWithFirstDrawBelow(double bound) => _scanSeed((v) => v < bound);
RngService _seedWithFirstDrawAtLeast(double bound) =>
    _scanSeed((v) => v >= bound);
RngService _seedWithFirstDrawBetween(double lo, double hi) =>
    _scanSeed((v) => v >= lo && v < hi);
RngService _seedThatDiscoversAndDraws() => _seedWithFirstDrawBelow(0.46);

int _seedIntWithFirstDrawBelow(double bound) {
  for (var s = 1; s < 5000; s++) {
    if (RngService(s).nextDouble() < bound) return s;
  }
  fail('no seed found for the required first draw');
}

RngService _scanSeed(bool Function(double first) ok) {
  for (var s = 1; s < 5000; s++) {
    if (ok(RngService(s).nextDouble())) return RngService(s);
  }
  fail('no seed found for the required first draw');
}
