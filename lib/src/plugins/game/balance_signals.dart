import 'run_result.dart';

/// Aggregate measurements across several [RunResult]s. Purely
/// descriptive: nothing here tunes any number, it only measures what the
/// current content already produces ("We are measuring").
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
    required this.eliteWinRate,
    required this.averageCyclesCompleted,
    required this.survivalRate,
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
        eliteWinRate: 0,
        averageCyclesCompleted: 0,
        survivalRate: 0,
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

    // "Fight 3" of every cycle is the elite/boss-tier fight — every 3rd
    // encounter in each run's flat `encounters` list, in order fought.
    final eliteFights = [
      for (final run in runs)
        for (var i = 2; i < run.encounters.length; i += 3) run.encounters[i],
    ];
    final eliteWins = eliteFights.where((e) => e.won).length;

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
      eliteWinRate: eliteFights.isEmpty ? 0 : eliteWins / eliteFights.length,
      averageCyclesCompleted:
          runs.map((r) => r.cyclesCompleted).reduce((a, b) => a + b) / runs.length,
      survivalRate: runs.where((r) => r.won).length / runs.length,
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

  /// Win rate of every cycle's 3rd ("elite/boss-tier") fight, across
  /// every cycle across every run.
  final double eliteWinRate;

  /// Mean `cyclesCompleted` across runs — the "how far did you get"
  /// balance signal for an endless run.
  final double averageCyclesCompleted;

  /// Fraction of runs that survived to the 200-cycle safety cap.
  final double survivalRate;
}
