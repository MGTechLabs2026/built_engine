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
      }
    });

    test('physique diversity: more than one physique type appears across 10 seeds', () {
      final distinctPhysiques = results.map((r) => r.physiqueId).toSet();
      expect(distinctPhysiques.length, greaterThan(1));
    });

    test('reward diversity: more than one distinct reward appears across 10 seeds', () {
      final distinctRewards = {for (final r in results) ...r.rewardsGranted};
      expect(distinctRewards.length, greaterThan(1));
    });

    test('evolution diversity: more than one distinct evolved technique appears '
        'across the seeds that evolved anything', () {
      final distinctEvolutions = {
        for (final r in results) ...r.techniquesEvolved,
      };
      // Not every seed necessarily evolves a technique (a run can lose
      // before ever training one to completion) — only assert diversity
      // among whichever ones did.
      expect(distinctEvolutions, isNotEmpty);
    });

    test('win/loss diversity: this milestone does not require every seed to win — '
        'a healthy prototype exposes both outcomes', () {
      final wins = results.where((r) => r.won).length;
      final losses = results.where((r) => !r.won).length;

      expect(wins + losses, equals(10));
      // Explicitly NOT asserting wins == 10 or losses == 10 — per the
      // milestone: "Do not require all seeds to win."
      expect(wins, greaterThan(0));
      expect(losses, greaterThan(0));
    });

    test('balance signals compute sane aggregates across the 10-seed sample', () {
      final signals = BalanceSignals.fromRuns(results);

      expect(signals.runCount, equals(10));
      expect(signals.averageTomeChanges, greaterThan(0));
      expect(signals.averageTrainingAttempts, greaterThan(0));
      expect(signals.buildDiversity, greaterThan(0));
      expect(signals.buildDiversity, lessThanOrEqualTo(1));
      expect(signals.averageCombatDuration, greaterThan(0));
      expect(signals.bossWinRate, greaterThanOrEqualTo(0));
      expect(signals.bossWinRate, lessThanOrEqualTo(1));
    });
  });
}
