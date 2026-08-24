import 'run_result.dart';

/// Formats [result] into a human-readable Playtest Report — a developer
/// can `print(formatPlaytestReport(...))` or write it to a file; no UI
/// involved.
String formatPlaytestReport(RunResult result) {
  final totalAttempts = result.trainingRecords.fold<int>(0, (sum, r) => sum + r.attemptCount);
  final averageQuality = result.trainingRecords.isEmpty
      ? null
      : result.trainingRecords.map((r) => r.averageQuality).reduce((a, b) => a + b) /
          result.trainingRecords.length;

  final buffer = StringBuffer()
    ..writeln('Playtest Report — ${result.characterName} (seed ${result.seed})')
    ..writeln('=' * 40)
    ..writeln('Run duration:        ${result.runDuration.inMicroseconds} us')
    ..writeln('Cycles completed:    ${result.cyclesCompleted}')
    ..writeln('Encounter count:     ${result.encounters.length}')
    ..writeln('Result:              ${result.won ? 'WIN' : 'LOSS'}')
    ..writeln('Physique:            ${result.physiqueId}')
    ..writeln('Martial tradition:   ${result.martialTradition}')
    ..writeln('Style:               ${result.styleId}')
    ..writeln('Final Tome:          ${result.finalBuild.map((c) => c.contentId).join(', ')}')
    ..writeln('Items discovered:    ${result.itemsDiscovered.join(', ')}')
    ..writeln('Items unlocked:      ${result.itemsUnlocked.join(', ')}')
    ..writeln('Techniques learned:  ${result.techniquesLearned.join(', ')}')
    ..writeln('Techniques evolved:  ${result.techniquesEvolved.join(', ')}')
    ..writeln('Training attempts:   $totalAttempts')
    ..writeln(
        'Training performance: ${averageQuality == null ? 'n/a' : averageQuality.toStringAsFixed(3)}')
    ..writeln('Rewards chosen:      ${result.rewardsGranted.join(', ')}')
    ..writeln()
    ..writeln('Encounters:')
    ..writeln(result.encounters
        .map((e) => '  ${e.name.padRight(20)} vs ${e.enemyId.padRight(16)} '
            '${e.won ? 'WON ' : 'LOST'} (${e.turnsUsed} turns, ${e.playerHealthAfter} HP left)')
        .join('\n'));

  return buffer.toString();
}
