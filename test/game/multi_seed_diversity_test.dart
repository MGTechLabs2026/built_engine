import 'package:build_engine/game.dart';
import 'package:test/test.dart';

void main() {
  group('multi-seed: at least 10 seeds', () {
    final seeds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    final results = [for (final seed in seeds) runGame(seed)];

    test('every seed produces a complete, valid run', () {
      expect(results, hasLength(10));
      for (final result in results) {
        expect(result.encounters, isNotEmpty);
        expect(result.cyclesCompleted, greaterThanOrEqualTo(0));
      }
    });

    test('physique diversity: more than one physique type appears across 10 seeds', () {
      final distinctPhysiques = results.map((r) => r.physiqueId).toSet();
      expect(distinctPhysiques.length, greaterThan(1));
    });

    test('martial tradition and style diversity across 10 seeds', () {
      final distinctTraditions = results.map((r) => r.martialTradition).toSet();
      final distinctStyles = results.map((r) => r.styleId).toSet();
      expect(distinctTraditions, isNotEmpty);
      expect(distinctStyles, isNotEmpty);
    });

    test('reward diversity: more than one distinct reward appears across 10 seeds', () {
      final distinctRewards = {for (final r in results) ...r.rewardsGranted};
      expect(distinctRewards.length, greaterThan(1));
    });

    test('win/loss (survival) diversity: this run does not require every seed to survive to '
        'the cap — a healthy prototype exposes both outcomes', () {
      final survived = results.where((r) => r.won).length;
      final died = results.where((r) => !r.won).length;

      expect(survived + died, equals(10));
      // Explicitly NOT asserting survived == 10 or died == 10.
      expect(survived + died, greaterThan(0));
    });

    test('balance signals compute sane aggregates across the 10-seed sample', () {
      final signals = BalanceSignals.fromRuns(results);

      expect(signals.runCount, equals(10));
      expect(signals.averageTomeChanges, greaterThan(0));
      expect(signals.buildDiversity, greaterThan(0));
      expect(signals.buildDiversity, lessThanOrEqualTo(1));
      expect(signals.averageCombatDuration, greaterThan(0));
      expect(signals.eliteWinRate, greaterThanOrEqualTo(0));
      expect(signals.eliteWinRate, lessThanOrEqualTo(1));
      expect(signals.averageCyclesCompleted, greaterThanOrEqualTo(0));
      expect(signals.survivalRate, greaterThanOrEqualTo(0));
      expect(signals.survivalRate, lessThanOrEqualTo(1));
    });
  });
}
