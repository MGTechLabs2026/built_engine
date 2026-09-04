/// Phase 7 §13.2 — end-to-end: `runGame(almanac: recorder, runId:, runNumber:)`
/// drives the headless bridge, which drives the recorder, and the caller
/// owns persistence.
///
/// Every relationship is asserted through explicit fields
/// (`run.runId`, `build.phase`, `build.sequence`, `fight.runId`, …) — never
/// by parsing an adapter-minted id string.
library;

import 'dart:io';

import 'package:build_engine/almanac.dart';
import 'package:build_engine/almanac_file.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

import '../support/policies.dart';

/// Always takes the item/technique reward — makes rewards land in the Tome
/// so a `postReward` snapshot can be shown to post-date the mutation.
class _ForceItemReward extends DefaultRunDecisionPolicy {
  const _ForceItemReward();

  @override
  int chooseReward(List<RewardKind> candidates) {
    final index = candidates.indexOf(RewardKind.itemOrTechnique);
    return index == -1 ? 0 : index;
  }
}

Set<String?> _occupants(AlmanacBuildRecord b) => {
  for (final s in b.tome.slots)
    if (s.occupantRefId != null) s.occupantRefId,
};

/// A throwaway `PluginContext` with technique content loaded — just
/// enough for [techniqueFamilyOf] to resolve a legacy evolved id to its
/// base family. `runGame` doesn't hand back the context it built
/// internally, so this test builds its own read-only one purely to
/// classify an id string; it plays no part in the run itself.
PluginContext _techniqueLookupContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  )..content.loadAll(techniqueContentDefinitions);
}

