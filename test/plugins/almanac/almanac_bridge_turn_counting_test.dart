/// Phase 7 §13.1 — `HeadlessGameAlmanacBridge` fight turn counting.
///
/// `_onActionCompleted` runs TWO independent `if`s: (1) `_encounterTurns++`
/// for every completed action while `_encounterActive`, either side, any
/// source; (2) independently, the exact `combat_stage.dart:104-107`
/// predicate → `recordTechniqueUsed`. A bare / basic / item action still
/// bumps `turnsUsed` and records no usage observation. An `ActionCompleted`
/// with no active encounter changes no fight; `EncounterStarted` resets the
/// counter to 0.
///
/// Relationships are asserted through explicit fields (`fight.runId`,
/// `fight.sequence`, `fight.turnsUsed`, `technique.totalUsage`) — never by
/// parsing an adapter-minted id.
library;

import 'package:build_engine/almanac.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

import 'support/bridge_context.dart';

AttackAction _bareAction(EntityId actor, EntityId target) => AttackAction(
  actor: actor,
  targets: [target],
  baseDamage: 1,
  damageStat: 'fist',
);

AttackAction _techniqueAction(
  EntityId actor,
  EntityId target,
  EntityId instanceId,
) => AttackAction(
  actor: actor,
  targets: [target],
  baseDamage: 1,
  damageStat: 'fist',
  sourceRef: BuildComponentRef(
    referenceType: techniqueReferenceType,
    contentId: 'basic_punch',
    instanceEntityId: instanceId,
  ),
);

void main() {
  late EventBus events;
  late PluginContext context;
  late EntityId character;
  late EntityId enemy;
  late AlmanacRecorder recorder;
  late HeadlessGameAlmanacBridge bridge;

  setUp(() {
    events = EventBus();
    context = bridgeTestContext(events);
    character = const EntityId(1);
    enemy = const EntityId(2);
    recorder = AlmanacRecorder();
    bridge = HeadlessGameAlmanacBridge(
      recorder,
      runId: 'run-tc',
      runNumber: 1,
      seed: 99,
    );
    bridge.attach(events, context, character);
    events.publish(PhysiqueAssigned(character, 'phy'));
    bridge.setRunProfile(lineageId: 'lin', physiqueId: 'phy');
  });

  test('bare -> technique -> bare while a fight is live => turnsUsed == 3, '
      'usage observations for this run == 1', () {
    events.publish(EncounterStarted(name: 'F1', enemyId: 'e1'));
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _techniqueAction(character, enemy, const EntityId(70))),
    );
    events.publish(
      ActionCompleted(const EntityId(0), enemy, [
        character,
      ], _bareAction(enemy, character)),
    );
    events.publish(
      EncounterResolved(
        name: 'F1',
        enemyId: 'e1',
        won: true,
        playerHealthAfter: 42,
      ),
    );

    final fight = recorder.state.runs.single.fights.single;
    expect(fight.runId, equals('run-tc'));
    expect(fight.sequence, equals(0));
    expect(fight.turnsUsed, equals(3));
    expect(fight.name, equals('F1'));

    final technique = recorder.state.techniques.single;
    expect(technique.instanceId, equals('70'));
    expect(technique.totalUsage, equals(1));
    expect(technique.usageObservations.single.runId, equals('run-tc'));
  });

  test('an item/basic action still increments turnsUsed but records no '
      'usage observation (the two ifs are independent)', () {
    events.publish(EncounterStarted(name: 'F1', enemyId: 'e1'));
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );
    events.publish(
      EncounterResolved(
        name: 'F1',
        enemyId: 'e1',
        won: true,
        playerHealthAfter: 10,
      ),
    );

    expect(recorder.state.runs.single.fights.single.turnsUsed, equals(2));
    expect(recorder.state.techniques, isEmpty);
  });

  test('an ActionCompleted with no active encounter changes no fight', () {
    // Before any EncounterStarted.
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );

    events.publish(EncounterStarted(name: 'F1', enemyId: 'e1'));
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );
    events.publish(
      EncounterResolved(
        name: 'F1',
        enemyId: 'e1',
        won: true,
        playerHealthAfter: 5,
      ),
    );

    // After EncounterResolved — must not touch the just-recorded fight.
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );

    expect(recorder.state.runs.single.fights.single.turnsUsed, equals(1));
  });

  test('a fresh EncounterStarted resets the counter to 0', () {
    events.publish(EncounterStarted(name: 'F1', enemyId: 'e1'));
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );
    events.publish(
      EncounterResolved(
        name: 'F1',
        enemyId: 'e1',
        won: true,
        playerHealthAfter: 30,
      ),
    );

    events.publish(EncounterStarted(name: 'F2', enemyId: 'e2'));
    events.publish(
      ActionCompleted(const EntityId(0), character, [
        enemy,
      ], _bareAction(character, enemy)),
    );
    events.publish(
      EncounterResolved(
        name: 'F2',
        enemyId: 'e2',
        won: true,
        playerHealthAfter: 20,
      ),
    );

    final fights = recorder.state.runs.single.fights.toList();
    expect(fights, hasLength(2));
    expect(fights[0].sequence, equals(0));
    expect(fights[0].turnsUsed, equals(2));
    expect(fights[1].sequence, equals(1));
    expect(fights[1].turnsUsed, equals(1));
  });
}
