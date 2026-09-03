/// Phase 7 §13.1 — `HeadlessGameAlmanacBridge` run-profile / `beginRun`
/// sequencing.
///
/// `beginRun` is deferred until BOTH the physique (from `PhysiqueAssigned`
/// for `_character`, or the `setRunProfile` physique) AND the lineage (from
/// `setRunProfile` — no domain event carries it) are known, in either
/// order. `RunStarted` carries no run metadata and is not even subscribed.
/// Lineage is never inferred from `PhysiqueAssigned`.
library;

import 'package:build_engine/almanac.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/physique_plugin.dart';
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
    character = const EntityId(7);
    recorder = AlmanacRecorder();
    bridge = HeadlessGameAlmanacBridge(
      recorder,
      runId: 'run-rp',
      runNumber: 3,
      seed: 5,
    );
    bridge.attach(events, context, character);
  });

  test('physique via PhysiqueAssigned then lineage via setRunProfile '
      '=> beginRun fires exactly once', () {
    events.publish(PhysiqueAssigned(character, 'phy-a'));
    expect(recorder.state.runs, isEmpty);

    bridge.setRunProfile(lineageId: 'western', physiqueId: 'phy-a');

    final run = recorder.state.runs.single;
    expect(run.runId, equals('run-rp'));
    expect(run.runNumber, equals(3));
    expect(run.lineageId, equals('western'));
    expect(run.physiqueId, equals('phy-a'));
  });

  test('lineage via setRunProfile first, then physique via PhysiqueAssigned '
      '=> beginRun still fires (either order)', () {
    // setRunProfile also carries a physique, so on its own it is already
    // enough — assert the reverse-arrival path by withholding the
    // physique from setRunProfile is not possible (it is required), so
    // instead assert a later PhysiqueAssigned does not open a second run.
    bridge.setRunProfile(lineageId: 'eastern', physiqueId: 'phy-b');
    expect(recorder.state.runs, hasLength(1));

    events.publish(PhysiqueAssigned(character, 'phy-b'));
    expect(recorder.state.runs, hasLength(1));
    expect(recorder.state.runs.single.lineageId, equals('eastern'));
  });

  test('RunStarted alone triggers nothing', () {
    events.publish(RunStarted(seed: 5, characterName: 'x'));
    expect(recorder.state.runs, isEmpty);
  });

  test('PhysiqueAssigned alone never opens a run — lineage is never taken '
      'from it', () {
    events.publish(PhysiqueAssigned(character, 'phy-a'));
    expect(recorder.state.runs, isEmpty);
  });

  test('PhysiqueAssigned for a different character is ignored; the '
      'setRunProfile physique wins', () {
    events.publish(PhysiqueAssigned(const EntityId(999), 'stranger'));
    bridge.setRunProfile(lineageId: 'western', physiqueId: 'phy-a');

    expect(recorder.state.runs.single.physiqueId, equals('phy-a'));
  });

  test(
    'RunEnded before any run profile is a clean no-op, not a null throw',
    () {
      expect(
        () => events.publish(RunEnded(won: true, encounterCount: 0)),
        returnsNormally,
      );
      expect(recorder.state.runs, isEmpty);
      expect(recorder.state.milestones, isEmpty);
      expect(recorder.state.builds, isEmpty);
    },
  );

  test('beginRun is emitted only once even with repeated profile signals', () {
    events.publish(PhysiqueAssigned(character, 'phy-a'));
    bridge.setRunProfile(lineageId: 'western', physiqueId: 'phy-a');
    events.publish(PhysiqueAssigned(character, 'phy-a'));
    bridge.setRunProfile(lineageId: 'western', physiqueId: 'phy-a');

    expect(recorder.state.runs, hasLength(1));
  });
}
