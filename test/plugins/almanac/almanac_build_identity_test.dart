/// Phase 4.7 — build snapshots are keyed by the structural `(runId, buildId)`
/// composite, never by a concatenated or parsed string.
///
/// Every relationship below is asserted through `build.runId` / `build.buildId`
/// / `build.phase` / `build.sequence`, so a client adapter emitting opaque ids
/// like `action-8f3a91` behaves identically to one emitting `run-1:initial:0`.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_queries.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

/// Reads a build back through the shipping query API — the composite
/// `(runId, buildId)` match in `AlmanacQueries.getBuild`, not a hand-rolled
/// scan.
AlmanacBuildRecord? _getBuild(
  AlmanacRecorder recorder,
  String runId,
  String buildId,
) => AlmanacQueries(recorder.state).getBuild(runId, buildId);

void main() {
  group('build identity', () {
    test('(run-A, build-1) and (run-B, build-1) are two records', () {
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-A', buildId: 'build-1'),
            )
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-B',
                buildId: 'build-1',
                lineageId: 'eastern',
              ),
            );

      final builds = recorder.state.builds;
      expect(builds, hasLength(2));
      expect(builds.map((b) => b.runId).toList(), ['run-A', 'run-B']);
      expect(builds.every((b) => b.buildId == 'build-1'), isTrue);

      final a = _getBuild(recorder, 'run-A', 'build-1');
      final b = _getBuild(recorder, 'run-B', 'build-1');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(b));
      expect(a!.lineageId, 'lin-a');
      expect(b!.lineageId, 'eastern');
    });

    test('(run-A, build-1) submitted twice identically is one record', () {
      final record = buildRecord(runId: 'run-A', buildId: 'build-1');
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(record)
            ..recordBuildSnapshot(record);

      expect(recorder.state.builds, hasLength(1));
    });

    test('two structurally-equal instances at one key are one record', () {
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-A', buildId: 'build-1'),
            )
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-A', buildId: 'build-1'),
            );

      expect(recorder.state.builds, hasLength(1));
    });

    test('a conflicting payload at one key is refused', () {
      final established = buildRecord(runId: 'run-A', buildId: 'build-1');
      final recorder = AlmanacRecorder()..recordBuildSnapshot(established);

      expect(
        () => recorder.recordBuildSnapshot(
          buildRecord(
            runId: 'run-A',
            buildId: 'build-1',
            phase: BuildPhase.postReward,
            sequence: 2,
          ),
        ),
        throwsA(isA<AlmanacIntegrityException>()),
      );
      expect(recorder.state.builds.single, established);
      expect(recorder.state.builds.single.phase, BuildPhase.initial);
    });

    test('distinct (runId, phase, sequence) triples are distinct records', () {
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-1',
                buildId: 'b0',
                phase: BuildPhase.initial,
                sequence: 0,
              ),
            )
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-1',
                buildId: 'b1',
                phase: BuildPhase.postReward,
                sequence: 1,
              ),
            )
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-1',
                buildId: 'b2',
                phase: BuildPhase.postReward,
                sequence: 2,
              ),
            )
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-1',
                buildId: 'b3',
                phase: BuildPhase.postTraining,
                sequence: 3,
              ),
            );

      final builds = recorder.state.builds;
      expect(builds, hasLength(4));
      expect(builds.map((b) => b.phase).toList(), [
        BuildPhase.initial,
        BuildPhase.postReward,
        BuildPhase.postReward,
        BuildPhase.postTraining,
      ]);
      expect(builds.map((b) => b.sequence).toList(), [0, 1, 2, 3]);
    });

    test('two finalBuild submissions for one run are one canonical record', () {
      final record = buildRecord(
        runId: 'run-1',
        buildId: 'b-final',
        phase: BuildPhase.finalBuild,
        sequence: 4,
      );
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(record)
            ..recordBuildSnapshot(record);

      final finals =
          recorder.state.builds
              .where((b) => b.phase == BuildPhase.finalBuild)
              .toList();
      expect(finals, hasLength(1));
      expect(finals.single.runId, 'run-1');
      expect(finals.single.sequence, 4);
    });

    test('opaque ids behave exactly like structured ones', () {
      final structured =
          AlmanacRecorder()
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-1', buildId: 'run-1:initial:0'),
            )
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-2', buildId: 'run-1:initial:0'),
            );
      final opaque =
          AlmanacRecorder()
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-1', buildId: 'action-8f3a91'),
            )
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-2', buildId: 'action-8f3a91'),
            );

      expect(structured.state.builds, hasLength(2));
      expect(opaque.state.builds, hasLength(2));
      // A buildId that textually names run-1 still belongs to run-2 when the
      // explicit field says so.
      expect(_getBuild(structured, 'run-2', 'run-1:initial:0'), isNotNull);
      expect(structured.state.builds.last.runId, 'run-2');
    });

    test('build identity survives a hydrate', () {
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(
              buildRecord(runId: 'run-A', buildId: 'build-1'),
            )
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-B',
                buildId: 'build-1',
                lineageId: 'eastern',
              ),
            );

      final rehydrated = AlmanacRecorder(recorder.state);
      expect(rehydrated.state, recorder.state);
      // ...and it is still idempotent afterwards.
      rehydrated.recordBuildSnapshot(
        buildRecord(runId: 'run-A', buildId: 'build-1'),
      );
      expect(rehydrated.state.builds, hasLength(2));
    });
  });
}
