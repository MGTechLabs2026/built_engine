import 'package:build_engine/build_engine.dart';

import 'enemy.dart';

/// Stable content ids for the run's 5 named enemies, split into two
/// difficulty pools — [RunEnemies.weakPool] for the first two fights of
/// a cycle, [RunEnemies.eliteBossPool] for the third. A typo here is a
/// compile error, not a silent runtime string mismatch, the same
/// rationale `ItemIds`/`TechniqueIds` already use.
abstract final class RunEnemies {
  static const trainingDummy = 'training_dummy';
  static const bandit = 'bandit';
  static const martialAdept = 'martial_adept';
  static const eliteWarrior = 'elite_warrior';
  static const boss = 'boss';

  /// Base enemies for a cycle's first two ("weak") fights.
  static const weakPool = [trainingDummy, bandit, martialAdept];

  /// Base enemies for a cycle's third ("elite/boss") fight.
  static const eliteBossPool = [eliteWarrior, boss];
}

/// The 5 enemies the run draws from, as data — `ContentRegistry`-loaded
/// the same way every real content plugin's own `*ContentDefinitions`
/// constant is (`itemContentDefinitions`, `techniqueContentDefinitions`,
/// ...), per `CLAUDE.md`'s own Plugin Types list naming Enemies as a
/// content type, not hand-written Dart objects. There is no dedicated
/// "Enemy plugin" — enemies exist only for this run-composition layer,
/// not as a reusable content type another plugin loads independently —
/// so `runGame` loads this batch directly via `context.content.loadAll`
/// rather than through a `GamePlugin.initialize`.
const enemyContentDefinitions = <Map<String, dynamic>>[
  {
    'id': RunEnemies.trainingDummy,
    'type': 'enemy',
    'tags': ['enemy'],
    'health': 20,
    'damage': 2,
    'damageStat': 'dummy_attack',
    'initiative': 1,
  },
  {
    'id': RunEnemies.bandit,
    'type': 'enemy',
    'tags': ['enemy'],
    'health': 27,
    'damage': 4,
    'damageStat': 'bandit_attack',
    'initiative': 6,
  },
  {
    'id': RunEnemies.martialAdept,
    'type': 'enemy',
    'tags': ['enemy'],
    'health': 36,
    'damage': 5,
    'damageStat': 'adept_attack',
    'initiative': 8,
  },
  {
    'id': RunEnemies.eliteWarrior,
    'type': 'enemy',
    'tags': ['enemy'],
    'health': 44,
    'damage': 6,
    'damageStat': 'elite_attack',
    'initiative': 9,
  },
  {
    'id': RunEnemies.boss,
    'type': 'enemy',
    'tags': ['enemy'],
    'health': 55,
    'damage': 7,
    'damageStat': 'boss_attack',
    'initiative': 9,
  },
];

/// Builds an [Enemy] from a loaded [ContentDefinition] — `extra['health']`/
/// `extra['damage']`/`extra['damageStat']`/`extra['initiative']` supply
/// the four fields `ContentRegistry` doesn't natively parse, mirroring
/// `itemDefinitionFromContent`'s own shape.
Enemy enemyDefinitionFromContent(ContentDefinition definition) => Enemy(
      id: definition.id,
      health: definition.extra['health'] as num,
      damage: definition.extra['damage'] as num,
      damageStat: definition.extra['damageStat'] as String,
      initiative: definition.extra['initiative'] as num,
    );

/// Resolves and parses enemy [id] from [context]'s loaded content in one
/// call — the same convenience `itemDefinition`/`techniqueDefinition`
/// already provide for their own content. Stateless: re-resolves from
/// `context.content` on every call, no caching.
Enemy enemyDefinition(String id, PluginContext context) =>
    enemyDefinitionFromContent(context.content.get(id));

/// Scales [base]'s health/damage to [cycleNumber] (1-indexed) — a flat
/// 12% growth per completed cycle, applied to both fights-1&2 and
/// fight-3 bases alike, so the run gets harder indefinitely rather than
/// plateauing at a fixed 5-enemy roster. Deliberately simple ("do not
/// tune the numbers yet, we are measuring") — [id]/[damageStat]/
/// [initiative] pass through unscaled.
Enemy scaledEnemy(Enemy base, int cycleNumber) {
  final factor = 1 + 0.12 * (cycleNumber - 1);
  return Enemy(
    id: base.id,
    health: (base.health * factor).round(),
    damage: (base.damage * factor).round(),
    damageStat: base.damageStat,
    initiative: base.initiative,
  );
}
