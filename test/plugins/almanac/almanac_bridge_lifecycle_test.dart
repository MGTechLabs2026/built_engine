/// Phase 7 §13.1 / §11.4 — `HeadlessGameAlmanacBridge` subscription
/// lifecycle correctness.
///
/// The bridge owns every `EventSubscription` it creates; a fresh bridge is
/// built per run; `detach()` cancels all subscriptions, sets `_disposed`,
/// and is idempotent; there is no static / module listener; two sequential
/// runs never cross-observe; N attach/run/detach cycles scale exactly ×N.
library;

import 'package:build_engine/almanac.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

import 'support/bridge_context.dart';

/// Publishes one `EncounterStarted` + `EncounterResolved` pair, recording
/// exactly one fight for whichever bridge is currently attached to
/// [events].
void _publishOneFight(EventBus events, {required String name}) {
  events.publish(EncounterStarted(name: name, enemyId: 'e'));
  events.publish(
    EncounterResolved(
      name: name,
      enemyId: 'e',
      won: true,
      playerHealthAfter: 1,
    ),
  );
}

HeadlessGameAlmanacBridge _attachedBridge(
  AlmanacRecorder recorder,
  EventBus events,
  PluginContext context,
  EntityId character, {
  required String runId,
  required int runNumber,
}) {
  final bridge = HeadlessGameAlmanacBridge(
    recorder,
    runId: runId,
    runNumber: runNumber,
    seed: 1,
  );
  bridge.attach(events, context, character);
  bridge.setRunProfile(lineageId: 'lin', physiqueId: 'phy');
  return bridge;
}

