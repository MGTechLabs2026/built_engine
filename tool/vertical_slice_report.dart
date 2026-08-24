// Runs the vertical slice (see `test/integration/support/
// vertical_slice_runner.dart`) across several seeds and writes a
// human-readable report per seed, plus a combined summary, to `output/`.
//
// This is a reporting/inspection tool, not a test — pass/fail correctness
// is already covered by `test/integration/vertical_slice_test.dart`. Run
// it with:
//
//   dart run tool/vertical_slice_report.dart [seed ...]
//
// With no arguments, runs a default spread of seeds.

import 'dart:io';

import '../test/integration/support/vertical_slice_runner.dart';

String _reportFor(int seed, VerticalSliceOutcome outcome) {
  final buffer = StringBuffer()
    ..writeln('Vertical slice run — seed $seed')
    ..writeln('=' * 40)
    ..writeln()
    ..writeln('Milestone log:')
    ..writeln(outcome.log.map((step) => '  $step').join('\n'))
    ..writeln()
    ..writeln('Outcomes:')
    ..writeln('  physiqueId:        ${outcome.physiqueId}')
    ..writeln('  rewardedContentId: ${outcome.rewardedContentId}')
    ..writeln('  evolvedContentId:  ${outcome.evolvedContentId}')
    ..writeln('  firstBattleWon:    ${outcome.firstBattleWon}')
    ..writeln('  secondBattleWon:   ${outcome.secondBattleWon}');
  return buffer.toString();
}

void main(List<String> args) {
  final seeds = args.isNotEmpty
      ? args.map(int.parse).toList()
      : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  final outputDir = Directory('output')..createSync(recursive: true);

  final summary = StringBuffer()
    ..writeln('Vertical slice — multi-seed report')
    ..writeln('Seeds: ${seeds.join(', ')}')
    ..writeln();
  summary.writeln(
    '${'seed'.padRight(6)}${'physique'.padRight(12)}${'rewarded'.padRight(14)}'
    '${'evolved'.padRight(24)}${'1st win'.padRight(9)}2nd win',
  );

  for (final seed in seeds) {
    final outcome = runVerticalSlice(seed);

    File('${outputDir.path}/seed_$seed.txt').writeAsStringSync(_reportFor(seed, outcome));

    summary.writeln(
      '${'$seed'.padRight(6)}${outcome.physiqueId.padRight(12)}'
      '${outcome.rewardedContentId.padRight(14)}${outcome.evolvedContentId.padRight(24)}'
      '${'${outcome.firstBattleWon}'.padRight(9)}${outcome.secondBattleWon}',
    );
  }

  File('${outputDir.path}/summary.txt').writeAsStringSync(summary.toString());

  stdout.writeln('Wrote ${seeds.length} seed reports + summary.txt to ${outputDir.path}/');
  stdout.write(summary.toString());
}
