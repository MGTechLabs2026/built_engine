import 'package:build_engine/game.dart';
import 'package:test/test.dart';

void main() {
  test('formatPlaytestReport includes every field the milestone asks for', () {
    final result = runGame(6);

    final report = formatPlaytestReport(result);

    expect(report, contains('Run duration'));
    expect(report, contains('Encounter count'));
    expect(report, contains('WIN'));
    expect(report, contains(result.physiqueId));
    expect(report, contains(result.styleId));
    expect(report, contains('Final Tome'));
    expect(report, contains('Items discovered'));
    expect(report, contains('Items unlocked'));
    expect(report, contains('Techniques learned'));
    expect(report, contains('Techniques evolved'));
    expect(report, contains('Training attempts'));
    expect(report, contains('Training performance'));
    expect(report, contains('Rewards chosen'));
    for (final encounter in result.encounters) {
      expect(report, contains(encounter.name));
    }
  });

  test('a loss report says LOSS, not WIN', () {
    final report = formatPlaytestReport(runGame(1));

    expect(report, contains('LOSS'));
  });
}
