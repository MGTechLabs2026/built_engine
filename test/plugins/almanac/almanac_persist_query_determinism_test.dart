/// Phase 9 / spec §13.1 + §16 — persist → query determinism.
///
/// A populated [AlmanacState] is put through
/// `AlmanacSerialization.encode` → `decode`, then EVERY `AlmanacQueries`
/// getter is run against the original and the decoded state and the two
/// results are compared. `List` equality in `package:test` is order-sensitive,
/// so this also locks ordering. The whole state is checked for structural
/// round-trip equality and the canonical encoding is checked for stability.
///
/// No id is ever parsed here: every getter argument is a real id taken
/// straight from the fixture.
library;

import 'package:build_engine/almanac.dart';
import 'package:test/test.dart';

import 'support/almanac_fixtures.dart';

/// `MapEntry` has no value `==`; compare the ranked lists as `(key, value)`
/// records instead.
List<(String, int)> _pairs(List<MapEntry<String, int>> entries) => [
  for (final entry in entries) (entry.key, entry.value),
];

void main() {
  final original = fullyPopulatedState();
  final decoded = AlmanacSerialization.decode(
    AlmanacSerialization.encode(original),
  );
  final fromOriginal = AlmanacQueries(original);
  final fromDecoded = AlmanacQueries(decoded);

  group('whole-state round-trip', () {
    test('decoded == original (structural equality)', () {
      expect(decoded, equals(original));
    });

    test('encode(decoded) == encode(original) (canonical form is stable)', () {
      expect(
        AlmanacSerialization.encode(decoded),
        equals(AlmanacSerialization.encode(original)),
      );
    });

    test('stateToJson / stateFromJson round-trips identically too', () {
      final viaMap = AlmanacSerialization.stateFromJson(
        AlmanacSerialization.stateToJson(original),
      );
      expect(viaMap, equals(original));
    });
  });

  group('every AlmanacQueries getter is identical on original vs decoded', () {
    test('getRunHistory', () {
      expect(fromOriginal.getRunHistory(), isNotEmpty);
      expect(fromDecoded.getRunHistory(), equals(fromOriginal.getRunHistory()));
    });

    test('getRun (hit both runs + miss)', () {
      for (final runId in const ['run-a', 'run-b', 'run-missing']) {
        expect(fromDecoded.getRun(runId), equals(fromOriginal.getRun(runId)));
      }
      expect(fromOriginal.getRun('run-a'), isNotNull);
    });

    test('getBuildHistory', () {
      expect(fromOriginal.getBuildHistory(), hasLength(4));
      expect(
        fromDecoded.getBuildHistory(),
        equals(fromOriginal.getBuildHistory()),
      );
    });

    test('getBuild (composite (runId, buildId) key)', () {
      const keys = [
        ('run-a', 'ba-final'),
        ('run-b', 'bb-0'),
        ('run-a', 'bb-0'), // wrong pairing -> null
      ];
      for (final (runId, buildId) in keys) {
        expect(
          fromDecoded.getBuild(runId, buildId),
          equals(fromOriginal.getBuild(runId, buildId)),
        );
      }
      expect(fromOriginal.getBuild('run-a', 'ba-final'), isNotNull);
    });

    test('getBuildsForRun', () {
      for (final runId in const ['run-a', 'run-b']) {
        expect(
          fromDecoded.getBuildsForRun(runId),
          equals(fromOriginal.getBuildsForRun(runId)),
        );
      }
      expect(fromOriginal.getBuildsForRun('run-a'), hasLength(2));
    });

    test('getLineageHistory / getRunsForLineage', () {
      for (final lineageId in const ['lin-west', 'lin-east', 'lin-none']) {
        expect(
          fromDecoded.getLineageHistory(lineageId),
          equals(fromOriginal.getLineageHistory(lineageId)),
        );
        expect(
          fromDecoded.getRunsForLineage(lineageId),
          equals(fromOriginal.getRunsForLineage(lineageId)),
        );
      }
      expect(fromOriginal.getLineageHistory('lin-west'), isNotEmpty);
    });

    test('getRunsForPhysique', () {
      for (final physiqueId in const ['phy-iron', 'phy-jade', 'phy-none']) {
        expect(
          fromDecoded.getRunsForPhysique(physiqueId),
          equals(fromOriginal.getRunsForPhysique(physiqueId)),
        );
      }
      expect(fromOriginal.getRunsForPhysique('phy-iron'), isNotEmpty);
    });

    test('getTechniqueHistory', () {
      for (final instanceId in const ['ti-a', 'ti-b', 'ti-missing']) {
        expect(
          fromDecoded.getTechniqueHistory(instanceId),
          equals(fromOriginal.getTechniqueHistory(instanceId)),
        );
      }
      expect(fromOriginal.getTechniqueHistory('ti-a'), isNotNull);
    });

    test('getTechniqueInspirations', () {
      for (final instanceId in const ['ti-a', 'ti-b']) {
        expect(
          fromDecoded.getTechniqueInspirations(instanceId),
          equals(fromOriginal.getTechniqueInspirations(instanceId)),
        );
      }
      expect(fromOriginal.getTechniqueInspirations('ti-b'), hasLength(1));
    });

    test('getRunsUsingTechnique', () {
      for (final instanceId in const ['ti-a', 'ti-b', 'ti-missing']) {
        expect(
          fromDecoded.getRunsUsingTechnique(instanceId),
          equals(fromOriginal.getRunsUsingTechnique(instanceId)),
        );
      }
      expect(fromOriginal.getRunsUsingTechnique('ti-a'), isNotEmpty);
    });

    test('getBuildsUsingTechnique', () {
      for (final instanceId in const ['ti-a', 'ti-b']) {
        expect(
          fromDecoded.getBuildsUsingTechnique(instanceId),
          equals(fromOriginal.getBuildsUsingTechnique(instanceId)),
        );
      }
      expect(fromOriginal.getBuildsUsingTechnique('ti-a'), hasLength(2));
    });

    test('getAffixHistory', () {
      for (final affixId in const ['af-1', 'af-2', 'af-missing']) {
        expect(
          fromDecoded.getAffixHistory(affixId),
          equals(fromOriginal.getAffixHistory(affixId)),
        );
      }
      expect(fromOriginal.getAffixHistory('af-1'), isNotNull);
    });

    test('getDiscoveries', () {
      expect(fromOriginal.getDiscoveries(), hasLength(4));
      expect(
        fromDecoded.getDiscoveries(),
        equals(fromOriginal.getDiscoveries()),
      );
    });

    test('getRecentDiscoveries', () {
      for (final limit in const [0, 2, 3, 99]) {
        expect(
          fromDecoded.getRecentDiscoveries(limit: limit),
          equals(fromOriginal.getRecentDiscoveries(limit: limit)),
        );
      }
    });

    test('lineageStatistics', () {
      for (final lineageId in const ['lin-west', 'lin-east', 'lin-none']) {
        expect(
          fromDecoded.lineageStatistics(lineageId),
          equals(fromOriginal.lineageStatistics(lineageId)),
        );
      }
      expect(fromOriginal.lineageStatistics('lin-west').runs, 1);
    });

    test('mostUsedTechniques', () {
      expect(
        _pairs(fromDecoded.mostUsedTechniques()),
        equals(_pairs(fromOriginal.mostUsedTechniques())),
      );
      expect(
        _pairs(fromDecoded.mostUsedTechniques(limit: 1)),
        equals(_pairs(fromOriginal.mostUsedTechniques(limit: 1))),
      );
      expect(fromOriginal.mostUsedTechniques(), isNotEmpty);
    });

    test('mostUsedAffixes', () {
      expect(
        _pairs(fromDecoded.mostUsedAffixes()),
        equals(_pairs(fromOriginal.mostUsedAffixes())),
      );
      expect(
        _pairs(fromDecoded.mostUsedAffixes(limit: 1)),
        equals(_pairs(fromOriginal.mostUsedAffixes(limit: 1))),
      );
      expect(fromOriginal.mostUsedAffixes(), isNotEmpty);
    });

    test('discoveryCompletion', () {
      const known = <AlmanacDiscoveryType, Set<String>>{
        AlmanacDiscoveryType.technique: {'fam-a', 'fam-b', 'fam-c'},
        AlmanacDiscoveryType.techniqueVariant: {'fam-a', 'fam-b'},
        AlmanacDiscoveryType.item: {'iron_sword', 'jade_staff'},
        AlmanacDiscoveryType.affix: {'af-1', 'af-2', 'af-3', 'af-4'},
        AlmanacDiscoveryType.lineage: <String>{},
      };
      expect(
        fromDecoded.discoveryCompletion(known: known),
        equals(fromOriginal.discoveryCompletion(known: known)),
      );
      // The fixture really did populate each requested type.
      final completion = fromOriginal.discoveryCompletion(known: known);
      expect(completion[AlmanacDiscoveryType.technique]!.discovered, 1);
      expect(completion[AlmanacDiscoveryType.lineage]!.fraction, 0.0);
    });
  });
}
