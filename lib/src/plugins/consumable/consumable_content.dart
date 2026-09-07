import 'package:build_engine/build_engine.dart';

import 'consumable_definition.dart';
import 'consumable_vocabulary.dart';

/// SP3 consumables as data — loaded into `PluginContext.content` via
/// `PluginSdk.registerContentBatch` in `ConsumablePlugin.initialize`.
/// Task 9 fills this out; this is the minimal single entry.
const consumableContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ConsumableIds.healPotion,
    'type': consumableReferenceType,
    'tags': <String>['consumable'],
    'charges': 1,
    'priority': 8,
    'effect': {'heal': 20},
  },
];

const _selfEffectKeys = {'heal', 'grant', 'removeAllStatuses'};
const _enemyEffectKeys = {'attack'};
const _allEffectKeys = {..._selfEffectKeys, ..._enemyEffectKeys};

/// Builds a [ConsumableDefinition] from a loaded [ContentDefinition].
/// STRICT (SP3 §5.1.2 / §5.1.3): exactly one recognized `effect` variant
/// and a `target` consistent with it, or a [ContentFieldException]
/// (which `ConsumablePlugin.initialize` wraps as
/// [ContentValidationException]).
ConsumableDefinition consumableDefinitionFromContent(ContentDefinition definition) {
  final extra = definition.extra;

  final charges = _optionalNonNegativeInt(extra, 'charges', 1);
  final priority = (extra['priority'] as num?) ?? 0;

  final effectRaw = extra['effect'];
  if (effectRaw is! Map) {
    throw ContentFieldException('effect', 'required object field missing');
  }
  final effect = Map<String, dynamic>.of(
      effectRaw.map((k, v) => MapEntry(k as String, v)));

  final present = effect.keys.toSet();
  final recognized = present.intersection(_allEffectKeys);
  final unknown = present.difference(_allEffectKeys);
  if (recognized.isEmpty) {
    throw ContentFieldException(
        'effect', 'no recognized variant (one of ${_allEffectKeys.join('/')})');
  }
  if (recognized.length > 1) {
    throw ContentFieldException(
        'effect', 'more than one variant: ${recognized.join(', ')}');
  }
  if (unknown.isNotEmpty) {
    throw ContentFieldException('effect.${unknown.first}', 'unknown key');
  }
  final key = recognized.single;

  final ConsumableEffectSpec spec;
  final ConsumableTarget legalTarget;
  switch (key) {
    case 'heal':
      spec = ConsumableHeal(_nonNegativeNum(effect, 'heal'));
      legalTarget = ConsumableTarget.self;
    case 'attack':
      final a = ContentField.requireMap(effect, 'attack');
      spec = ConsumableAttack(
        _nonNegativeNum(a, 'damage'),
        ContentField.requireString(a, 'stat'),
      );
      legalTarget = ConsumableTarget.enemy;
    case 'grant':
      final g = ContentField.requireMap(effect, 'grant');
      final opName = ContentField.requireString(g, 'op');
      const knownOps = {'add', 'multiply', 'override', 'min', 'max'};
      if (!knownOps.contains(opName)) {
        throw ContentFieldException(
            'effect.grant.op', 'unknown modifier operation "$opName"');
      }
      final value = ContentField.requireNum(g, 'value');
      if (opName == 'add' && value < 0) {
        throw ContentFieldException(
            'effect.grant.value', 'must be >= 0 for op "add"');
      }
      spec = ConsumableGrantModifier(
        ContentField.requireString(g, 'stat'),
        modifierOperationFromString(opName),
        value,
      );
      legalTarget = ConsumableTarget.self;
    case 'removeAllStatuses':
      if (effect['removeAllStatuses'] != true) {
        throw ContentFieldException(
            'effect.removeAllStatuses', 'must be the literal true');
      }
      spec = const ConsumableRemoveAllStatuses();
      legalTarget = ConsumableTarget.self;
    default:
      throw StateError('unreachable: $key');
  }

  final targetRaw = extra['target'];
  final ConsumableTarget target;
  if (targetRaw == null) {
    target = legalTarget;
  } else {
    final parsed = switch (targetRaw) {
      'self' => ConsumableTarget.self,
      'enemy' => ConsumableTarget.enemy,
      _ => throw ContentFieldException('target', 'must be "self" or "enemy"'),
    };
    if (parsed != legalTarget) {
      throw ContentFieldException('target',
          'effect "$key" requires target ${legalTarget.name}, got ${parsed.name}');
    }
    target = parsed;
  }

  return ConsumableDefinition(
    id: definition.id,
    tags: definition.tags,
    charges: charges,
    priority: priority,
    target: target,
    effect: spec,
  );
}

num _nonNegativeNum(Map<String, dynamic> json, String key) {
  final v = ContentField.requireNum(json, key);
  if (v < 0) throw ContentFieldException(key, 'must be >= 0');
  return v;
}

int _optionalNonNegativeInt(Map<String, dynamic> json, String key, int fallback) {
  final v = json[key];
  if (v == null) return fallback;
  if (v is! int || v < 0) {
    throw ContentFieldException(key, 'must be a non-negative int');
  }
  return v;
}

/// Resolves + parses consumable [id] from [context]'s loaded content.
ConsumableDefinition consumableDefinition(String id, PluginContext context) =>
    consumableDefinitionFromContent(context.content.get(id));
