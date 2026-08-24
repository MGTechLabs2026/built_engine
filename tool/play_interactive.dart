// An interactive session of `runGame` (see `lib/game.dart`) for the
// first human gameplay test — decisions come from stdin, narration goes
// to stdout, driven entirely by the existing gameplay telemetry
// (`lib/src/plugins/game/run_events.dart`) plus a few already-existing
// Core/Combat events. Not a UI: plain text prompts and printlns.
//
// Anything that can write lines to this process's stdin and read its
// stdout can play a run this way — a person at a real terminal, or an
// LLM/script driving the process.
//
//   dart run tool/play_interactive.dart [seed]
//
// With no seed, a random one is generated and printed at the top (still
// fully deterministic once known — pass it back in on a later run to
// replay the same encounters/rewards/reward pool order).
//
// This is an endless run — it only ends when you die, or a 200-cycle
// safety cap is reached alive. At the end, the full playtest report
// prints, and the run's `DecisionLog` is written to
// `output/interactive_seed_<seed>.decisions` (one decision per line) —
// replay it exactly with:
//
//   ReplayDecisionPolicy(loadDecisionLog(File(...).readAsStringSync()))

import 'dart:io';
import 'dart:math';

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/physique_plugin.dart';

String _rewardLabel(RewardKind kind) => switch (kind) {
      RewardKind.unlockSlot => 'Unlock a new Tome slot',
      RewardKind.itemOrTechnique => 'Random item or technique',
      RewardKind.upgradePoint => '+1 upgrade point',
    };

String _askName() {
  stdout.writeln('\n=== What is your name? ===');
  stdout.write('> ');
  final line = stdin.readLineSync()?.trim();
  return (line == null || line.isEmpty) ? 'Player' : line;
}

void main(List<String> args) {
  final seed = args.isNotEmpty ? int.parse(args.first) : Random().nextInt(1 << 32);
  stdout.writeln('Seed: $seed (pass it as an argument to replay the same encounters/rewards)');
  final characterName = _askName();

  final events = EventBus();
  events.subscribe<RunStarted>(
    (e) => stdout.writeln('\n--- Run started: ${e.characterName} (seed ${e.seed}) ---'),
  );
  events.subscribe<PhysiqueAssigned>((e) => stdout.writeln('Physique: ${e.physiqueId}'));
  events.subscribe<TomeChanged>((e) => stdout.writeln('Tome changed (${e.stepName}): '
      '${e.components.map((c) => '${c.referenceType}:${c.contentId}').join(', ')}'));
  events.subscribe<CycleStarted>((e) => stdout.writeln('\n===== Cycle ${e.cycleNumber} ====='));
  events.subscribe<RunStatus>((e) {
    stdout.writeln('Health: ${e.health}/${e.maxHealth}   Speed: ${e.initiative}   '
        'Upgrade points: ${e.upgradePoints}');
    final slotLines = [
      for (final s in e.slots)
        if (s.unlocked)
          '  ${s.slot.id}: ${s.occupant == null ? '(empty)' : '${s.occupant!.referenceType}:${s.occupant!.contentId}'}'
        else
          '  ${s.slot.id}: (locked)',
    ];
    stdout.writeln('Tome:\n${slotLines.join('\n')}');
    stdout.writeln('Owned items: ${e.ownedItemIds.isEmpty ? '(none)' : e.ownedItemIds.join(', ')}');
    stdout.writeln(
        'Known techniques: ${e.knownTechniqueIds.isEmpty ? '(none)' : e.knownTechniqueIds.join(', ')}');
  });
  events.subscribe<EncounterStarted>((e) => stdout.writeln('\n>> Fight: ${e.name} vs ${e.enemyId}'));
  events.subscribe<ActionCompleted>(
    (e) => stdout.writeln('   ${e.actor} used ${e.action.runtimeType} -> ${e.targets.join(', ')}'),
  );
  events.subscribe<EncounterResolved>((e) => stdout
      .writeln('<< ${e.name}: ${e.won ? 'WON' : 'LOST'} (player health ${e.playerHealthAfter})'));
  events.subscribe<RewardSelected>((e) => stdout.writeln('Reward chosen: ${_rewardLabel(e.chosen)}'));
  events.subscribe<SubjectDiscovered>((e) => stdout.writeln('Acquired: ${e.subject}'));
  events.subscribe<ResourceChanged>((e) {
    if (e.resource == 'upgrade_points' && e.delta > 0) {
      stdout.writeln('Gained an upgrade point (now ${e.newCurrent}).');
    }
  });
  events.subscribe<SlotUnlocked>((e) => stdout.writeln('*** Tome slot ${e.slot.id} unlocked! ***'));
  events.subscribe<UpgradePointSpent>((e) => stdout.writeln('Upgrade point spent on ${e.target}.'));
  events.subscribe<TrainingStarted>((e) => stdout.writeln('\n>> Training: ${e.subject}'));
  events.subscribe<TrainingResultRecorded>(
    (e) => stdout.writeln('<< Training result for ${e.subject}: gain ${e.gain}'),
  );
  events.subscribe<TechniqueEvolved>((e) => stdout.writeln('*** ${e.fromId} evolved into ${e.toId}! ***'));
  events.subscribe<RunEnded>(
    (e) => stdout.writeln('\n--- Run ended: ${e.won ? 'WIN' : 'LOSS'} (${e.encounterCount} encounters) ---'),
  );

  final result = runGame(seed, characterName: characterName, policy: ConsoleDecisionPolicy(), eventBus: events);

  stdout.writeln('\n${formatPlaytestReport(result)}');

  final outputDir = Directory('output')..createSync(recursive: true);
  final logFile = File('${outputDir.path}/interactive_seed_$seed.decisions');
  logFile.writeAsStringSync(saveDecisionLog(result.decisionLog));
  stdout.writeln('Decision log saved to ${logFile.path} — replay with:');
  stdout.writeln('  runGame($seed, policy: ReplayDecisionPolicy(loadDecisionLog(File('
      "'${logFile.path}'"
      ').readAsStringSync())))');
}
