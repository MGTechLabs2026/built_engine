import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('empty profile returns zero/empty for every lookup', () {
    expect(EffectProfile.empty.tier(EffectTier.permanent), isEmpty);
    expect(EffectProfile.empty.amount(EffectTier.active, 'damage'), 0);
  });

  test('tier() returns exactly what was constructed', () {
    final p = EffectProfile.of({
      EffectTier.supporting: {'blade': 3, 'fist': -1},
    });
    expect(p.tier(EffectTier.supporting), {'blade': 3, 'fist': -1});
    expect(p.tier(EffectTier.permanent), isEmpty);
  });

  test('amount() returns 0 for an absent tier or an absent stat key', () {
    final p = EffectProfile.of({
      EffectTier.active: {'damage': 5},
    });
    expect(p.amount(EffectTier.active, 'damage'), 5);
    expect(p.amount(EffectTier.active, 'unknown_stat'), 0);
    expect(p.amount(EffectTier.permanent, 'damage'), 0);
  });

  test('negative amounts are legal', () {
    final p = EffectProfile.of({
      EffectTier.supporting: {'blade': -4},
    });
    expect(p.amount(EffectTier.supporting, 'blade'), -4);
  });

  test('tier() and the profile itself are immutable to external mutation', () {
    final source = {
      EffectTier.permanent: {'damage': 1},
    };
    final p = EffectProfile.of(source);
    source[EffectTier.permanent]!['damage'] = 999; // mutate the ORIGINAL map
    expect(p.amount(EffectTier.permanent, 'damage'), 1); // unaffected

    expect(() => p.tier(EffectTier.permanent)['damage'] = 999,
        throwsUnsupportedError); // returned map itself is unmodifiable
  });

  test('merge is additive, tier-by-tier, stat-by-stat', () {
    final a = EffectProfile.of({
      EffectTier.supporting: {'blade': 3, 'fist': 2},
      EffectTier.permanent: {'initiative': 1},
    });
    final b = EffectProfile.of({
      EffectTier.supporting: {'blade': 1},
      EffectTier.active: {'damage': 5},
    });
    final merged = a.merge(b);
    expect(merged.tier(EffectTier.supporting), {'blade': 4, 'fist': 2});
    expect(merged.amount(EffectTier.permanent, 'initiative'), 1);
    expect(merged.amount(EffectTier.active, 'damage'), 5);
  });

  test('merge with empty is a no-op', () {
    final a = EffectProfile.of({
      EffectTier.active: {'damage': 5},
    });
    expect(a.merge(EffectProfile.empty).amount(EffectTier.active, 'damage'), 5);
    expect(EffectProfile.empty.merge(a).amount(EffectTier.active, 'damage'), 5);
  });
}