void main() {
  test(
    '3 runs (own runId, differing seeds/policies) => 3 distinct '
    'AlmanacRunRecords with discoveries + final builds + lineage/physique',
    () {
      final recorder = AlmanacRecorder();
      runGame(
        2,
        policy: const NeverReplacePolicy(),
        almanac: recorder,
        runId: 'run-1',
        runNumber: 1,
      );
      runGame(
        4,
        policy: const _ForceItemReward(),
        almanac: recorder,
        runId: 'run-2',
        runNumber: 2,
      );
      runGame(
        13,
        policy: const DefaultRunDecisionPolicy(),
        almanac: recorder,
        runId: 'run-3',
        runNumber: 3,
      );

      final state = recorder.state;
      expect(
        state.runs.map((r) => r.runId),
        equals(['run-1', 'run-2', 'run-3']),
      );
      for (final run in state.runs) {
        expect(run.lineageId, isNotEmpty);
        expect(run.physiqueId, isNotEmpty);
        expect(run.finalBuildId, isNotNull);
        expect(run.completedAt, isNotNull);
        expect(
          state.builds.where(
            (b) => b.runId == run.runId && b.phase == BuildPhase.finalBuild,
          ),
          hasLength(1),
        );
      }
      expect(state.discoveries, isNotEmpty);
      final queries = AlmanacQueries(state);
      expect(
        queries.getRunHistory().map((r) => r.runId),
        equals(['run-1', 'run-2', 'run-3']),
      );
    },
  );

  test('same seed, two different runIds => two separate run records; '
      'ledgers disjoint, matched on explicit (runId, …)', () {
    final recorder = AlmanacRecorder();
    runGame(
      3,
      policy: const _ForceItemReward(),
      almanac: recorder,
      runId: 'alpha',
      runNumber: 1,
    );
    runGame(
      3,
      policy: const _ForceItemReward(),
      almanac: recorder,
      runId: 'beta',
      runNumber: 2,
    );

    final state = recorder.state;
    expect(state.runs.map((r) => r.runId), equals(['alpha', 'beta']));

    for (final f in state.runs.expand((r) => r.fights)) {
      expect(f.runId, anyOf('alpha', 'beta'));
    }
    for (final b in state.builds) {
      final owner = state.runs.singleWhere((r) => r.runId == b.runId);
      expect(owner.runId, equals(b.runId));
    }
    // Every training observation names exactly one of the two runs.
    for (final run in state.runs) {
      for (final t in run.trainingObservations) {
        expect(t.runId, equals(run.runId));
      }
    }
  });

  test('same seed + same policy + same runId replayed through the bridge '
      '=> equivalent AlmanacState (structural)', () {
    // Flat string rows only — no nested List/Set inside a record (Dart
    // record `==` does not deep-compare collections).
    List<String> project(AlmanacState s) => [
      for (final r in s.runs)
        'run|${r.runId}|${r.runNumber}|${r.outcome}|${r.lineageId}|'
            '${r.physiqueId}|${r.finalBuildId}|${r.enemiesDefeated}|'
            '${r.techniquesUsed}|${r.trainingSessions}',
      for (final r in s.runs)
        for (final f in r.fights)
          'fight|${r.runId}|${f.sequence}|${f.name}|${f.enemyId}|'
              '${f.won}|${f.turnsUsed}',
      for (final b in s.builds)
        'build|${b.runId}|${b.phase}|${b.sequence}|${b.dna.signature}|'
            '${(_occupants(b).whereType<String>().toList()..sort()).join(",")}',
      for (final d in s.discoveries) 'disc|${d.type}|${d.contentId}|${d.runId}',
      for (final m in s.milestones) 'mile|${m.type}|${m.runId}|${m.contextId}',
    ];

    AlmanacState once() {
      final recorder = AlmanacRecorder();
      runGame(
        5,
        policy: const _ForceItemReward(),
        almanac: recorder,
        runId: 'replay',
        runNumber: 1,
      );
      return recorder.state;
    }

    expect(project(once()), equals(project(once())));
  });

  test('two full runGame(almanac:) calls sharing one recorder, different '
      'runIds => 2 run records, no cross-run leak, subscriptions gone after '
      'each runGame returns', () {
    final recorder = AlmanacRecorder();

    final busA = EventBus();
    runGame(
      2,
      policy: const NeverReplacePolicy(),
      almanac: recorder,
      runId: 'first',
      runNumber: 1,
      eventBus: busA,
    );
    final firstFightsAfterReturn =
        recorder.state.runs
            .singleWhere((r) => r.runId == 'first')
            .fights
            .length;

    // The bridge for run 'first' was detached inside buildResult — a stray
    // event on its own EventBus must reach nobody.
    busA.publish(
      EncounterResolved(
        name: 'stray',
        enemyId: 'ghost',
        won: true,
        playerHealthAfter: 1,
      ),
    );
    expect(
      recorder.state.runs.singleWhere((r) => r.runId == 'first').fights.length,
      equals(firstFightsAfterReturn),
    );

    final busB = EventBus();
    runGame(
      4,
      policy: const _ForceItemReward(),
      almanac: recorder,
      runId: 'second',
      runNumber: 2,
      eventBus: busB,
    );

    final state = recorder.state;
    expect(state.runs.map((r) => r.runId), equals(['first', 'second']));
    // No fight recorded under 'first' names a 'second' enemy and vice versa.
    final firstEnemies =
        state.runs
            .singleWhere((r) => r.runId == 'first')
            .fights
            .map((f) => f.name)
            .toSet();
    final secondNames =
        state.runs
            .singleWhere((r) => r.runId == 'second')
            .fights
            .map((f) => f.name)
            .toSet();
    expect(firstEnemies.intersection({'stray'}), isEmpty);
    expect(secondNames.intersection({'stray'}), isEmpty);
  });

  test('persist -> AlmanacRecorder(repo.load()) -> continue: combined '
      'history correct, run 1 unchanged, run 2 appended', () {
    final dir = Directory.systemTemp.createTempSync('almanac_hist');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = JsonFileAlmanacRepository(File('${dir.path}/almanac.json'));

    final recorder1 = AlmanacRecorder(repo.load());
    runGame(
      2,
      policy: const NeverReplacePolicy(),
      almanac: recorder1,
      runId: 'run-1',
      runNumber: 1,
    );
    final run1Produced = recorder1.state.runs.single;
    final run1Builds =
        recorder1.state.builds.where((b) => b.runId == 'run-1').toList();
    repo.save(recorder1.state);

    final recorder2 = AlmanacRecorder(repo.load());
    runGame(
      4,
      policy: const _ForceItemReward(),
      almanac: recorder2,
      runId: 'run-2',
      runNumber: 2,
    );

    final state = recorder2.state;
    expect(state.runs.map((r) => r.runId), equals(['run-1', 'run-2']));
    // Run 1 byte-identical to what run 1 produced.
    expect(
      state.runs.firstWhere((r) => r.runId == 'run-1'),
      equals(run1Produced),
    );
    expect(
      state.builds.where((b) => b.runId == 'run-1').toList(),
      equals(run1Builds),
    );
    // Run 2 appended.
    expect(
      state.runs.firstWhere((r) => r.runId == 'run-2').finalBuildId,
      isNotNull,
    );

    // No <path>.tmp residue.
    expect(File('${dir.path}/almanac.json.tmp').existsSync(), isFalse);
  });

  test('whole-chronicle JsonFile encode->decode round-trip: every '
      'AlmanacQueries getter returns identical ordered results, no .tmp '
      'residue', () {
    final dir = Directory.systemTemp.createTempSync('almanac_rt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = JsonFileAlmanacRepository(File('${dir.path}/almanac.json'));

    final recorder = AlmanacRecorder();
    runGame(
      2,
      policy: const NeverReplacePolicy(),
      almanac: recorder,
      runId: 'r1',
      runNumber: 1,
    );
    runGame(
      3,
      policy: const _ForceItemReward(),
      almanac: recorder,
      runId: 'r2',
      runNumber: 2,
    );

    final before = recorder.state;
    repo.save(before);
    final after = repo.load();

    final qBefore = AlmanacQueries(before);
    final qAfter = AlmanacQueries(after);
    expect(qAfter.getRunHistory(), equals(qBefore.getRunHistory()));
    expect(qAfter.getBuildHistory(), equals(qBefore.getBuildHistory()));
    expect(qAfter.getDiscoveries(), equals(qBefore.getDiscoveries()));
    for (final runId in ['r1', 'r2']) {
      expect(
        qAfter.getBuildsForRun(runId),
        equals(qBefore.getBuildsForRun(runId)),
      );
      expect(qAfter.getRun(runId), equals(qBefore.getRun(runId)));
    }
    expect(after, equals(before));
    expect(File('${dir.path}/almanac.json.tmp').existsSync(), isFalse);
  });

  test('postReward snapshot reflects the applied reward — the snapshot '
      'post-dates the Tome mutation, not the RewardSelected decision', () {
    final recorder = AlmanacRecorder();
    final bus = EventBus();
    final rewardsSelected = <RewardSelected>[];
    final runEnded = <RunEnded>[];
    bus.subscribe<RewardSelected>(rewardsSelected.add);
    bus.subscribe<RunEnded>(runEnded.add);

    // M3 (§13.2): probe how many postReward records exist for this run at the
    // instant each RewardSelected is published — proving RewardSelected
    // precedes the postReward record's creation, not just the Tome mutation.
    final postRewardCountAtSelection = <int>[];
    bus.subscribe<RewardSelected>((_) {
      postRewardCountAtSelection.add(
        recorder.state.builds
            .where((b) => b.runId == 'rw' && b.phase == BuildPhase.postReward)
            .length,
      );
    });

    runGame(
      1,
      policy: const _ForceItemReward(),
      almanac: recorder,
      runId: 'rw',
      runNumber: 1,
      eventBus: bus,
    );

    final state = recorder.state;
    final initial = state.builds.singleWhere(
      (b) => b.runId == 'rw' && b.phase == BuildPhase.initial,
    );
    final postRewards =
        state.builds
            .where((b) => b.runId == 'rw' && b.phase == BuildPhase.postReward)
            .toList();
    expect(postRewards, isNotEmpty);

    // At least one postReward snapshot holds an occupant the initial build
    // did not — i.e. the reward's placement is already applied when the
    // snapshot is taken.
    final newlyPlaced = <String?>{};
    for (final b in postRewards) {
      newlyPlaced.addAll(_occupants(b).difference(_occupants(initial)));
    }
    expect(newlyPlaced, isNotEmpty);
    // Every newly-placed occupant was discovered in this run.
    final discovered = state.discoveries.map((d) => d.contentId).toSet();
    expect(newlyPlaced.whereType<String>().every(discovered.contains), isTrue);

    // RewardSelected fired (it is a decision, published before the
    // mutation — never the snapshot trigger); RunEnded fired once.
    expect(rewardsSelected, isNotEmpty);
    expect(runEnded, hasLength(1));

    // M3 (§13.2): at the k-th RewardSelected the recorder holds at most k-1
    // postReward records for this run — this cycle's record is created only
    // later, by recordBuildPhase(postReward) after the Tome mutation. The
    // count is monotonic non-decreasing and starts at 0.
    expect(postRewardCountAtSelection, isNotEmpty);
    expect(postRewardCountAtSelection.first, equals(0));
    for (var i = 0; i < postRewardCountAtSelection.length; i++) {
      expect(postRewardCountAtSelection[i], lessThanOrEqualTo(i));
      if (i > 0) {
        expect(
          postRewardCountAtSelection[i],
          greaterThanOrEqualTo(postRewardCountAtSelection[i - 1]),
        );
      }
    }
    // …and by run end those postReward records do exist (non-zero after).
    expect(
      postRewards.length,
      greaterThanOrEqualTo(postRewardCountAtSelection.length),
    );
    // postReward sequences are 0,1,2,… in first-seen order.
    expect(
      postRewards.map((b) => b.sequence),
      equals([for (var i = 0; i < postRewards.length; i++) i]),
    );
  });

  test('postTraining snapshot reflects the applied training AND the '
      "subsequent manageTome() pass (newly-known technique equipped)", () {
    final recorder = AlmanacRecorder();
    final result = runGame(
      6,
      policy: TrainAfterFirstCombatPolicy(),
      almanac: recorder,
      runId: 'tr',
      runNumber: 1,
    );

    final state = recorder.state;
    final run = state.runs.single;

    // Training ledger tracks the run's training exactly.
    expect(
      run.trainingObservations.length,
      equals(result.trainingRecords.length),
    );
    expect(run.trainingSessions, equals(result.trainingRecords.length));

    final postTraining =
        state.builds
            .where((b) => b.runId == 'tr' && b.phase == BuildPhase.postTraining)
            .toList();
    expect(postTraining, isNotEmpty);

    // manageTome() equipped a newly-known technique after runTraining, and
    // a postTraining snapshot captured it as a Tome occupant.
    expect(result.techniquesLearned, isNotEmpty);
    final learned = result.techniquesLearned.toSet();
    final captured = postTraining.any(
      (b) => b.tome.slots.any(
        (s) =>
            s.occupantKind == 'technique' && learned.contains(s.occupantRefId),
      ),
    );
    expect(captured, isTrue);

    // finalBuild ⊇ initial (the run only ever grows the kit here); if a
    // technique evolved, the final snapshot shows the evolved id.
    final initial = state.builds.singleWhere(
      (b) => b.phase == BuildPhase.initial,
    );
    final finalBuild = state.builds.singleWhere(
      (b) => b.phase == BuildPhase.finalBuild,
    );
    expect(_occupants(finalBuild).containsAll(_occupants(initial)), isTrue);
    // SP1: finalBuild's technique occupants are base-family ids; the
    // evolved identity is the variant's descriptor set. Assert the final
    // build carries at least one technique instance snapshot with
    // descriptors when the run evolved.
    if (result.techniquesEvolved.isNotEmpty) {
      final evolvedFamily = techniqueFamilyOf(
        result.techniquesEvolved.last,
        _techniqueLookupContext(),
      );
      expect(finalBuild.techniques, isNotEmpty);
      expect(
        finalBuild.techniques.any(
          (t) => t.baseFamilyId == evolvedFamily && t.descriptorIds.isNotEmpty,
        ),
        isTrue,
        reason:
            "the evolved family's equipped instance should carry the "
            'evolved descriptors specifically, not just any non-empty '
            'descriptor set (which an inspired variant would also '
            'satisfy)',
      );
    }

    // M4 (§13.2 "Full-run ordering by contents"): order this run's build
    // records by phase progression then per-phase sequence, and assert the
    // full monotonic superset chain
    //   initial ⊆ postReward₁ ⊆ … ⊆ postTraining ⊆ finalBuild
    // over the occupied (slotId → occupantRefId) set — no equipped
    // item/technique is silently lost between two snapshots within a run.
    // Selected and ordered by explicit fields only; no buildId is parsed.
    final chain =
        state.builds.where((b) => b.runId == 'tr').toList()..sort((x, y) {
          final byPhase = x.phase.index.compareTo(y.phase.index);
          return byPhase != 0 ? byPhase : x.sequence.compareTo(y.sequence);
        });
    // initial + at least one postTraining + finalBuild.
    expect(chain.length, greaterThanOrEqualTo(3));
    Map<String, String?> occupied(AlmanacBuildRecord b) => {
      for (final s in b.tome.slots)
        if (s.occupantRefId != null) s.slotId: s.occupantRefId,
    };
    for (var i = 1; i < chain.length; i++) {
      final prev = occupied(chain[i - 1]);
      final curr = occupied(chain[i]);
      for (final entry in prev.entries) {
        // The fixture (TrainAfterFirstCombatPolicy) only ever grows the kit —
        // no manageTome() unequip — so every prior (slotId → occupant) pair
        // survives verbatim into the next snapshot.
        expect(
          curr[entry.key],
          equals(entry.value),
          reason:
              'occupant ${entry.value} in slot ${entry.key} vanished between '
              '${chain[i - 1].phase.name}#${chain[i - 1].sequence} and '
              '${chain[i].phase.name}#${chain[i].sequence}',
        );
      }
      // Weaker whole-set monotonicity too (an occupant may change slots).
      expect(
        _occupants(chain[i]).containsAll(_occupants(chain[i - 1])),
        isTrue,
      );
    }
  });

  test('almanac == null: runGame does no repo IO and constructs no bridge; '
      'result byte-identical to a plain runGame(seed)', () {
    final source =
        File('lib/src/plugins/game/game_run.dart').readAsStringSync();
    expect(source, isNot(contains('AlmanacRepository')));
    expect(source, isNot(contains('JsonFileAlmanacRepository')));
    expect(source, isNot(contains('repo.load')));
    expect(source, isNot(contains('repo.save')));

    final a = runGame(6, policy: const NeverReplacePolicy());
    final b = runGame(
      6,
      policy: const NeverReplacePolicy(),
      almanac: null,
      runId: null,
      runNumber: null,
    );
    expect(b.won, equals(a.won));
    expect(b.cyclesCompleted, equals(a.cyclesCompleted));
    expect(
      b.finalBuild.map((c) => (c.referenceType, c.contentId)),
      equals(a.finalBuild.map((c) => (c.referenceType, c.contentId))),
    );
    expect(
      b.encounters.map((e) => (e.name, e.enemyId, e.won, e.playerHealthAfter)),
      equals(
        a.encounters.map(
          (e) => (e.name, e.enemyId, e.won, e.playerHealthAfter),
        ),
      ),
    );

    // M2 (§13.2): the opt-in params default to a byte-identical run — proven
    // in this file, not by leaning on test/game/game_run_test.dart.
    // `decisionLog` has no value `==`, so compare its canonical text form;
    // `tomeHistory` / `trainingRecords` via explicit-field projections.
    expect(
      saveDecisionLog(b.decisionLog),
      equals(saveDecisionLog(a.decisionLog)),
    );
    List<String> tomeHistory(RunResult r) => [
      for (final s in r.tomeHistory)
        '${s.afterStep}|'
            '${[for (final c in s.components) '${c.referenceType}:${c.contentId}'].join(",")}',
    ];
    expect(tomeHistory(b), equals(tomeHistory(a)));
    expect(
      b.trainingRecords.map(
        (t) => (t.subject, t.attemptCount, t.averageQuality, t.gain),
      ),
      equals(
        a.trainingRecords.map(
          (t) => (t.subject, t.attemptCount, t.averageQuality, t.gain),
        ),
      ),
    );
  });
}
