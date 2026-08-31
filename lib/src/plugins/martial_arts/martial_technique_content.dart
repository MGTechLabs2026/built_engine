import 'package:build_engine/build_engine.dart';

import 'martial_styles.dart';
import 'martial_technique_action.dart';
import 'martial_vocabulary.dart';

/// The techniques and stances this plugin
/// implements, as data — loaded into `PluginContext.content` via
/// `PluginSdk.registerContentBatch` in `MartialArtsPlugin.initialize`
/// (mirroring `ElementalPlugin`'s `elementalContentDefinitions`),
/// and also what the convenience factory functions below build a
/// [MartialTechniqueAction] from (see `martialTechniqueFromDefinition`).
///
/// `baseDamage`/`damageStat` are MartialArts-specific fields
/// `ContentRegistry` doesn't recognize — they surface verbatim on
/// `ContentDefinition.extra`, exactly like `components.attack` did in
/// `claude.md`'s own `iron_sword` example. `effects` does double duty as
/// "what this technique does to its actor" for both shapes: for an
/// attack technique that's its resource cost/reward (paid once, before
/// the damage lands — `costEffects` on `MartialTechniqueAction`); for a
/// stance (no `baseDamage`) it's the self-buff a self-targeted technique
/// applies (`selfEffects`). See `martialTechniqueFromDefinition`.
const martialTechniqueContentDefinitions = <Map<String, dynamic>>[
  {
    'id': 'jab',
    'type': 'technique',
    'tags': ['martial', 'fist', MartialTraditions.western, 'external'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.polearming}'},
    ],
    'effects': [
      {
        'type': 'modifyResource',
        'resource': MartialResources.momentum,
        'delta': 8,
      },
    ],
    'baseDamage': 6,
    'damageStat': 'punch',
  },
  {
    'id': 'power_cross',
    'type': 'technique',
    'tags': ['martial', 'fist', MartialTraditions.western, 'external'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.polearming}'},
      {
        'type': 'resourceAbove',
        'resource': MartialResources.momentum,
        'threshold': 19,
      },
    ],
    'effects': [
      {
        'type': 'modifyResource',
        'resource': MartialResources.momentum,
        'delta': -20,
      },
    ],
    'baseDamage': 18,
    'damageStat': 'punch',
  },
  {
    'id': 'guard_stance',
    'type': 'technique',
    'tags': ['martial', 'fist', MartialTraditions.western],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.polearming}'},
    ],
    'effects': [
      {'type': 'addTag', 'tag': MartialStances.guard},
      {
        'type': 'modifyResource',
        'resource': MartialResources.momentum,
        'delta': 5,
      },
    ],
  },
  {
    'id': 'palm_strike',
    'type': 'technique',
    'tags': ['martial', 'palm', MartialTraditions.eastern, 'external'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.shaolin}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 2},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -3},
    ],
    'baseDamage': 8,
    'damageStat': 'palm',
  },
  {
    'id': 'blazing_palm',
    'type': 'technique',
    'tags': ['martial', 'palm', MartialTraditions.eastern, 'fire', 'qi'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.shaolin}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 7},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -8},
    ],
    'baseDamage': 14,
    'damageStat': 'palm',
  },
  {
    'id': 'iron_body_stance',
    'type': 'technique',
    'tags': ['martial', 'qi', 'internal', MartialTraditions.eastern],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.shaolin}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 4},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -5},
      {'type': 'addTag', 'tag': MartialStances.ironBody},
    ],
  },
  {
    'id': 'push_hands',
    'type': 'technique',
    'tags': ['martial', 'internal', MartialTraditions.eastern, 'qi'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.taiChi}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 3},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -4},
    ],
    'baseDamage': 7,
    'damageStat': 'internal',
  },
  {
    'id': 'whirling_palm',
    'type': 'technique',
    'tags': ['martial', 'internal', MartialTraditions.eastern, 'qi', 'yang'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.taiChi}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 5},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -6},
    ],
    'baseDamage': 10,
    'damageStat': 'internal',
  },
  {
    'id': 'yielding_stance',
    'type': 'technique',
    'tags': ['martial', 'internal', MartialTraditions.eastern, 'qi', 'counter'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.taiChi}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 2},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -3},
      {'type': 'addTag', 'tag': MartialStances.taiChi},
    ],
  },

  // ══ Content Expansion V1: style-technique sets for the three styles
  //    that previously had none. Same opener / spender / stance shape as
  //    polearming and shaolin above. Matrix §C.3.

  // --- Wrestling (western, momentum) ---
  {
    'id': 'collar_tie',
    'type': 'technique',
    'tags': ['martial', 'grapple', MartialTraditions.western, 'external'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.wrestling}'},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.momentum, 'delta': 8},
    ],
    'baseDamage': 5,
    'damageStat': 'grapple',
  },
  {
    'id': 'takedown',
    'type': 'technique',
    'tags': ['martial', 'grapple', MartialTraditions.western, 'external'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.wrestling}'},
      {'type': 'resourceAbove', 'resource': MartialResources.momentum, 'threshold': 19},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.momentum, 'delta': -20},
    ],
    'baseDamage': 17,
    'damageStat': 'grapple',
  },
  {
    'id': 'sprawl_stance',
    'type': 'technique',
    'tags': ['martial', 'grapple', MartialTraditions.western, 'counter'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.wrestling}'},
    ],
    'effects': [
      {'type': 'addTag', 'tag': MartialStances.sprawl},
      {'type': 'modifyResource', 'resource': MartialResources.momentum, 'delta': 5},
    ],
  },

  // --- Fencing (western, momentum) ---
  {
    'id': 'lunge',
    'type': 'technique',
    'tags': ['martial', 'thrust', MartialTraditions.western, 'external'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.fencing}'},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.momentum, 'delta': 8},
    ],
    'baseDamage': 6,
    'damageStat': 'thrust',
  },
  {
    'id': 'riposte',
    'type': 'technique',
    'tags': ['martial', 'thrust', MartialTraditions.western, 'external', 'counter'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.fencing}'},
      {'type': 'resourceAbove', 'resource': MartialResources.momentum, 'threshold': 15},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.momentum, 'delta': -16},
    ],
    'baseDamage': 14,
    'damageStat': 'thrust',
  },
  {
    'id': 'en_garde_stance',
    'type': 'technique',
    'tags': ['martial', 'thrust', MartialTraditions.western],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.fencing}'},
    ],
    'effects': [
      {'type': 'addTag', 'tag': MartialStances.enGarde},
      {'type': 'modifyResource', 'resource': MartialResources.momentum, 'delta': 5},
    ],
  },

  // --- Kunlun (eastern, qi) ---
  {
    'id': 'crescent_slash',
    'type': 'technique',
    'tags': ['martial', 'blade', MartialTraditions.eastern, 'external'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.kunlun}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 2},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -3},
    ],
    'baseDamage': 8,
    'damageStat': 'blade',
  },
  {
    'id': 'moonfall_slash',
    'type': 'technique',
    'tags': ['martial', 'blade', MartialTraditions.eastern, 'external', 'yang'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.kunlun}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 7},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -8},
    ],
    'baseDamage': 15,
    'damageStat': 'blade',
  },
  {
    'id': 'swallow_step',
    'type': 'technique',
    'tags': ['martial', 'blade', MartialTraditions.eastern, 'counter'],
    'conditions': [
      {'type': 'hasTag', 'tag': 'style:${MartialStyles.kunlun}'},
      {'type': 'resourceAbove', 'resource': MartialResources.qi, 'threshold': 2},
    ],
    'effects': [
      {'type': 'modifyResource', 'resource': MartialResources.qi, 'delta': -3},
      {'type': 'addTag', 'tag': MartialStances.swallow},
    ],
  },
];