void main() {
  test('(a) one run: each source event published once => exactly one '
      'recorder observation', () {
    final events = EventBus();
    final context = bridgeTestContext(events);
    const character = EntityId(1);
    final recorder = AlmanacRecorder();
    _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-a',
      runNumber: 1,
    );

    context.components.add(
      const EntityId(50),
      const TechniqueVariant(
        owner: character,
        baseFamilyId: 'basic_punch',
        descriptorIds: {'swift'},
        axisProfile: {'speed': 2},
      ),
    );

    events.publish(PhysiqueAssigned(character, 'phy'));
    events.publish(
      TechniqueVariantMinted(character, const EntityId(50), 'basic_punch'),
    );
    events.publish(
      TechniqueVariantInspired(
        owner: character,
        instanceId: const EntityId(60),
        familyId: 'basic_punch',
        descriptorIds: const {'iron'},
        inspirerInstanceIds: const [EntityId(50)],
      ),
    );
    events.publish(const SubjectDiscovered(EntityId(0), 'item:knife'));
    events.publish(EncounterStarted(name: 'F1', enemyId: 'e1'));
    events.publish(
      ActionCompleted(
        const EntityId(0),
        character,
        const [EntityId(2)],
        AttackAction(
          actor: character,
          targets: const [EntityId(2)],
          baseDamage: 1,
          damageStat: 'fist',
          sourceRef: BuildComponentRef(
            referenceType: techniqueReferenceType,
            contentId: 'basic_punch',
            instanceEntityId: const EntityId(70),
          ),
        ),
      ),
    );
    events.publish(
      EncounterResolved(
        name: 'F1',
        enemyId: 'e1',
        won: true,
        playerHealthAfter: 9,
      ),
    );
    events.publish(
      TrainingResultRecorded(
        subject: 'technique:basic_punch',
        profile: const TrainingProfile({}),
        gain: 1,
      ),
    );
    events.publish(RunEnded(won: true, encounterCount: 1));

    final state = recorder.state;
    expect(state.runs, hasLength(1));
    final run = state.runs.single;
    expect(run.fights, hasLength(1));
    expect(run.trainingObservations, hasLength(1));
    expect(run.outcome, equals(RunOutcome.won));
    expect(run.finalBuildId, isNotNull);
    // The item discovery plus the `techniqueVariant` row emitted by the
    // minted technique (§7.1).
    expect(state.discoveries, hasLength(2));
    expect(
      state.discoveries
          .firstWhere((d) => d.type == AlmanacDiscoveryType.item)
          .contentId,
      equals('knife'),
    );
    expect(
      state.discoveries
          .firstWhere((d) => d.type == AlmanacDiscoveryType.techniqueVariant)
          .contentId,
      equals('50'),
    );
    expect(state.inspirations, hasLength(1));
    // minted (50) + inspired result (60) + usage-created (70)
    expect(
      state.techniques.map((t) => t.instanceId).toSet(),
      equals({'50', '60', '70'}),
    );
    expect(
      state.techniques.firstWhere((t) => t.instanceId == '70').totalUsage,
      equals(1),
    );
    // finalBuild snapshot recorded once.
    expect(
      state.builds.where((b) => b.phase == BuildPhase.finalBuild),
      hasLength(1),
    );
  });

  test('(b) two sequential fresh-bridge cycles on the SAME EventBus => no '
      'duplicated observations, no run-A event in run-B state', () {
    final events = EventBus();
    final context = bridgeTestContext(events);
    const character = EntityId(1);
    final recorder = AlmanacRecorder();

    final bridgeA = _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-a',
      runNumber: 1,
    );
    _publishOneFight(events, name: 'A-F1');
    bridgeA.detach();

    // Stray event after run A detached — must reach nobody.
    events.publish(
      EncounterResolved(
        name: 'stray',
        enemyId: 'e',
        won: true,
        playerHealthAfter: 1,
      ),
    );

    final bridgeB = _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-b',
      runNumber: 2,
    );
    _publishOneFight(events, name: 'B-F1');
    bridgeB.detach();

    final runA = recorder.state.runs.firstWhere((r) => r.runId == 'run-a');
    final runB = recorder.state.runs.firstWhere((r) => r.runId == 'run-b');
    expect(runA.fights, hasLength(1));
    expect(runA.fights.single.name, equals('A-F1'));
    expect(runB.fights, hasLength(1));
    expect(runB.fights.single.name, equals('B-F1'));
    expect(runB.fights.single.sequence, equals(0));
  });

  test('(c) after detach(), publishing every observed event type AND '
      'calling recordBuildPhase again => recorder state unchanged', () {
    final events = EventBus();
    final context = bridgeTestContext(events);
    const character = EntityId(1);
    final recorder = AlmanacRecorder();
    final bridge = _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-c',
      runNumber: 1,
    );
    _publishOneFight(events, name: 'F1');
    events.publish(RunEnded(won: true, encounterCount: 1));
    bridge.detach();

    final before = recorder.state;

    events.publish(PhysiqueAssigned(character, 'phy'));
    events.publish(
      TechniqueVariantMinted(character, const EntityId(50), 'basic_punch'),
    );
    events.publish(
      TechniqueVariantInspired(
        owner: character,
        instanceId: const EntityId(60),
        familyId: 'basic_punch',
        descriptorIds: const {'iron'},
        inspirerInstanceIds: const [],
      ),
    );
    events.publish(const SubjectDiscovered(EntityId(0), 'item:knife'));
    events.publish(EncounterStarted(name: 'F2', enemyId: 'e2'));
    events.publish(
      ActionCompleted(
        const EntityId(0),
        character,
        const [EntityId(2)],
        AttackAction(
          actor: character,
          targets: const [EntityId(2)],
          baseDamage: 1,
          damageStat: 'fist',
        ),
      ),
    );
    events.publish(
      EncounterResolved(
        name: 'F2',
        enemyId: 'e2',
        won: true,
        playerHealthAfter: 1,
      ),
    );
    events.publish(
      TrainingResultRecorded(
        subject: 's',
        profile: const TrainingProfile({}),
        gain: 1,
      ),
    );
    events.publish(RunEnded(won: false, encounterCount: 2));
    bridge.recordBuildPhase(BuildPhase.postReward);
    bridge.recordBuildPhase(BuildPhase.postTraining);

    expect(recorder.state, equals(before));
  });

  test('(d) detach() called twice => no throw, state unchanged', () {
    final events = EventBus();
    final context = bridgeTestContext(events);
    const character = EntityId(1);
    final recorder = AlmanacRecorder();
    final bridge = _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-d',
      runNumber: 1,
    );
    _publishOneFight(events, name: 'F1');

    final before = recorder.state;
    bridge.detach();
    expect(bridge.detach, returnsNormally);
    expect(recorder.state, equals(before));
  });

  test('(e) N attach/run/detach cycles => observation counts scale ×N', () {
    final events = EventBus();
    final context = bridgeTestContext(events);
    const character = EntityId(1);
    final recorder = AlmanacRecorder();

    const n = 5;
    for (var i = 0; i < n; i++) {
      final bridge = _attachedBridge(
        recorder,
        events,
        context,
        character,
        runId: 'run-$i',
        runNumber: i + 1,
      );
      _publishOneFight(events, name: 'F-$i');
      events.publish(
        TrainingResultRecorded(
          subject: 's',
          profile: const TrainingProfile({}),
          gain: 1,
        ),
      );
      bridge.detach();
    }

    final state = recorder.state;
    expect(state.runs, hasLength(n));
    final totalFights = state.runs.fold<int>(
      0,
      (sum, r) => sum + r.fights.length,
    );
    final totalTraining = state.runs.fold<int>(
      0,
      (sum, r) => sum + r.trainingObservations.length,
    );
    expect(totalFights, equals(n));
    expect(totalTraining, equals(n));
  });

  test(
    '(f) attach called twice on one bridge => still one subscription set',
    () {
      final events = EventBus();
      final context = bridgeTestContext(events);
      const character = EntityId(1);
      final recorder = AlmanacRecorder();
      final bridge = HeadlessGameAlmanacBridge(
        recorder,
        runId: 'run-f',
        runNumber: 1,
        seed: 1,
      );
      bridge.attach(events, context, character);
      bridge.attach(events, context, character); // no-op
      bridge.setRunProfile(lineageId: 'lin', physiqueId: 'phy');

      _publishOneFight(events, name: 'F1');

      expect(recorder.state.runs.single.fights, hasLength(1));
    },
  );

  test('(g) counters never leak between instances', () {
    final events = EventBus();
    final context = bridgeTestContext(events);
    const character = EntityId(1);
    final recorder = AlmanacRecorder();

    final bridgeA = _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-a',
      runNumber: 1,
    );
    events.publish(EncounterStarted(name: 'A1', enemyId: 'e'));
    events.publish(EncounterStarted(name: 'A2', enemyId: 'e'));
    events.publish(EncounterStarted(name: 'A3', enemyId: 'e'));
    bridgeA.detach();

    final bridgeB = _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-b',
      runNumber: 2,
    );
    _publishOneFight(events, name: 'B1');
    bridgeB.detach();

    final runB = recorder.state.runs.firstWhere((r) => r.runId == 'run-b');
    expect(runB.fights.single.sequence, equals(0));
  });

  test('(h) RewardSelected / RunStarted / TomeChanged are not subscribed; '
      'no event produces a build record on its own', () {
    final events = EventBus();
    final context = bridgeTestContext(events);
    const character = EntityId(1);
    final recorder = AlmanacRecorder();
    _attachedBridge(
      recorder,
      events,
      context,
      character,
      runId: 'run-h',
      runNumber: 1,
    );

    final beforeUnsubscribed = recorder.state;
    events.publish(const RewardSelected(RewardKind.itemOrTechnique));
    events.publish(RunStarted(seed: 1, characterName: 'x'));
    events.publish(TomeChanged(stepName: 's', components: const []));
    expect(
      recorder.state,
      equals(beforeUnsubscribed),
      reason: 'RewardSelected / RunStarted / TomeChanged change nothing',
    );

    // TrainingResultRecorded IS subscribed, but only feeds the training
    // ledger — it must never create a build record.
    events.publish(
      TrainingResultRecorded(
        subject: 's',
        profile: const TrainingProfile({}),
        gain: 1,
      ),
    );
    expect(recorder.state.builds, isEmpty);
    expect(recorder.state.runs.single.trainingObservations, hasLength(1));
  });
}
