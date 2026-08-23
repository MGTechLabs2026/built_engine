import '../entity/entity_id.dart';
import '../rule/condition.dart';
import '../rule/effect.dart';
import '../rule/rule.dart';

import 'built_in_content_factories.dart';
import 'content_definition.dart';
import 'content_errors.dart';
import 'json_helpers.dart';

typedef EffectFactory = Effect Function(Map<String, dynamic> params);
typedef ConditionFactory = Condition Function(Map<String, dynamic> params);
typedef SubjectResolver = EntityId? Function(Object event);

class _TriggerDescriptor {
  const _TriggerDescriptor(this.eventType, this.subjectOf);
  final Type eventType;
  final SubjectResolver subjectOf;
}

/// The engine's Asset/Data Registry (`claude.md` core service #12):
/// loads, validates, and looks up data-defined content and rules. See
/// `docs/superpowers/specs/2026-08-23-content-registry-design.md` for
/// the full design.
class ContentRegistry {
  ContentRegistry() {
    registerBuiltInContentFactories(this);
  }

  final Map<String, EffectFactory> _effectFactories = {};
  final Map<String, ConditionFactory> _conditionFactories = {};
  final Map<String, _TriggerDescriptor> _triggers = {};

  final Map<String, ContentDefinition> _content = {};
  final Map<String, RuleDefinition> _rules = {};

  // --- factory registration ---

  /// Registers an [Effect] factory under [key], for JSON entries shaped
  /// `{"type": key, ...params}`. Core's own generic effects are already
  /// registered by the constructor; plugins call this for their own.
  void registerEffectFactory(String key, EffectFactory factory) {
    _effectFactories[key] = factory;
  }

  /// Registers a [Condition] factory under [key]. See
  /// [registerEffectFactory].
  void registerConditionFactory(String key, ConditionFactory factory) {
    _conditionFactories[key] = factory;
  }

  /// Registers a rule trigger under [key]: the [Type] a `RuleDefinition`
  /// naming [key] as its `trigger` resolves to, and how to resolve the
  /// rule's subject from a published event of that type. Core's own
  /// events are already registered by the constructor; plugins call this
  /// for their own event types.
  void registerTrigger(String key, Type eventType, SubjectResolver subjectOf) {
    _triggers[key] = _TriggerDescriptor(eventType, subjectOf);
  }

  // --- loading ---

  /// Parses, validates, and registers one content definition. `requires`
  /// is checked against everything already registered. Throws
  /// [ContentValidationException]/[UnknownContentFactoryException] on a
  /// structural problem, or [ContentDuplicateIdException]/
  /// [ContentDependencyException] — nothing is registered if any check
  /// fails.
  ContentDefinition load(Map<String, dynamic> json) {
    final definition = _parse(json);
    _checkDuplicate(definition.id);
    _checkRequires(definition, additionalKnownIds: const {});
    _content[definition.id] = definition;
    return definition;
  }

  /// Loads every entry in [jsonList] as one atomic batch: every entry is
  /// parsed, then every id is checked for duplicates (against the
  /// registry and the rest of the batch), then every entry's `requires`
  /// is checked against the union of the registry and the batch — so
  /// two entries in the same batch may reference each other in either
  /// order. Nothing is registered unless every entry clears every check.
  List<ContentDefinition> loadAll(List<Map<String, dynamic>> jsonList) {
    final parsed = jsonList.map(_parse).toList();

    final idsInBatch = <String>{};
    for (final definition in parsed) {
      if (!idsInBatch.add(definition.id) || _idExists(definition.id)) {
        throw ContentDuplicateIdException(definition.id);
      }
    }

    for (final definition in parsed) {
      _checkRequires(definition, additionalKnownIds: idsInBatch);
    }

    for (final definition in parsed) {
      _content[definition.id] = definition;
    }
    return parsed;
  }

  /// Parses, validates, and registers one rule definition. [json] must
  /// have `id` and `trigger` (a key registered via [registerTrigger])
  /// plus optional `conditions`/`effects`, in the same shape a content
  /// definition's `conditions`/`effects` use. Shares its id space with
  /// content definitions.
  RuleDefinition loadRule(Map<String, dynamic> json) {
    final id = ContentField.requireString(json, 'id');
    _checkDuplicate(id);
    final triggerKey = ContentField.requireString(json, 'trigger');
    final descriptor = _triggers[triggerKey];
    if (descriptor == null) {
      throw UnknownContentFactoryException('trigger', triggerKey);
    }

    final List<Condition> conditions;
    final List<Effect> effects;
    try {
      conditions = _parseConditions(json);
      effects = _parseEffects(json);
    } on ContentFieldException catch (e) {
      throw ContentValidationException(id, e);
    }

    final rule = Rule(
      trigger: descriptor.eventType,
      subjectOf: descriptor.subjectOf,
      conditions: conditions,
      effects: effects,
    );
    final definition =
        RuleDefinition(id: id, rule: rule, raw: Map<String, dynamic>.of(json));
    _rules[id] = definition;
    return definition;
  }

