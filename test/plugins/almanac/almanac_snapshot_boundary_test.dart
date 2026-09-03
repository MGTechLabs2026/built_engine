/// Phase 7 §13.1 / §11.2 A / §11.3 3a-4b — `HeadlessGameAlmanacBridge`
/// snapshot boundary timing.
///
/// A snapshot is built ONLY from a `recordBuildPhase(...)` composition
/// callback (`initial` / `postReward` / `postTraining`) or the `RunEnded`
/// handler (`finalBuild`) — never from `RewardSelected` or
/// `TrainingResultRecorded`, which fire before their mutations. When the
/// callback runs, the bridge reads the live Tome, so the snapshot reflects
/// exactly the state that operation left behind. `recordBuildPhase` before
/// `beginRun` or after `detach` is a no-op.
library;

import 'package:build_engine/almanac.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

import 'support/bridge_context.dart';

void main() {
  late EventBus events;
  late PluginContext context;
  late EntityId character;
  late AlmanacRecorder recorder;
  late HeadlessGameAlmanacBridge bridge;

  setUp(() {
    events = EventBus();
    context = bridgeTestContext(events);
    character = context.characters.create();
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 't', slotIds: const ['s1', 's2']),
    );
    context.tome.createTome(character, 't');
    recorder = AlmanacRecorder();
    bridge = HeadlessGameAlmanacBridge(
      recorder,
      runId: 'run-sb',
      runNumber: 1,
      seed: 1,
    );
    bridge.attach(events, context, character);
    bridge.setRunProfile(lineageId: 'western', physiqueId: 'phy');
  });

  test('a hand-fed RewardSelected alone produces no postReward build '
      'record; recordBuildPhase(postReward) after the Tome mutation does, '
      'and the snapshot contains the reward placement', () {
    events.publish(const RewardSelected(RewardKind.itemOrTechnique));
    expect(
      recorder.state.builds.where((b) => b.phase == BuildPhase.postReward),
      isEmpty,
    );

    // resolveReward has now placed the reward item into the Tome.
    context.tome.insert(
      character,
      const SlotId('s1'),
      BuildComponentRef(
        referenceType: itemReferenceType,
        contentId: 'reward_item',
      ),
    );
    bridge.recordBuildPhase(BuildPhase.postReward);

    final build = recorder.state.builds.singleWhere(
      (b) => b.phase == BuildPhase.postReward,
    );
    expect(build.runId, equals('run-sb'));
    expect(build.sequence, equals(0));
    expect(
      build.tome.slots.any(
        (s) => s.occupantKind == 'item' && s.occupantRefId == 'reward_item',
      ),
      isTrue,
    );
  });

  test('a hand-fed TrainingResultRecorded alone produces no postTraining '
      'record; recordBuildPhase(postTraining) after runTraining + '
      'restoreHealth + manageTome shows the MANAGED Tome', () {
    events.publish(
      TrainingResultRecorded(
        subject: 'technique:basic_punch',
        profile: const TrainingProfile({}),
        gain: 1,
      ),
    );
    expect(
      recorder.state.builds.where((b) => b.phase == BuildPhase.postTraining),
      isEmpty,
    );
    // The ledger DID record the session.
    expect(recorder.state.runs.single.trainingObservations, hasLength(1));

    // manageTome() then equips a newly-usable benched item.
    context.tome.insert(
      character,
      const SlotId('s2'),
      BuildComponentRef(
        referenceType: itemReferenceType,
        contentId: 'benched_item',
      ),
    );
    bridge.recordBuildPhase(BuildPhase.postTraining);

    final build = recorder.state.builds.singleWhere(
      (b) => b.phase == BuildPhase.postTraining,
    );
    expect(build.sequence, equals(0));
    expect(
      build.tome.slots.any((s) => s.occupantRefId == 'benched_item'),
      isTrue,
    );
  });

  test('recordBuildPhase before beginRun is a no-op', () {
    final freshEvents = EventBus();
    final freshContext = bridgeTestContext(freshEvents);
    final freshCharacter = freshContext.characters.create();
    final freshRecorder = AlmanacRecorder();
    final freshBridge = HeadlessGameAlmanacBridge(
      freshRecorder,
      runId: 'run-x',
      runNumber: 1,
      seed: 1,
    );
    freshBridge.attach(freshEvents, freshContext, freshCharacter);

    freshBridge.recordBuildPhase(BuildPhase.initial);

    expect(freshRecorder.state.builds, isEmpty);
    expect(freshRecorder.state.runs, isEmpty);
  });

  test('recordBuildPhase after detach is a no-op', () {
    bridge.detach();
    bridge.recordBuildPhase(BuildPhase.postReward);
    expect(recorder.state.builds, isEmpty);
  });

  test('initial and postReward snapshots use their own sequence counters, '
      'first of each phase is sequence 0', () {
    bridge.recordBuildPhase(BuildPhase.initial);
    bridge.recordBuildPhase(BuildPhase.postReward);
    bridge.recordBuildPhase(BuildPhase.postReward);

    final initial = recorder.state.builds.where(
      (b) => b.phase == BuildPhase.initial,
    );
    final postReward = recorder.state.builds.where(
      (b) => b.phase == BuildPhase.postReward,
    );
    expect(initial.map((b) => b.sequence), equals([0]));
    expect(postReward.map((b) => b.sequence), equals([0, 1]));
  });
}