/// Builds a [MartialTechniqueAction] for [actor]/[targets] from a loaded
/// [ContentDefinition]. [ContentDefinition.effects] does double duty:
/// for an attack technique (`extra['baseDamage']` present) it becomes
/// [MartialTechniqueAction.costEffects] — the resource cost/reward paid
/// once before the damage lands; for a stance (`baseDamage` absent) it
/// becomes [MartialTechniqueAction.selfEffects] instead — the self-buff
/// applied when the technique targets its own actor. Never both, same
/// invariant `MartialTechniqueAction`'s own constructor documents.
MartialTechniqueAction martialTechniqueFromDefinition(
  ContentDefinition definition, {
  required EntityId actor,
  required List<EntityId> targets,
}) {
  final baseDamage = definition.extra['baseDamage'] as num?;
  final damageStat = definition.extra['damageStat'] as String?;
  return MartialTechniqueAction(
    actor: actor,
    targets: targets,
    tags: definition.tags,
    conditions: definition.conditions,
    costEffects: baseDamage != null ? definition.effects : const [],
    baseDamage: baseDamage,
    damageStat: damageStat,
    selfEffects: baseDamage == null ? definition.effects : const [],
  );
}

/// Parses [martialTechniqueContentDefinitions] into a fresh
/// [ContentRegistry] and looks up [id]. A throwaway registry on every
/// call, deliberately — a persistent module-level one would be exactly
/// the singleton pattern `ARCHITECTURE_AUDIT.md` checked this engine for
/// and confirmed absent everywhere else; techniques are invoked at most
/// once per actor per turn in a turn-based game, so the reparse cost is
/// immaterial. `MartialArtsPlugin.initialize` separately loads the same
/// definitions into the real, shared `PluginContext.content` (via
/// `PluginSdk.registerContentBatch`) so they're genuinely discoverable
/// by any plugin — this function exists only for the convenience
/// factories below, which predate `ContentRegistry` and are kept at
/// their original, context-free call shape for backward compatibility.
MartialTechniqueAction _technique(
  String id, {
  required EntityId actor,
  required List<EntityId> targets,
}) {
  final registry = ContentRegistry()
    ..loadAll(martialTechniqueContentDefinitions);
  return martialTechniqueFromDefinition(registry.get(id),
      actor: actor, targets: targets);
}