  // --- lookup ---

  ContentDefinition get(String id) =>
      _content[id] ?? (throw ContentNotFoundException(id));

  ContentDefinition? find(String id) => _content[id];

  RuleDefinition rule(String id) =>
      _rules[id] ?? (throw ContentNotFoundException(id));

  List<ContentDefinition> allOfType(String type) =>
      _content.values.where((d) => d.type == type).toList();

  List<ContentDefinition> withTag(String tag) =>
      _content.values.where((d) => d.tags.contains(tag)).toList();

  // --- serialization ---

  /// Every loaded definition's original `raw` map — content definitions
  /// first (in load order), then rule definitions (in load order).
  /// Feeding this back through [loadAll]/[loadRule] on a fresh
  /// [ContentRegistry] reproduces an equivalent registry. Live
  /// [Effect]/[Condition] objects are never re-serialized — only the
  /// original decoded JSON, which stays lossless because `raw` is never
  /// mutated after parsing.
  List<Map<String, dynamic>> toJson() => [
        for (final definition in _content.values) definition.raw,
        for (final definition in _rules.values) definition.raw,
      ];

  // --- internals ---

  bool _idExists(String id) =>
      _content.containsKey(id) || _rules.containsKey(id);

  void _checkDuplicate(String id) {
    if (_idExists(id)) {
      throw ContentDuplicateIdException(id);
    }
  }

  void _checkRequires(
    ContentDefinition definition, {
    required Set<String> additionalKnownIds,
  }) {
    for (final requiredId in definition.requires) {
      if (!_idExists(requiredId) && !additionalKnownIds.contains(requiredId)) {
        throw ContentDependencyException(definition.id, requiredId);
      }
    }
  }

  ContentDefinition _parse(Map<String, dynamic> json) {
    final id = ContentField.requireString(json, 'id');
    try {
      final type = ContentField.requireString(json, 'type');
      final tags = ContentField.optionalStringSet(json, 'tags');
      final requires = ContentField.optionalStringSet(json, 'requires');

      var costEffects = const <Effect>[];
      var remainingComponents = const <String, dynamic>{};
      final componentsValue = json['components'];
      if (componentsValue != null) {
        final componentsMap = ContentField.requireMap(json, 'components');
        final costValue = componentsMap['cost'];
        if (costValue != null) {
          if (costValue is! Map) {
            throw ContentFieldException(
                'components.cost', 'required object field missing');
          }
          final costMap =
              costValue.map((k, v) => MapEntry(k as String, v));
          final String resource;
          final num amount;
          try {
            resource = ContentField.requireString(costMap, 'resource');
            amount = ContentField.requireNum(costMap, 'amount');
          } on ContentFieldException catch (e) {
            throw ContentFieldException(
                'components.cost.${e.path}', e.problem);
          }
          costEffects = [ModifyResource(resource, -amount)];
        }
        remainingComponents = Map<String, dynamic>.of(componentsMap)
          ..remove('cost');
      }

      final conditions = _parseConditions(json);
      final effects = _parseEffects(json);

      final extra = Map<String, dynamic>.of(json)
        ..remove('id')
        ..remove('type')
        ..remove('tags')
        ..remove('requires')
        ..remove('components')
        ..remove('conditions')
        ..remove('effects');
      if (remainingComponents.isNotEmpty) {
        extra['components'] = remainingComponents;
      }

      return ContentDefinition(
        id: id,
        type: type,
        tags: tags,
        costEffects: costEffects,
        conditions: conditions,
        effects: effects,
        requires: requires,
        extra: extra,
        raw: Map<String, dynamic>.of(json),
      );
    } on ContentFieldException catch (e) {
      throw ContentValidationException(id, e);
    }
  }

  List<Condition> _parseConditions(Map<String, dynamic> json) {
    final entries = ContentField.optionalMapList(json, 'conditions');
    final conditions = <Condition>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      try {
        final key = ContentField.requireString(entry, 'type');
        final factory = _conditionFactories[key];
        if (factory == null) {
          throw UnknownContentFactoryException('condition', key);
        }
        conditions.add(factory(entry));
      } on ContentFieldException catch (e) {
        throw ContentFieldException('conditions[$i].${e.path}', e.problem);
      }
    }
    return conditions;
  }

  List<Effect> _parseEffects(Map<String, dynamic> json) {
    final entries = ContentField.optionalMapList(json, 'effects');
    final effects = <Effect>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      try {
        final key = ContentField.requireString(entry, 'type');
        final factory = _effectFactories[key];
        if (factory == null) {
          throw UnknownContentFactoryException('effect', key);
        }
        effects.add(factory(entry));
      } on ContentFieldException catch (e) {
        throw ContentFieldException('effects[$i].${e.path}', e.problem);
      }
    }
    return effects;
  }
}
