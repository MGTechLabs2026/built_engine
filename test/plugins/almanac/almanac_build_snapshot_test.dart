/// Phase 4.7 — what a stored build snapshot preserves: sequence separation,
/// replay safety, the tome layout's slot and instance ids, the DNA back-fill,
/// and independence from the caller's source collections.
///
/// Building a snapshot from live Tome state is the bridge's job (Task 7), so
/// the layouts here are constructed directly as value objects.
library;

import 'package:build_engine/src/plugins/almanac/almanac_models.dart';
import 'package:build_engine/src/plugins/almanac/almanac_recorder.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

void main() {
  group('build snapshots', () {
    test('two postReward snapshots at different sequences stay separate', () {
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-1',
                buildId: 'b-r0',
                phase: BuildPhase.postReward,
                sequence: 0,
              ),
            )
            ..recordBuildSnapshot(
              buildRecord(
                runId: 'run-1',
                buildId: 'b-r1',
                phase: BuildPhase.postReward,
                sequence: 1,
              ),
            );

      final rewards =
          recorder.state.builds
              .where((b) => b.phase == BuildPhase.postReward)
              .toList();
      expect(rewards, hasLength(2));
      expect(rewards.map((b) => b.sequence).toList(), [0, 1]);
    });

    test('replaying both snapshots adds nothing', () {
      final first = buildRecord(
        runId: 'run-1',
        buildId: 'b-r0',
        phase: BuildPhase.postReward,
      );
      final second = buildRecord(
        runId: 'run-1',
        buildId: 'b-r1',
        phase: BuildPhase.postReward,
        sequence: 1,
      );
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(first)
            ..recordBuildSnapshot(second)
            ..recordBuildSnapshot(first)
            ..recordBuildSnapshot(second);

      expect(recorder.state.builds, hasLength(2));
    });

    test('the tome layout keeps its slot ids and instance ids', () {
      final recorder =
          AlmanacRecorder()..recordBuildSnapshot(
            buildRecord(
              runId: 'run-1',
              buildId: 'b0',
              tome: TomeLayoutSnapshot(
                width: 2,
                height: 1,
                slots: const [
                  TomeSlotSnapshot(
                    slotId: 's0',
                    occupantKind: 'technique',
                    occupantRefId: 'fam-a',
                    instanceId: 'ti-1',
                  ),
                  TomeSlotSnapshot(slotId: 's1', occupantKind: 'empty'),
                ],
              ),
            ),
          );

      final tome = recorder.state.builds.single.tome;
      expect(tome.width, 2);
      expect(tome.height, 1);
      expect(tome.slots.map((s) => s.slotId).toList(), ['s0', 's1']);
      expect(tome.slots.first.instanceId, 'ti-1');
      expect(tome.slots.first.occupantRefId, 'fam-a');
      expect(tome.slots.last.instanceId, isNull);
    });

    test('mutating the caller source lists afterwards changes nothing', () {
      final techniques = <TechniqueInstanceSnapshot>[
        techniqueSnapshot(instanceId: 'ti-1', baseFamilyId: 'fam-a'),
      ];
      final items = <ItemInstanceSnapshot>[
        itemSnapshot(definitionId: 'iron_sword'),
      ];
      final slots = <TomeSlotSnapshot>[
        const TomeSlotSnapshot(slotId: 's0', occupantKind: 'empty'),
      ];
      final recorder =
          AlmanacRecorder()..recordBuildSnapshot(
            buildRecord(
              runId: 'run-1',
              buildId: 'b0',
              techniques: techniques,
              items: items,
              tome: TomeLayoutSnapshot(slots: slots),
            ),
          );

      techniques.add(
        techniqueSnapshot(instanceId: 'ti-2', baseFamilyId: 'fam-b'),
      );
      items.add(itemSnapshot(definitionId: 'wooden_staff'));
      slots.add(const TomeSlotSnapshot(slotId: 's1', occupantKind: 'empty'));

      final build = recorder.state.builds.single;
      expect(build.techniques, hasLength(1));
      expect(build.items, hasLength(1));
      expect(build.tome.slots, hasLength(1));
    });

    test('an empty DNA is back-filled from the snapshot contents', () {
      final recorder =
          AlmanacRecorder()..recordBuildSnapshot(
            buildRecordWithoutDna(
              runId: 'run-1',
              buildId: 'b0',
              lineageId: 'western',
              physiqueId: 'phy-a',
              techniques: [
                techniqueSnapshot(
                  instanceId: 'ti-1',
                  baseFamilyId: 'fam-a',
                  axisProfile: const {'power': 5},
                ),
              ],
              items: [itemSnapshot(definitionId: 'iron_sword')],
              affixes: const [
                AffixSnapshot(
                  affixId: 'af-1',
                  stat: 'crit',
                  value: 1,
                  category: 'offensive',
                ),
              ],
            ),
          );

      final dna = recorder.state.builds.single.dna;
      expect(dna.tokens, [
        'WESTERN',
        'PHY-A',
        'FAM-A',
        'IRON_SWORD',
        'OFFENSIVE',
        'POWER',
      ]);
      expect(dna.signature, isNotEmpty);
    });

    test('a supplied DNA is left exactly as the caller computed it', () {
      final dna = BuildDna(tokens: const ['CUSTOM'], signature: 'deadbeef');
      final recorder =
          AlmanacRecorder()..recordBuildSnapshot(
            buildRecord(runId: 'run-1', buildId: 'b0', dna: dna),
          );

      expect(recorder.state.builds.single.dna, dna);
    });

    test('the DNA back-fill is idempotent under replay and hydrate', () {
      final record = buildRecordWithoutDna(runId: 'run-1', buildId: 'b0');
      final recorder =
          AlmanacRecorder()
            ..recordBuildSnapshot(record)
            ..recordBuildSnapshot(record);

      expect(recorder.state.builds, hasLength(1));
      expect(AlmanacRecorder(recorder.state).state, recorder.state);
    });

    test('a stored snapshot collection cannot be grown from outside', () {
      final recorder =
          AlmanacRecorder()..recordBuildSnapshot(
            buildRecord(
              runId: 'run-1',
              buildId: 'b0',
              techniques: [
                techniqueSnapshot(instanceId: 'ti-1', baseFamilyId: 'fam-a'),
              ],
            ),
          );
      final build = recorder.state.builds.single;

      expect(
        () => build.techniques.add(
          techniqueSnapshot(instanceId: 'ti-2', baseFamilyId: 'fam-b'),
        ),
        throwsUnsupportedError,
      );
      expect(() => build.tome.slots.clear(), throwsUnsupportedError);
      expect(recorder.state.builds.single.techniques, hasLength(1));
    });
  });
}