// --- Polearming ---

MartialTechniqueAction jab({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('jab', actor: actor, targets: targets);

MartialTechniqueAction powerCross({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('power_cross', actor: actor, targets: targets);

MartialTechniqueAction guardStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('guard_stance', actor: actor, targets: targets);

// --- Shaolin ---

MartialTechniqueAction palmStrike({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('palm_strike', actor: actor, targets: targets);

MartialTechniqueAction blazingPalm({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('blazing_palm', actor: actor, targets: targets);

MartialTechniqueAction ironBodyStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('iron_body_stance', actor: actor, targets: targets);

// --- Tai Chi ---

MartialTechniqueAction pushHands({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('push_hands', actor: actor, targets: targets);

MartialTechniqueAction whirlingPalm({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('whirling_palm', actor: actor, targets: targets);

MartialTechniqueAction yieldingStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('yielding_stance', actor: actor, targets: targets);

// --- Wrestling (Content Expansion V1) ---

MartialTechniqueAction collarTie({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('collar_tie', actor: actor, targets: targets);

MartialTechniqueAction takedown({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('takedown', actor: actor, targets: targets);

MartialTechniqueAction sprawlStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('sprawl_stance', actor: actor, targets: targets);

// --- Fencing (Content Expansion V1) ---

MartialTechniqueAction lunge({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('lunge', actor: actor, targets: targets);

MartialTechniqueAction riposte({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('riposte', actor: actor, targets: targets);

MartialTechniqueAction enGardeStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('en_garde_stance', actor: actor, targets: targets);

// --- Kunlun (Content Expansion V1) ---

MartialTechniqueAction crescentSlash({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('crescent_slash', actor: actor, targets: targets);

MartialTechniqueAction moonfallSlash({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('moonfall_slash', actor: actor, targets: targets);

MartialTechniqueAction swallowStep({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    _technique('swallow_step', actor: actor, targets: targets);
