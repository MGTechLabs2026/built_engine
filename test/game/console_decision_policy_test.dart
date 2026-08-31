import 'package:build_engine/build_engine.dart';
import 'package:build_engine/console_policy.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

/// A scripted stdin/stdout stand-in — feeds pre-set answers one line at a
/// time and records everything printed, so `ConsoleDecisionPolicy` can be
/// tested without a real terminal.
class ScriptedIO {
  ScriptedIO(this.answers);

  final List<String> answers;
  final List<String> printed = [];
  var _index = 0;

  void print(String line) => printed.add(line);

  String? readLine() => _index < answers.length ? answers[_index++] : null;
}

void main() {
  group('ConsoleDecisionPolicy: prompt/answer parsing', () {
    test('chooseMartialTradition accepts a numeric index', () {
      final io = ScriptedIO(['1']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseMartialTradition(const [MartialTraditions.western, MartialTraditions.eastern]);

      expect(choice, equals(MartialTraditions.eastern));
    });

    test('chooseStartingStyle accepts a numeric index', () {
      final io = ScriptedIO(['1']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseStartingStyle(const ['polearming', 'shaolin', 'taiChi']);

      expect(choice, equals('shaolin'));
    });

    test('chooseStartingStyle accepts the exact label, case-insensitively', () {
      final io = ScriptedIO(['SHAOLIN']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseStartingStyle(const ['polearming', 'shaolin', 'taiChi']);

      expect(choice, equals('shaolin'));
    });

    test('an invalid answer reprompts instead of crashing', () {
      final io = ScriptedIO(['not a number', '99', '0']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseStartingStyle(const ['polearming', 'shaolin']);

      expect(choice, equals('polearming'));
      expect(io.printed.any((l) => l.contains('Not a valid choice')), isTrue);
    });

    test('chooseCombatOrTraining returns the chosen candidate', () {
      final io = ScriptedIO(['training']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseCombatOrTraining(const ['combat', 'training']);

      expect(choice, equals('training'));
    });

    test('chooseReward formats RewardKind values as readable labels and returns the chosen index', () {
      final io = ScriptedIO(['1']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);
      const candidates = [RewardKind.unlockSlot, RewardKind.itemOrTechnique, RewardKind.upgradePoint];

      final choice = policy.chooseReward(candidates);

      expect(choice, equals(1));
      expect(io.printed, contains('  [0] Unlock a new Tome slot'));
      expect(io.printed, contains('  [1] Random item or technique'));
      expect(io.printed, contains('  [2] +1 upgrade point'));
    });

    test('chooseTrainingTarget returns the chosen candidate string', () {
      final io = ScriptedIO(['technique:basic_slash']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseTrainingTarget(const ['item:iron_knuckle', 'technique:basic_slash']);

      expect(choice, equals('technique:basic_slash'));
    });

    test('chooseSlot returns the SlotId at the chosen index', () {
      final io = ScriptedIO(['0']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);
      const component = BuildComponentRef(referenceType: 'item', contentId: 'iron_knuckle');

      final choice = policy.chooseSlot(component, [const SlotId('slot_1'), const SlotId('slot_2')]);

      expect(choice, equals(const SlotId('slot_1')));
    });

    test('chooseReplace accepts y/yes and n/no, case-insensitively', () {
      final yes = ScriptedIO(['YES']);
      final yesPolicy = ConsoleDecisionPolicy(print: yes.print, readLine: yes.readLine);
      expect(
        yesPolicy.chooseReplace(
          const SlotId('slot_1'),
          const BuildComponentRef(referenceType: 'item', contentId: 'a'),
          const BuildComponentRef(referenceType: 'item', contentId: 'b'),
        ),
        isTrue,
      );

      final no = ScriptedIO(['n']);
      final noPolicy = ConsoleDecisionPolicy(print: no.print, readLine: no.readLine);
      expect(
        noPolicy.chooseReplace(
          const SlotId('slot_1'),
          const BuildComponentRef(referenceType: 'item', contentId: 'a'),
          const BuildComponentRef(referenceType: 'item', contentId: 'b'),
        ),
        isFalse,
      );
    });

    test('chooseUpgradeSpend returns the chosen candidate string', () {
      final io = ScriptedIO(['stat:attack']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseUpgradeSpend(const ['stat:health', 'stat:attack', 'stat:speed', 'skip']);

      expect(choice, equals('stat:attack'));
    });

    test('chooseTomeAction returns the chosen candidate string', () {
      final io = ScriptedIO(['1']);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      final choice = policy.chooseTomeAction(const ['equip:item:knife', 'done', 'unequip:slot_1:item:cloth_armor']);

      expect(choice, equals('done'));
    });

    test('when answers run out (stdin closed), every remaining decision falls back to the '
        'same default DefaultRunDecisionPolicy uses', () {
      final io = ScriptedIO(const []);
      final policy = ConsoleDecisionPolicy(print: io.print, readLine: io.readLine);

      expect(policy.chooseStartingStyle(const ['polearming', 'shaolin']), equals('polearming'));
      expect(policy.chooseUpgradeSpend(const ['stat:health', 'skip']), equals('stat:health'));
      expect(
        policy.chooseReplace(
          const SlotId('slot_1'),
          const BuildComponentRef(referenceType: 'item', contentId: 'a'),
          const BuildComponentRef(referenceType: 'item', contentId: 'b'),
        ),
        isTrue,
      );
    });
  });

  group('ConsoleDecisionPolicy: driving a full run', () {
    test('an all-EOF console session reproduces the exact same run as DefaultRunDecisionPolicy', () {
      final io = ScriptedIO(const []);
      final consoleResult =
          runGame(6, policy: ConsoleDecisionPolicy(print: io.print, readLine: io.readLine));
      final defaultResult = runGame(6);

      expect(consoleResult.won, equals(defaultResult.won));
      expect(consoleResult.finalBuild.map((c) => c.contentId).toSet(),
          equals(defaultResult.finalBuild.map((c) => c.contentId).toSet()));
    });
  });

  group('saveDecisionLog / loadDecisionLog: text round-trip', () {
    test('a saved-then-loaded DecisionLog replays the exact same run', () {
      final original = runGame(6);

      final loaded = loadDecisionLog(saveDecisionLog(original.decisionLog));
      final replay = runGame(6, policy: ReplayDecisionPolicy(loaded));

      expect(replay.won, equals(original.won));
      expect(replay.finalBuild.map((c) => (c.referenceType, c.contentId)),
          equals(original.finalBuild.map((c) => (c.referenceType, c.contentId))));
    });

    test('round-trip preserves every field exactly', () {
      final log = runGame(6).decisionLog;

      final loaded = loadDecisionLog(saveDecisionLog(log));

      expect(loaded.martialTradition, equals(log.martialTradition));
      expect(loaded.startingStyle, equals(log.startingStyle));
      expect(loaded.combatOrTrainingChoices, equals(log.combatOrTrainingChoices));
      expect(loaded.rewardChoices, equals(log.rewardChoices));
      expect(loaded.trainingChoices, equals(log.trainingChoices));
      expect(loaded.slotChoices, equals(log.slotChoices));
      expect(loaded.replaceChoices, equals(log.replaceChoices));
      expect(loaded.upgradeSpendChoices, equals(log.upgradeSpendChoices));
      expect(loaded.tomeActionChoices, equals(log.tomeActionChoices));
    });
  });
}
