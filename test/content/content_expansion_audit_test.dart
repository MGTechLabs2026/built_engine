import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/game/enemy_content.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/martial_arts/martial_item_content.dart';
import 'package:build_engine/src/plugins/martial_arts/martial_styles.dart';
import 'package:build_engine/src/plugins/martial_arts/martial_technique_content.dart';
import 'package:build_engine/src/plugins/physique/physique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

/// A whole-catalogue audit for Content Expansion V1 (matrix §J). Runs the
/// checks a `tool/validate_content.dart` would: unique ids, valid
/// evolution targets, acyclic trees, tier-monotone ladders, valid
/// training dimensions, valid style/affinity/rarity references.
void main() {
  const allContent = <List<Map<String, dynamic>>>[
    techniqueContentDefinitions,
    itemContentDefinitions,
    martialTechniqueContentDefinitions,
    martialItemContentDefinitions,
    physiqueContentDefinitions,
    enemyContentDefinitions,
  ];

  const trainingDims = {
    TrainingDimensions.speed,
    TrainingDimensions.power,
    TrainingDimensions.precision,
    TrainingDimensions.reaction,
    TrainingDimensions.control,
    TrainingDimensions.consistency,
  };
  const affinities = {'aff:burst', 'aff:power', 'aff:sturdy', 'aff:endurance'};
  const rarities = {
    'rarity:common', 'rarity:uncommon', 'rarity:rare', 'rarity:master',
  };
  final styleIds = {
    MartialStyles.polearming, MartialStyles.wrestling, MartialStyles.fencing,
    MartialStyles.shaolin, MartialStyles.taiChi, MartialStyles.kunlun,
  };

  test('every content id is globally unique', () {
    final seen = <String, int>{};
    for (final batch in allContent) {
      for (final d in batch) {
        seen.update(d['id'] as String, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final dupes = {
      for (final e in seen.entries)
        if (e.value > 1) e.key: e.value,
    };
    expect(dupes, isEmpty, reason: 'duplicate content ids: $dupes');
  });

  test('every technique evolution targetId resolves to a defined technique', () {
    final ids = {for (final d in techniqueContentDefinitions) d['id'] as String};
    for (final d in techniqueContentDefinitions) {
      for (final e in (d['evolution'] as List? ?? const [])) {
        expect(ids, contains((e as Map)['targetId']),
            reason: '${d['id']} -> missing ${e['targetId']}');
      }
    }
  });

  test('every item gradeEvolution targetId resolves to a defined item', () {
    final ids = {for (final d in itemContentDefinitions) d['id'] as String};
    for (final d in itemContentDefinitions) {
      for (final e in (d['gradeEvolution'] as List? ?? const [])) {
        expect(ids, contains((e as Map)['targetId']),
            reason: '${d['id']} -> missing ${e['targetId']}');
      }
    }
  });

  test('technique and item evolution graphs are acyclic', () {
    void assertAcyclic(
        List<Map<String, dynamic>> batch, String edgeKey) {
      final edges = <String, List<String>>{
        for (final d in batch)
          d['id'] as String: [
            for (final e in (d[edgeKey] as List? ?? const []))
              (e as Map)['targetId'] as String,
          ],
      };
      final visiting = <String>{};
      final done = <String>{};
      bool hasCycle(String node) {
        if (done.contains(node)) return false;
        if (!visiting.add(node)) return true;
        for (final next in edges[node] ?? const <String>[]) {
          if (hasCycle(next)) return true;
        }
        visiting.remove(node);
        done.add(node);
        return false;
      }

      for (final node in edges.keys) {
        expect(hasCycle(node), isFalse, reason: 'cycle through $node');
      }
    }

    assertAcyclic(techniqueContentDefinitions, 'evolution');
    assertAcyclic(itemContentDefinitions, 'gradeEvolution');
  });

  test('every technique evolution strictly deepens the tier', () {
    int rank(String tier) => const [
          EvolutionTiers.basic,
          EvolutionTiers.intermediate,
          EvolutionTiers.advanced,
          EvolutionTiers.master,
        ].indexOf(tier);
    final tierOf = {
      for (final d in techniqueContentDefinitions)
        d['id'] as String: d['tier'] as String,
    };
    for (final d in techniqueContentDefinitions) {
      for (final e in (d['evolution'] as List? ?? const [])) {
        final child = (e as Map)['targetId'] as String;
        expect(rank(tierOf[child]!), greaterThan(rank(d['tier'] as String)),
            reason: '${d['id']} (${d['tier']}) -> $child (${tierOf[child]})');
      }
    }
  });

  test('every training map key is a known TrainingDimension', () {
    for (final batch in [techniqueContentDefinitions, itemContentDefinitions]) {
      for (final d in batch) {
        for (final k in (d['training'] as Map? ?? const {}).keys) {
          expect(trainingDims, contains(k),
              reason: '${d['id']} uses unknown training dim "$k"');
        }
      }
    }
  });

  test('every aff:/rarity: tag on a technique or item is a valid value', () {
    for (final batch in [techniqueContentDefinitions, itemContentDefinitions]) {
      for (final d in batch) {
        for (final t in (d['tags'] as List).cast<String>()) {
          if (t.startsWith('aff:')) {
            expect(affinities, contains(t), reason: '${d['id']} bad tag $t');
          }
          if (t.startsWith('rarity:')) {
            expect(rarities, contains(t), reason: '${d['id']} bad tag $t');
          }
        }
      }
    }
  });

  test('every style:<id> condition on a martial technique names a real style',
      () {
    for (final d in martialTechniqueContentDefinitions) {
      for (final c in (d['conditions'] as List? ?? const [])) {
        final tag = (c as Map)['tag'] as String?;
        if (tag != null && tag.startsWith('style:')) {
          expect(styleIds, contains(tag.substring(6)),
              reason: '${d['id']} conditions on unknown $tag');
        }
      }
    }
  });

  test('TechniqueIds.bases lists exactly the basic-tier techniques', () {
    final basicTier = {
      for (final d in techniqueContentDefinitions)
        if (d['tier'] == EvolutionTiers.basic) d['id'] as String,
    };
    expect(basicTier, equals(TechniqueIds.bases.toSet()));
  });

  test('every combinable item chain ends at a class-9 terminal with no '
      'further gradeEvolution', () {
    final byId = {for (final d in itemContentDefinitions) d['id'] as String: d};
    for (final d in itemContentDefinitions) {
      if (d['maxClass'] == null) continue;
      final targets = [
        for (final e in (d['gradeEvolution'] as List? ?? const []))
          (e as Map)['targetId'] as String,
      ];
      for (final t in targets) {
        expect(byId[t]!['maxClass'], isNotNull,
            reason: '$t is a grade target but not itself combinable');
      }
    }
    // the masterwork tier is terminal
    final terminals = itemContentDefinitions.where((d) => d['maxClass'] == 9);
    expect(terminals, isNotEmpty);
    for (final d in terminals) {
      expect(d['gradeEvolution'], isNull,
          reason: '${d['id']} is class 9 but still has a grade path');
    }
  });

  test('the whole catalogue loads through ContentRegistry without a '
      'ContentDuplicateIdException', () {
    final registry = ContentRegistry();
    for (final batch in allContent) {
      expect(() => registry.loadAll(batch), returnsNormally);
    }
    // sanity: the V1 headline counts
    expect(registry.allOfType('technique').length,
        techniqueContentDefinitions.length + martialTechniqueContentDefinitions.length);
  });
}
