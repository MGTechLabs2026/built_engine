import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  const resolver = EffectProfileResolver();

  EffectProfile p({num permanent = 0, num active = 0, num supporting = 0}) =>
      EffectProfile.of({
        EffectTier.permanent: {'stat': permanent},
        EffectTier.active: {'stat': active},
        EffectTier.supporting: {'stat': supporting},
      });

  test('permanent is counted from owned, regardless of hung', () {
    final result = resolver.resolve(
      owned: [p(permanent: 3)],
      hung: const [],
      stat: 'stat',
    );
    expect(result, 3);
  });

  test('supporting is counted from hung only — an owned-but-unhung '
      "profile's supporting tier does not count", () {
    final ownedOnly = p(supporting: 4);
    final result = resolver.resolve(
      owned: [ownedOnly],
      hung: const [], // not hung
      stat: 'stat',
    );
    expect(result, 0);

    final resultHung = resolver.resolve(
      owned: [ownedOnly],
      hung: [ownedOnly],
      stat: 'stat',
    );
    expect(resultHung, 4);
  });

  test('active is counted only when passed as usedThisCalculation', () {
    final component = p(active: 7);
    expect(
      resolver.resolve(owned: [component], hung: [component], stat: 'stat'),
      0, // no usedThisCalculation -> active never counted
    );
    expect(
      resolver.resolve(
        owned: [component],
        hung: [component],
        usedThisCalculation: component,
        stat: 'stat',
      ),
      7,
    );
  });

  test('all three tiers sum independently for one stat', () {
    final a = p(permanent: 1, supporting: 2, active: 3);
    final b = p(permanent: 10);
    final result = resolver.resolve(
      owned: [a, b],
      hung: [a],
      usedThisCalculation: a,
      stat: 'stat',
    );
    // permanent: a(1) + b(10) = 11
    // supporting: a(2) (only a is hung)
    // active: a(3) (usedThisCalculation)
    expect(result, 16);
  });

  test('empty inputs return 0', () {
    expect(
      resolver.resolve(owned: const [], hung: const [], stat: 'stat'),
      0,
    );
  });

  test('negative amounts subtract', () {
    final result = resolver.resolve(
      owned: [p(permanent: -5)],
      hung: const [],
      stat: 'stat',
    );
    expect(result, -5);
  });

  test('determinism: two runs, identical inputs, equal output', () {
    final owned = [p(permanent: 2, supporting: 1), p(permanent: 3)];
    final hung = [owned.first];
    final a = resolver.resolve(owned: owned, hung: hung, stat: 'stat');
    final b = resolver.resolve(owned: owned, hung: hung, stat: 'stat');
    expect(a, b);
  });
}
