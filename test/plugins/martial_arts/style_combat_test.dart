// A2 — the authoritative style-scoped combat rules. These are the exact
// numbers the client's CombatAdapter used to compute inline; the engine
// now owns them and the client calls this. Pure: no context, no RNG.
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

Set<String> _fighter({String? style, String? spec}) => {
      'martial',
      if (style != null) 'style:$style',
      if (spec != null) spec,
    };

void main() {
  group('off-specialty penalty', () {
    test('a blade action is unpenalised in-lane (kunlun) and -15% off-lane '
        '(shaolin)', () {
      final kunlun = StyleCombatRules(_fighter(style: 'kunlun'));
      final shaolin = StyleCombatRules(_fighter(style: 'shaolin'));

      expect(kunlun.outgoingDamageFactor(const ['technique', 'blade']), 1.0);
      expect(shaolin.outgoingDamageFactor(const ['technique', 'blade']),
          offSpecialtyDamageFactor);
      expect(offSpecialtyDamageFactor, 0.85);
    });

    test('the factor tracks each style\'s aligned-family data verbatim', () {
      // Exactly the shipped styleAlignedFamilies map — a fist action is
      // in-lane for five styles and off-lane for taiChi (internal / palm
      // / guard / fan), same as the client\'s prior offSpec.
      for (final entry in {
        'polearming': 1.0,
        'wrestling': 1.0,
        'fencing': 1.0,
        'shaolin': 1.0,
        'kunlun': 1.0,
        'taiChi': offSpecialtyDamageFactor,
      }.entries) {
        expect(
          StyleCombatRules(_fighter(style: entry.key))
              .outgoingDamageFactor(const ['technique', 'fist']),
          entry.value,
          reason: '${entry.key} fist action',
        );
      }
    });

    test('neutral content (no recognised family tag) is never penalised', () {
      final shaolin = StyleCombatRules(_fighter(style: 'shaolin'));
      expect(
        shaolin.outgoingDamageFactor(const ['technique', 'aff:power', 'rarity:common']),
        1.0,
      );
    });

    test('a fighter with no known style is never penalised', () {
      final none = StyleCombatRules({'martial'});
      expect(none.outgoingDamageFactor(const ['technique', 'blade']), 1.0);
      expect(none.outgoingDamageFactor(const ['technique', 'palm']), 1.0);
    });
  });

  group('Shaolin Conditioning', () {
    final on = StyleCombatRules(_fighter(style: 'shaolin', spec: MartialSpecs.conditioning));
    final off = StyleCombatRules(_fighter(style: 'shaolin'));

    test('shaves exactly 1 off a multi-point hit', () {
      expect(on.mitigateIncoming(6), 5);
      expect(on.mitigateIncoming(2), 1);
    });

    test('a hit of 1 or less is unchanged (floor 1)', () {
      expect(on.mitigateIncoming(1), 1);
      expect(on.mitigateIncoming(0), 0);
    });

    test('inactive Conditioning leaves damage untouched', () {
      expect(off.mitigateIncoming(6), 6);
      expect(off.conditioning, isFalse);
    });
  });

  group('Kunlun Burst Chain', () {
    final on = StyleCombatRules(_fighter(style: 'kunlun', spec: MartialSpecs.burstChain));
    final off = StyleCombatRules(_fighter(style: 'kunlun'));

    test('escalates +0, +2, +4 across consecutive landed blade hits', () {
      var state = BurstChainState.broken;
      final r1 = on.burstChainOnHit(state, true);
      expect(r1.bonus, 0);
      state = r1.state;
      final r2 = on.burstChainOnHit(state, true);
      expect(r2.bonus, 2);
      state = r2.state;
      final r3 = on.burstChainOnHit(state, true);
      expect(r3.bonus, 4);
    });

    test('a non-blade hit contributes nothing and does not advance the streak',
        () {
      final r = on.burstChainOnHit(const BurstChainState(3), false);
      expect(r.bonus, 0);
      expect(r.state.streak, 3);
    });

    test('resetting to broken drops the bonus back to +0', () {
      var state = on.burstChainOnHit(BurstChainState.broken, true).state; // 1
      state = on.burstChainOnHit(state, true).state; // 2
      state = BurstChainState.broken; // miss / enemy turn
      expect(on.burstChainOnHit(state, true).bonus, 0);
    });

    test('inactive Burst Chain never adds a bonus', () {
      expect(off.burstChainOnHit(const BurstChainState(5), true).bonus, 0);
      expect(off.burstChain, isFalse);
    });
  });
}
