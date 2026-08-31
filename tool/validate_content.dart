// tool/validate_content.dart
//
// Standalone content audit for Content Expansion V1 (matrix §J). Prints a
// report and exits non-zero on any failure. The authoritative version of
// these checks — with per-case reasons — lives in
// `test/content/content_expansion_audit_test.dart`; this script is for a
// quick command-line pass (`dart run tool/validate_content.dart`).

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/game/enemy_content.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/martial_arts/martial_item_content.dart';
import 'package:build_engine/src/plugins/martial_arts/martial_styles.dart';
import 'package:build_engine/src/plugins/martial_arts/martial_technique_content.dart';
import 'package:build_engine/src/plugins/physique/physique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';

void main() {
  final problems = <String>[];
  void check(bool ok, String message) {
    if (!ok) problems.add(message);
  }

  const batches = <String, List<Map<String, dynamic>>>{
    'technique': techniqueContentDefinitions,
    'item': itemContentDefinitions,
    'martial technique': martialTechniqueContentDefinitions,
    'martial item': martialItemContentDefinitions,
    'physique': physiqueContentDefinitions,
    'enemy': enemyContentDefinitions,
  };

  // 1. unique ids
  final seen = <String, String>{};
  batches.forEach((kind, batch) {
    for (final d in batch) {
      final id = d['id'] as String;
      if (seen.containsKey(id)) {
        check(false, 'duplicate id "$id" ($kind and ${seen[id]})');
      }
      seen[id] = kind;
    }
  });

  // 2. evolution / gradeEvolution targets resolve
  final techniqueIds = {
    for (final d in techniqueContentDefinitions) d['id'] as String,
  };
  final itemIds = {for (final d in itemContentDefinitions) d['id'] as String};
  for (final d in techniqueContentDefinitions) {
    for (final e in (d['evolution'] as List? ?? const [])) {
      final t = (e as Map)['targetId'] as String;
      check(techniqueIds.contains(t), '${d['id']} evolves to missing "$t"');
    }
  }
  for (final d in itemContentDefinitions) {
    for (final e in (d['gradeEvolution'] as List? ?? const [])) {
      final t = (e as Map)['targetId'] as String;
      check(itemIds.contains(t), '${d['id']} grade-evolves to missing "$t"');
    }
  }

  // 3. tier-monotone technique ladders
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
      check(rank(tierOf[child]!) > rank(d['tier'] as String),
          '${d['id']} (${d['tier']}) -> $child (${tierOf[child]}) does not deepen');
    }
  }

  // 4. training dims + aff/rarity tags
  const trainingDims = {
    TrainingDimensions.speed, TrainingDimensions.power,
    TrainingDimensions.precision, TrainingDimensions.reaction,
    TrainingDimensions.control, TrainingDimensions.consistency,
  };
  const affinities = {'aff:burst', 'aff:power', 'aff:sturdy', 'aff:endurance'};
  const rarities = {
    'rarity:common', 'rarity:uncommon', 'rarity:rare', 'rarity:master',
  };
  for (final batch in [techniqueContentDefinitions, itemContentDefinitions]) {
    for (final d in batch) {
      for (final k in (d['training'] as Map? ?? const {}).keys) {
        check(trainingDims.contains(k), '${d['id']} unknown training dim "$k"');
      }
      for (final t in (d['tags'] as List).cast<String>()) {
        if (t.startsWith('aff:')) {
          check(affinities.contains(t), '${d['id']} bad affinity tag "$t"');
        }
        if (t.startsWith('rarity:')) {
          check(rarities.contains(t), '${d['id']} bad rarity tag "$t"');
        }
      }
    }
  }

  // 5. style references
  final styleIds = {
    MartialStyles.polearming, MartialStyles.wrestling, MartialStyles.fencing,
    MartialStyles.shaolin, MartialStyles.taiChi, MartialStyles.kunlun,
  };
  for (final d in martialTechniqueContentDefinitions) {
    for (final c in (d['conditions'] as List? ?? const [])) {
      final tag = (c as Map)['tag'] as String?;
      if (tag != null && tag.startsWith('style:')) {
        check(styleIds.contains(tag.substring(6)),
            '${d['id']} conditions on unknown style "$tag"');
      }
    }
  }

  // 6. bases <-> basic tier
  final basicTier = {
    for (final d in techniqueContentDefinitions)
      if (d['tier'] == EvolutionTiers.basic) d['id'] as String,
  };
  check(basicTier.difference(TechniqueIds.bases.toSet()).isEmpty &&
      TechniqueIds.bases.toSet().difference(basicTier).isEmpty,
      'TechniqueIds.bases != the basic-tier techniques '
      '(${TechniqueIds.bases} vs $basicTier)');

  final total = batches.values.fold<int>(0, (a, b) => a + b.length);
  if (problems.isEmpty) {
    print('content OK — $total definitions across ${batches.length} batches');
  } else {
    print('content audit FAILED (${problems.length}):');
    for (final p in problems) {
      print('  - $p');
    }
    throw StateError('${problems.length} content problem(s)');
  }
}
