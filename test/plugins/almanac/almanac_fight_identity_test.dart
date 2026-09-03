/// Phase 4.2 — fights are keyed by the structural `(runId, fightId)` pair.
///
/// Every relationship is asserted through an explicit field (`fight.runId`,
/// `fight.sequence`), never by reading structure out of an opaque id.
library;

import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

AlmanacRecorder _withRun(String runId, int runNumber) =>
    AlmanacRecorder()..beginRun(
      runId: runId,
      runNumber: runNumber,
      lineageId: 'western',
      physiqueId: 'phy-a',
      startedAt: at(1),
    );

void _recordBandit(
  AlmanacRecorder recorder, {
  required String runId,
  required String fightId,
  required int sequence,
  bool won = true,
}) => recorder.recordFight(
  runId: runId,
  fightId: fightId,
  sequence: sequence,
  name: 'Bandit',
  enemyId: 'enemy-bandit',
  won: won,
  playerHealthAfter: 10,
  turnsUsed: 5,
);

void main() {
  group('fight identity', () {
    test('two otherwise-identical Bandit fights stay two records', () {
      final recorder = _withRun('run-1', 1);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e0', sequence: 0);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e1', sequence: 1);

      final fights = recorder.state.runs.single.fights;
      expect(fights, hasLength(2));
      expect(fights.map((f) => f.sequence).toList(), [0, 1]);
      expect(fights.every((f) => f.runId == 'run-1'), isTrue);
      expect(fights.every((f) => f.name == 'Bandit'), isTrue);
    });

    test('replaying a fightId leaves the ledger at two records', () {
      final recorder = _withRun('run-1', 1);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e0', sequence: 0);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e1', sequence: 1);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e0', sequence: 0);

      expect(recorder.state.runs.single.fights, hasLength(2));
    });

    test('the same opaque fightId under two runs is two records', () {
      final recorder = _withRun('run-A', 1)..beginRun(
        runId: 'run-B',
        runNumber: 2,
        lineageId: 'eastern',
        physiqueId: 'phy-b',
        startedAt: at(2),
      );
      _recordBandit(recorder, runId: 'run-A', fightId: 'fight-1', sequence: 0);
      _recordBandit(recorder, runId: 'run-B', fightId: 'fight-1', sequence: 0);

      final runs = recorder.state.runs;
      expect(runs.map((r) => r.fights.length).toList(), [1, 1]);
      expect(runs.first.fights.single.runId, 'run-A');
      expect(runs.last.fights.single.runId, 'run-B');
    });

    test('enemiesDefeated counts each won fight once', () {
      final recorder = _withRun('run-1', 1);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e0', sequence: 0);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e1', sequence: 1);
      _recordBandit(
        recorder,
        runId: 'run-1',
        fightId: 'e2',
        sequence: 2,
        won: false,
      );
      // A replay must not bump the projection.
      _recordBandit(recorder, runId: 'run-1', fightId: 'e0', sequence: 0);

      expect(recorder.state.runs.single.enemiesDefeated, 2);
    });

    test('a conflicting payload at the same key is refused', () {
      final recorder = _withRun('run-1', 1);
      _recordBandit(recorder, runId: 'run-1', fightId: 'e0', sequence: 0);

      expect(
        () => _recordBandit(
          recorder,
          runId: 'run-1',
          fightId: 'e0',
          sequence: 0,
          won: false,
        ),
        throwsA(
          isA<AlmanacIntegrityException>().having(
            (e) => e.field,
            'field',
            'won',
          ),
        ),
      );
      expect(recorder.state.runs.single.fights.single.won, isTrue);
      expect(recorder.state.runs.single.enemiesDefeated, 1);
    });

    test('a fight for a run that has not begun still lands on that run', () {
      final recorder = AlmanacRecorder();
      _recordBandit(recorder, runId: 'run-1', fightId: 'e0', sequence: 0);
      recorder.beginRun(
        runId: 'run-1',
        runNumber: 1,
        lineageId: 'western',
        physiqueId: 'phy-a',
        startedAt: at(1),
      );

      final run = recorder.state.runs.single;
      expect(run.runId, 'run-1');
      expect(run.lineageId, 'western');
      expect(run.fights.single.fightId, 'e0');
    });
  });
}
