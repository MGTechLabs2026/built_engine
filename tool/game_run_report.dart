// Runs the headless game (`runGame`, see `lib/game.dart`) across several
// seeds and writes a Playtest Report per seed, plus a combined
// diversity/balance-signals summary, to `output/`.
//
// This is a reporting/inspection tool, not a test — pass/fail correctness
// is already covered by `test/game/`. Run it with:
//
//   dart run tool/game_run_report.dart [seed ...]
//
// With no arguments, runs a default spread of 10 seeds.
//
// Mirrors `tool/vertical_slice_report.dart`'s structure for the older
// vertical-slice proof — that tool is retained unchanged; this is its
// counterpart for the newer `runGame` endless-loop player loop.

import 'dart:io';

import 'package:build_engine/game.dart';

void main(List<String> args) {
  final seeds = args.isNotEmpty ? args.map(int.parse).toList() : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  final outputDir = Directory('output')..createSync(recursive: true);
  final results = <RunResult>[];

  for (final seed in seeds) {
    final result = runGame(seed);
    results.add(result);
    File('${outputDir.path}/game_run_seed_$seed.txt').writeAsStringSync(formatPlaytestReport(result));
  }

  final signals = BalanceSignals.fromRuns(results);
  final distinctPhysiques = results.map((r) => r.physiqueId).toSet();
  final distinctTraditions = results.map((r) => r.martialTradition).toSet();
  final distinctStyles = results.map((r) => r.styleId).toSet();
  final distinctRewards = {for (final r in results) ...r.rewardsGranted};
  final distinctEvolutions = {for (final r in results) ...r.techniquesEvolved};
  final wins = results.where((r) => r.won).length;

  final summary = StringBuffer()
    ..writeln('Headless game run — multi-seed report')
    ..writeln('Seeds: ${seeds.join(', ')}')
    ..writeln()
    ..writeln(
      '${'seed'.padRight(6)}${'physique'.padRight(10)}${'tradition'.padRight(10)}${'style'.padRight(10)}'
      '${'result'.padRight(8)}${'cycles'.padRight(8)}evolved',
    );
  for (var i = 0; i < seeds.length; i++) {
    final r = results[i];
    summary.writeln(
      '${'${seeds[i]}'.padRight(6)}${r.physiqueId.padRight(10)}${r.martialTradition.padRight(10)}'
      '${r.styleId.padRight(10)}${(r.won ? 'WIN' : 'LOSS').padRight(8)}'
      '${'${r.cyclesCompleted}'.padRight(8)}${r.techniquesEvolved.join(',')}',
    );
  }
  summary
    ..writeln()
    ..writeln('Diversity:')
    ..writeln('  physique diversity:  ${distinctPhysiques.length} distinct (${distinctPhysiques.join(', ')})')
    ..writeln('  tradition diversity: ${distinctTraditions.length} distinct (${distinctTraditions.join(', ')})')
    ..writeln('  style diversity:     ${distinctStyles.length} distinct (${distinctStyles.join(', ')})')
    ..writeln('  reward diversity:    ${distinctRewards.length} distinct')
    ..writeln('  evolution diversity: ${distinctEvolutions.length} distinct (${distinctEvolutions.join(', ')})')
    ..writeln('  win/loss:            $wins survived / ${seeds.length - wins} died')
    ..writeln()
    ..writeln('Balance signals (measured, not tuned):')
    ..writeln('  avg time to first reward:              ${signals.averageTimeToFirstReward}')
    ..writeln('  avg time to first item mastery:         ${signals.averageTimeToFirstItemMastery}')
    ..writeln('  avg time to first technique evolution:  ${signals.averageTimeToFirstTechniqueEvolution}')
    ..writeln('  avg Tome changes:                       ${signals.averageTomeChanges.toStringAsFixed(2)}')
    ..writeln('  avg training attempts:                  ${signals.averageTrainingAttempts.toStringAsFixed(2)}')
    ..writeln('  build diversity:                        ${signals.buildDiversity.toStringAsFixed(2)}')
    ..writeln('  avg combat duration (turns/encounter):  ${signals.averageCombatDuration.toStringAsFixed(2)}')
    ..writeln('  elite/boss-tier fight win rate:         ${signals.eliteWinRate.toStringAsFixed(2)}')
    ..writeln('  avg cycles completed:                   ${signals.averageCyclesCompleted.toStringAsFixed(2)}')
    ..writeln('  survival rate (reached the cap):        ${signals.survivalRate.toStringAsFixed(2)}');

  File('${outputDir.path}/game_run_summary.txt').writeAsStringSync(summary.toString());

  stdout.writeln('Wrote ${seeds.length} seed reports + game_run_summary.txt to ${outputDir.path}/');
  stdout.write(summary.toString());
}
