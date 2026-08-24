import 'package:build_engine/game.dart';
import 'package:test/test.dart';

void main() {
  test('formatPlaytestReport includes every field the run tracks', () {
    final result = runGame(6);

    final report = formatPlaytestReport(result);

    expect(report, contains(result.characterName));
    expect(report, contains('Run duration'));
    expect(report, contains('Cycles completed'));
    expect(report, contains('Encounter count'));
    expect(report, contains(result.won ? 'WIN' : 'LOSS'));
    expect(report, contains(result.physiqueId));
    expect(report, contains('Martial tradition'));
    expect(report, contains(result.martialTradition));
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

  test('a losing run says LOSS, a surviving-to-the-cap run says WIN', () {
    final died = runGame(1);
    expect(died.won, isFalse);
    expect(formatPlaytestReport(died), contains('LOSS'));
  });
}
