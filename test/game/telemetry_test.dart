import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('gameplay telemetry: every new game-level event is observable live via a caller-supplied EventBus', () {
    final events = EventBus();
    final runStarted = <RunStarted>[];
    final runEnded = <RunEnded>[];
    final encounterStarted = <EncounterStarted>[];
    final encounterResolved = <EncounterResolved>[];
    final rewardOffered = <RewardOffered>[];
    final rewardSelected = <RewardSelected>[];
    final trainingStarted = <TrainingStarted>[];
    final trainingResult = <TrainingResultRecorded>[];
    final techniqueEvolved = <TechniqueEvolved>[];
    final tomeChanged = <TomeChanged>[];
    final activeBuildResolved = <ActiveBuildResolved>[];

    events.subscribe<RunStarted>(runStarted.add);
    events.subscribe<RunEnded>(runEnded.add);
    events.subscribe<EncounterStarted>(encounterStarted.add);
    events.subscribe<EncounterResolved>(encounterResolved.add);
    events.subscribe<RewardOffered>(rewardOffered.add);
    events.subscribe<RewardSelected>(rewardSelected.add);
    events.subscribe<TrainingStarted>(trainingStarted.add);
    events.subscribe<TrainingResultRecorded>(trainingResult.add);
    events.subscribe<TechniqueEvolved>(techniqueEvolved.add);
    events.subscribe<TomeChanged>(tomeChanged.add);
    events.subscribe<ActiveBuildResolved>(activeBuildResolved.add);

    final result = runGame(6, eventBus: events);

    // Run started / ended — exactly once each.
    expect(runStarted, hasLength(1));
    expect(runStarted.single.seed, equals(6));
    expect(runEnded, hasLength(1));
    expect(runEnded.single.won, equals(result.won));
    expect(runEnded.single.encounterCount, equals(result.encounters.length));

    // Encounter started/result — one pair per encounter fought.
    expect(encounterStarted, hasLength(result.encounters.length));
    expect(encounterResolved, hasLength(result.encounters.length));
    expect(encounterResolved.last.won, equals(result.encounters.last.won));

    // Reward offered/selected — one pair per reward actually granted.
    expect(rewardSelected, hasLength(result.rewardsGranted.length));
    expect(rewardOffered.length, equals(rewardSelected.length));

    // Training started/result — one pair per TrainingRecord.
    expect(trainingStarted, hasLength(result.trainingRecords.length));
    expect(trainingResult, hasLength(result.trainingRecords.length));

    // Technique evolved — matches RunResult.techniquesEvolved exactly.
    expect(techniqueEvolved, hasLength(result.techniquesEvolved.length));
    if (techniqueEvolved.isNotEmpty) {
      expect(techniqueEvolved.single.toId, equals(result.techniquesEvolved.single));
    }

    // Tome changed — one per tomeHistory entry, same order.
    expect(tomeChanged, hasLength(result.tomeHistory.length));
    expect(tomeChanged.last.stepName, equals(result.tomeHistory.last.afterStep));

    // Build resolved — once per combat encounter (ActiveBuild is
    // resolved right before each fight's actions are interpreted).
    expect(activeBuildResolved, hasLength(result.encounters.length));
  });

  test('events reflecting Core/Combat/Discovery/Mastery telemetry points already fire generically '
      '(no duplicate event published) — PhysiqueAssigned, SubjectDiscovered, MasteryChanged, '
      'ProgressionTierReached, ActionStarted/Completed, BattleWon/Lost', () {
    final events = EventBus();
    var physiqueAssigned = 0;
    var subjectDiscovered = 0;
    var actionCompleted = 0;

    events.subscribe<PhysiqueAssigned>((_) => physiqueAssigned++);
    events.subscribe<SubjectDiscovered>((_) => subjectDiscovered++);
    events.subscribe<ActionCompleted>((_) => actionCompleted++);

    runGame(6, eventBus: events);

    expect(physiqueAssigned, equals(1)); // exactly once, at run start
    expect(subjectDiscovered, greaterThan(0)); // at least the starting item+technique
    expect(actionCompleted, greaterThan(0)); // at least one combat action across the run
  });
}
