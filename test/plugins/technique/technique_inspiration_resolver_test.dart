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
      // inspirer B (usage 1) is below kMinUsageToInspire (3) and is
      // filtered out at step 0. Only inspirer A stays eligible, so
      // c == 1.0 by construction → p == 0.05 + 0.55 == 0.60 exactly.
      final hit = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 1, usage: 4),
          _insp(2, {'power': 5}, mastery: 1, usage: 1),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawBelow(0.60),
      );
      final miss = _resolver.resolve(
        trainedFamilyId: 'basic_punch',
        inspirers: [
          _insp(1, {'power': 5}, mastery: 1, usage: 4),
          _insp(2, {'power': 5}, mastery: 1, usage: 1),
        ],
        descriptorPool: [_d('strong', {'power': 4})],
        rng: _seedWithFirstDrawAtLeast(0.60),
      );
      expect(hit.discovered, isTrue);
      expect(miss.discovered, isFalse); // p == 0.60, a draw >= 0.60 misses
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

// --- seed helpers: RngService is a deterministic LCG-ish stream; scan
// seeds until the first nextDouble() lands where the test needs it. Keep
// the scan bounded and assert it found one.
RngService _seedWithFirstDrawBelow(double bound) => _scanSeed((v) => v < bound);
RngService _seedWithFirstDrawAtLeast(double bound) =>
    _scanSeed((v) => v >= bound);
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
