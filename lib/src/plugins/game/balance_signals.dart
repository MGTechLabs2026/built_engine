import 'run_result.dart';

/// Aggregate measurements across several [RunResult]s — the milestone's
/// own "Balance Signals" section. Purely descriptive: nothing here tunes
/// any number, it only measures what the current content already
/// produces ("We are measuring," per the milestone).
class BalanceSignals {
  const BalanceSignals({
    required this.runCount,
    required this.averageTimeToFirstReward,
    required this.averageTimeToFirstItemMastery,
    required this.averageTimeToFirstTechniqueEvolution,
    required this.averageTomeChanges,
    required this.averageTrainingAttempts,
    required this.buildDiversity,
    required this.averageCombatDuration,
    required this.bossWinRate,
  });

  factory BalanceSignals.fromRuns(List<RunResult> runs) {
    if (runs.isEmpty) {
      return const BalanceSignals(
        runCount: 0,
        averageTimeToFirstReward: null,
        averageTimeToFirstItemMastery: null,
        averageTimeToFirstTechniqueEvolution: null,
        averageTomeChanges: 0,
        averageTrainingAttempts: 0,
        buildDiversity: 0,
        averageCombatDuration: 0,
        bossWinRate: 0,
      );
    }

    double? averageOfPresent(Iterable<int?> values) {
      final present = [for (final v in values) if (v != null) v];
      if (present.isEmpty) return null;
      return present.reduce((a, b) => a + b) / present.length;
    }

    final totalTrainingAttempts = [
      for (final run in runs)
        run.trainingRecords.fold<int>(0, (sum, r) => sum + r.attemptCount),
    ];
    final totalCombatTurns = [
      for (final run in runs) ...[for (final e in run.encounters) e.turnsUsed],
    ];
    final distinctBuilds = {
      for (final run in runs)
        run.finalBuild.map((c) => '${c.referenceType}:${c.contentId}').toList().join(','),
    };
    final bossWins = runs
        .where((r) => r.encounters.any((e) => e.name == 'Boss' && e.won))
        .length;

    return BalanceSignals(
      runCount: runs.length,
      averageTimeToFirstReward: averageOfPresent(runs.map((r) => r.firstRewardStep)),
      averageTimeToFirstItemMastery: averageOfPresent(runs.map((r) => r.firstItemMasteryStep)),
      averageTimeToFirstTechniqueEvolution:
          averageOfPresent(runs.map((r) => r.firstTechniqueEvolutionStep)),
      averageTomeChanges: runs.map((r) => r.tomeHistory.length).reduce((a, b) => a + b) / runs.length,
      averageTrainingAttempts: totalTrainingAttempts.isEmpty
          ? 0
          : totalTrainingAttempts.reduce((a, b) => a + b) / runs.length,
      buildDiversity: distinctBuilds.length / runs.length,
      averageCombatDuration:
          totalCombatTurns.isEmpty ? 0 : totalCombatTurns.reduce((a, b) => a + b) / totalCombatTurns.length,
      bossWinRate: bossWins / runs.length,
    );
  }

  final int runCount;
  final double? averageTimeToFirstReward;
  final double? averageTimeToFirstItemMastery;
  final double? averageTimeToFirstTechniqueEvolution;
  final double averageTomeChanges;
  final double averageTrainingAttempts;

  /// Distinct final builds / total runs — `1.0` means every run ended
  /// with a unique build, `1/runCount` means every run converged on the
  /// same one.
  final double buildDiversity;
  final double averageCombatDuration;
  final double bossWinRate;
}
