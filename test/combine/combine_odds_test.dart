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
      expect(odds.failPercent, equals(5)); // 10 - 6 = 4, below the floor of 5 -> clamped to 5, deficit redistributed
      expect(odds.normalPercent, equals(78));
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
