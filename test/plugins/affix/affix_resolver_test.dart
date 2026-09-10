import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

ContentRegistry _content() => ContentRegistry()..loadAll(affixContentDefinitions);

class _CountingRng extends RngService {
  _CountingRng(int seed) : super(seed);
  int doubles = 0;
  @override
  double nextDouble() {
    doubles++;
    return super.nextDouble();
  }
}

AffixResolution _resolve(int seed, AffixDomain domain, String? tradition,
        {RngService? rng}) =>
    resolveRewardAffixes(
      ctx: AffixRewardContext(domain: domain, physiqueTradition: tradition),
      rng: rng ?? RngService(seed),
      content: _content(),
    );

void main() {
  test('deterministic: same seed + ctx => equal resolution', () {
    expect(_resolve(7, AffixDomain.item, 'western'),
        equals(_resolve(7, AffixDomain.item, 'western')));
  });

  test('always exactly 2 slots, positions 0/1, slotKinds prefix/suffix', () {
    final r = _resolve(1, AffixDomain.technique, null);
    expect(r.slots, hasLength(2));
    expect(r.slots[0].position, 0);
    expect(r.slots[0].slotKind, 'prefix');
    expect(r.slots[1].position, 1);
    expect(r.slots[1].slotKind, 'suffix');
  });

  test('all four (prefix?, suffix?) states occur across seeds, both domains', () {
    for (final domain in AffixDomain.values) {
      final seen = <String>{};
      for (var seed = 0; seed < 400; seed++) {
        final r = _resolve(seed, domain, null);
        seen.add('${r.slots[0].affix == null}/${r.slots[1].affix == null}');
      }
      expect(seen, containsAll(<String>{'true/true', 'true/false', 'false/true', 'false/false'}),
          reason: 'domain $domain must reach none / suffix-only / prefix-only / both');
    }
  });

  test('affinity weighting: western favours force, eastern favours flow', () {
    int forceCount(String? tradition) {
      var n = 0;
      for (var seed = 0; seed < 600; seed++) {
        for (final s in _resolve(seed, AffixDomain.item, tradition).slots) {
          if (s.affix?.lean == AffixLean.force) n++;
        }
      }
      return n;
    }

    expect(forceCount('western'), greaterThan(forceCount('eastern')));
    expect(forceCount('western'), greaterThan(forceCount(null)));
  });

  test('draw order + count: one nextDouble per no-affix slot, two per affixed slot', () {
    // seed chosen so both slots land affixed (verify, then assert count)
    for (var seed = 0; seed < 50; seed++) {
      final rng = _CountingRng(seed);
      final r = _resolve(seed, AffixDomain.item, null, rng: rng);
      final affixed = r.slots.where((s) => s.affix != null).length;
      final empty = 2 - affixed;
      expect(rng.doubles, empty * 1 + affixed * 2,
          reason: 'seed $seed: $empty empty (1 draw) + $affixed affixed (2 draws)');
    }
  });

  test('resolution is inert: reading slots consumes nothing / mutates nothing', () {
    final rng = _CountingRng(3);
    final r = _resolve(3, AffixDomain.item, null, rng: rng);
    final before = rng.doubles;
    r.slots.map((s) => s.affix?.id).toList();
    r.slots.map((s) => s.slotKind).toList();
    expect(rng.doubles, before);
  });
}
