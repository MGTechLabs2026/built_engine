# Content Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the engine's Asset/Data Registry (`claude.md` core
service #12) — a `ContentRegistry` that loads/validates/looks-up
data-defined content (items, skills, styles, spells, trinkets, statuses)
and data-defined rules, via a flat keyed effect/condition/trigger factory
dispatch instead of a generic JSON interpreter.

**Architecture:** One generic `ContentDefinition` envelope (id, opaque
type label, tags, single optional resource cost, conditions, effects,
cross-references, passthrough extras) covers every non-rule content kind.
`RuleDefinition` covers data-defined `Rule`s via a separate trigger
registry (a JSON trigger name can't otherwise become a Dart `Type` +
subject-resolving closure). Both share one id space and one set of
effect/condition factories. `loadAll` is fully atomic — nothing commits
until every entry in the batch clears parsing, duplicate-id, and
`requires` checks.

**Tech Stack:** Dart `^3.7.0`, `package:test`, package `build_engine`.

**Spec:** `docs/superpowers/specs/2026-08-23-content-registry-design.md`

## Global Constraints

- Core must never contain content-domain vocabulary. `type` is an opaque
  string the registry stores/indexes but never branches on.
- This registry consumes already-decoded `Map<String, dynamic>`/
  `List<dynamic>` data — no file/asset I/O, no `dart:io`. That remains a
  separate future pass.
- Do not build a recursive/generic JSON-AST interpreter. Effects/
  conditions/triggers dispatch through flat keyed factory registries;
  each factory is a small, independently-testable function.
- IDs (content and rule) are globally unique across the whole registry.
- `loadAll` is fully atomic: nothing is registered unless every entry in
  the batch clears structural parsing, duplicate-id checking, and
  `requires` checking.
- `ContentRegistry` never auto-registers a loaded `RuleDefinition.rule`
  against a `RuleEngine` — that stays the caller's explicit choice, like
  every other wiring step in this codebase.
- No new top-level exported function names that could collide with a
  plugin's own vocabulary — the JSON field-extraction helpers are static
  methods on one `ContentField` class, not top-level functions.
- Every new/changed public class needs tests: loading, validation,
  lookup, dependency errors, duplicate IDs, serialization (the plan's
  six requested categories), plus an end-to-end integration test.

---

### Task 1: Content errors and field-extraction helpers

**Files:**
- Create: `lib/src/content/content_errors.dart`
- Create: `lib/src/content/json_helpers.dart`
- Test: `test/content/content_errors_test.dart`
- Test: `test/content/json_helpers_test.dart`

**Interfaces:**
- Produces:
  - `abstract class ContentSystemException implements Exception { final String message; String toString(); }`
  - `class ContentFieldException extends ContentSystemException { ContentFieldException(String path, String problem); final String path; final String problem; }`
  - `class ContentValidationException extends ContentSystemException { ContentValidationException(String definitionId, ContentFieldException cause); }`
  - `class ContentDuplicateIdException extends ContentSystemException { ContentDuplicateIdException(String id); }`
  - `class ContentDependencyException extends ContentSystemException { ContentDependencyException(String definitionId, String missingRequiredId); }`
  - `class ContentNotFoundException extends ContentSystemException { ContentNotFoundException(String id); }`
  - `class UnknownContentFactoryException extends ContentSystemException { UnknownContentFactoryException(String kind, String key); }`
  - `class ContentField` with static methods:
    - `static String requireString(Map<String, dynamic> json, String key)`
    - `static num requireNum(Map<String, dynamic> json, String key)`
    - `static Map<String, dynamic> requireMap(Map<String, dynamic> json, String key)`
    - `static List<Map<String, dynamic>> optionalMapList(Map<String, dynamic> json, String key)`
    - `static Set<String> optionalStringSet(Map<String, dynamic> json, String key)`

- [ ] **Step 1: Write `content_errors.dart`**

```dart
/// Base type for every exception thrown by the content registry
/// (`lib/src/content/`).
abstract class ContentSystemException implements Exception {
  const ContentSystemException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by a content factory (effect/condition) when a required
/// parameter is missing or has the wrong type. [path] names the field
/// (e.g. `'amount'`, or `'components.cost.resource'` once a caller has
/// prefixed it with where the field lives); [problem] describes what's
/// wrong. [ContentRegistry] catches this at the top level of a
/// definition and re-throws [ContentValidationException] naming which
/// definition it came from.
class ContentFieldException extends ContentSystemException {
  ContentFieldException(this.path, this.problem) : super('$path — $problem');

  final String path;
  final String problem;
}

/// Thrown by `load`/`loadAll`/`loadRule` when a definition's fields fail
/// validation — wraps the underlying [ContentFieldException] with which
/// definition it came from.
class ContentValidationException extends ContentSystemException {
  ContentValidationException(String definitionId, ContentFieldException cause)
      : super("Invalid content '$definitionId': $cause");
}

/// Thrown when a content or rule id is registered more than once. Ids
/// are globally unique across every content type and every rule.
class ContentDuplicateIdException extends ContentSystemException {
  ContentDuplicateIdException(String id)
      : super('Content id already registered: $id');
}

/// Thrown when a definition's `requires` names an id that isn't
/// registered — neither already in the registry, nor elsewhere in the
/// same `loadAll` batch.
class ContentDependencyException extends ContentSystemException {
  ContentDependencyException(String definitionId, String missingRequiredId)
      : super(
          "Content '$definitionId' requires unknown content "
          "'$missingRequiredId'",
        );
}

/// Thrown by [ContentRegistry.get]/[ContentRegistry.rule] when no
/// definition with the given id is registered.
class ContentNotFoundException extends ContentSystemException {
  ContentNotFoundException(String id)
      : super('No content registered with id: $id');
}

/// Thrown when an effect/condition/trigger JSON `"type"` key has no
/// registered factory. [kind] is `'effect'`, `'condition'`, or
/// `'trigger'`.
class UnknownContentFactoryException extends ContentSystemException {
  UnknownContentFactoryException(String kind, String key)
      : super('No $kind factory registered for type: $key');
}
```

- [ ] **Step 2: Write `content_errors_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('content exceptions', () {
    test('ContentFieldException composes path and problem', () {
      final exception =
          ContentFieldException('amount', 'required num field missing');
      expect(exception, isA<ContentSystemException>());
      expect(
        exception.toString(),
        equals('amount — required num field missing'),
      );
    });

    test(
        'ContentValidationException names the definition and wraps the '
        'field error', () {
      final field = ContentFieldException(
          'effects[0].amount', 'required num field missing');
      final exception = ContentValidationException('dragon_palm', field);
      expect(exception.toString(), contains('dragon_palm'));
      expect(exception.toString(), contains('effects[0].amount'));
    });

    test('ContentDuplicateIdException names the id', () {
      final exception = ContentDuplicateIdException('dragon_palm');
      expect(exception.toString(), contains('dragon_palm'));
    });

    test('ContentDependencyException names both the definition and the '
        'missing id', () {
      final exception =
          ContentDependencyException('dragon_palm', 'style:shaolin');
      expect(exception.toString(), contains('dragon_palm'));
      expect(exception.toString(), contains('style:shaolin'));
    });

    test('ContentNotFoundException names the id', () {
      final exception = ContentNotFoundException('nonexistent');
      expect(exception.toString(), contains('nonexistent'));
    });

    test('UnknownContentFactoryException names the kind and key', () {
      final exception =
          UnknownContentFactoryException('effect', 'summonDragon');
      expect(exception.toString(), contains('effect'));
      expect(exception.toString(), contains('summonDragon'));
    });
  });
}
```

- [ ] **Step 3: Write `json_helpers.dart`**

```dart
import 'content_errors.dart';

/// Typed field-extraction helpers shared by every content factory —
/// Core's built-in ones and any a plugin registers. Each throws
/// [ContentFieldException] on a missing or wrong-typed field rather than
/// letting a raw [TypeError]/`null` surface — this is what keeps every
/// individual factory a few lines long. Namespaced under one class
/// (rather than exported as top-level functions) so the package's
/// public surface doesn't gain generic top-level names like
/// `requireString`.
class ContentField {
  const ContentField._();

  static String requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw ContentFieldException(
          key, 'required non-empty String field missing');
    }
    return value;
  }

  static num requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num) {
      throw ContentFieldException(key, 'required num field missing');
    }
    return value;
  }

  static Map<String, dynamic> requireMap(
      Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! Map) {
      throw ContentFieldException(key, 'required object field missing');
    }
    return value.map((k, v) => MapEntry(k as String, v));
  }

  /// Reads an optional array of objects at [key]; `null`/absent yields
  /// an empty list. Every element must itself be a JSON object.
  static List<Map<String, dynamic>> optionalMapList(
      Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) {
      throw ContentFieldException(key, 'must be an array if present');
    }
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < value.length; i++) {
      final entry = value[i];
      if (entry is! Map) {
        throw ContentFieldException('$key[$i]', 'entry must be an object');
      }
      result.add(entry.map((k, v) => MapEntry(k as String, v)));
    }
    return result;
  }

  /// Reads an optional array of strings at [key]; `null`/absent yields
  /// an empty set.
  static Set<String> optionalStringSet(
      Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const <String>{};
    if (value is! List) {
      throw ContentFieldException(key, 'must be an array if present');
    }
    final result = <String>{};
    for (var i = 0; i < value.length; i++) {
      final entry = value[i];
      if (entry is! String) {
        throw ContentFieldException('$key[$i]', 'entry must be a string');
      }
      result.add(entry);
    }
    return result;
  }
}
```

- [ ] **Step 4: Write `json_helpers_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ContentField.requireString', () {
    test('returns the string when present and non-empty', () {
      expect(
          ContentField.requireString({'tag': 'fire'}, 'tag'), equals('fire'));
    });

    test('throws when missing', () {
      expect(() => ContentField.requireString({}, 'tag'),
          throwsA(isA<ContentFieldException>()));
    });

    test('throws when empty', () {
      expect(() => ContentField.requireString({'tag': ''}, 'tag'),
          throwsA(isA<ContentFieldException>()));
    });

    test('throws when wrong type', () {
      expect(() => ContentField.requireString({'tag': 5}, 'tag'),
          throwsA(isA<ContentFieldException>()));
    });
  });

  group('ContentField.requireNum', () {
    test('returns the num when present', () {
      expect(ContentField.requireNum({'amount': 15}, 'amount'), equals(15));
    });

    test('throws when missing or wrong type', () {
      expect(() => ContentField.requireNum({}, 'amount'),
          throwsA(isA<ContentFieldException>()));
      expect(() => ContentField.requireNum({'amount': 'x'}, 'amount'),
          throwsA(isA<ContentFieldException>()));
    });
  });

  group('ContentField.requireMap', () {
    test('returns a String-keyed copy when present', () {
      final result = ContentField.requireMap(
          {'cost': {'resource': 'qi'}}, 'cost');
      expect(result, equals({'resource': 'qi'}));
    });

    test('throws when missing or wrong type', () {
      expect(() => ContentField.requireMap({}, 'cost'),
          throwsA(isA<ContentFieldException>()));
      expect(() => ContentField.requireMap({'cost': 'x'}, 'cost'),
          throwsA(isA<ContentFieldException>()));
    });
  });

  group('ContentField.optionalMapList', () {
    test('returns an empty list when absent', () {
      expect(ContentField.optionalMapList({}, 'effects'), isEmpty);
    });

    test('returns the parsed list when present', () {
      final result = ContentField.optionalMapList({
        'effects': [
          {'type': 'damage', 'amount': 15},
        ],
      }, 'effects');
      expect(
          result,
          equals([
            {'type': 'damage', 'amount': 15},
          ]));
    });

    test('throws when an entry is not an object', () {
      expect(
        () => ContentField.optionalMapList({
          'effects': [1],
        }, 'effects'),
        throwsA(isA<ContentFieldException>()),
      );
    });

    test('throws when the field itself is not an array', () {
      expect(
        () => ContentField.optionalMapList({'effects': 'x'}, 'effects'),
        throwsA(isA<ContentFieldException>()),
      );
    });
  });

  group('ContentField.optionalStringSet', () {
    test('returns an empty set when absent', () {
      expect(ContentField.optionalStringSet({}, 'tags'), isEmpty);
    });

    test('returns the parsed set when present', () {
      expect(
        ContentField.optionalStringSet({
          'tags': ['fire', 'dragon'],
        }, 'tags'),
        equals({'fire', 'dragon'}),
      );
    });

    test('throws when an entry is not a string', () {
      expect(
        () => ContentField.optionalStringSet({
          'tags': [1],
        }, 'tags'),
        throwsA(isA<ContentFieldException>()),
      );
    });
  });
}
```

- [ ] **Step 5: Run the tests**

Run: `dart test test/content/content_errors_test.dart test/content/json_helpers_test.dart`
Expected: both files' tests PASS. (These import `package:build_engine/build_engine.dart`, which does not yet export the new files — a compile error is expected until Task 4 adds the exports. For this task, temporarily run against the files directly via relative-path test imports, OR add the two `export` lines from Task 4's Step 1 now and let Task 4 find them already present — **do the latter**: add
```dart
export 'src/content/content_errors.dart';
export 'src/content/json_helpers.dart';
```
to `lib/build_engine.dart` now, alphabetically positioned among the existing `export` lines, as part of this task. Task 4 will add the remaining two content exports once those files exist.)

- [ ] **Step 6: Commit**

```bash
git add lib/src/content/content_errors.dart lib/src/content/json_helpers.dart \
  test/content/content_errors_test.dart test/content/json_helpers_test.dart \
  lib/build_engine.dart
git commit -m "feat: add content registry error types and field-extraction helpers"
```

---

### Task 2: `ContentDefinition` and `RuleDefinition`

**Files:**
- Create: `lib/src/content/content_definition.dart`
- Test: `test/content/content_definition_test.dart`

**Interfaces:**
- Consumes: `Effect`, `Condition` (`lib/src/rule/effect.dart`,
  `lib/src/rule/condition.dart`), `Rule` (`lib/src/rule/rule.dart`) —
  all pre-existing, unchanged.
- Produces:
  - `class ContentDefinition { final String id; final String type; final Set<String> tags; final List<Effect> costEffects; final List<Condition> conditions; final List<Effect> effects; final Set<String> requires; final Map<String, dynamic> extra; final Map<String, dynamic> raw; }`
  - `class RuleDefinition { final String id; final Rule rule; final Map<String, dynamic> raw; }`

- [ ] **Step 1: Write `content_definition.dart`**

```dart
import '../rule/condition.dart';
import '../rule/effect.dart';
import '../rule/rule.dart';

/// A single piece of data-defined content — an item, skill, style,
/// spell, trinket, or status. [type] is an opaque label the registry
/// stores and indexes but never interprets. See the Content Registry
/// design spec (`docs/superpowers/specs/2026-08-23-content-registry-design.md`)
/// for the full field-by-field JSON shape this is parsed from.
class ContentDefinition {
  const ContentDefinition({
    required this.id,
    required this.type,
    required this.tags,
    required this.costEffects,
    required this.conditions,
    required this.effects,
    required this.requires,
    required this.extra,
    required this.raw,
  });

  final String id;
  final String type;
  final Set<String> tags;

  /// Zero or one entries, parsed from the JSON `components.cost` object
  /// (`{"resource": ..., "amount": ...}`) into a single
  /// `ModifyResource(resource, -amount)`. No content in this engine has
  /// ever needed more than one resource cost.
  final List<Effect> costEffects;

  final List<Condition> conditions;
  final List<Effect> effects;

  /// Other content/rule ids that must be registered for this definition
  /// to be valid. Checked by `ContentRegistry` at load time, not stored
  /// as a live reference.
  final Set<String> requires;

  /// Every top-level JSON field this class didn't otherwise interpret,
  /// verbatim — including any `components` entry besides `cost` (e.g.
  /// `claude.md`'s own `iron_sword` example's `components.attack`).
  final Map<String, dynamic> extra;

  /// The exact input map this definition was parsed from, for lossless
  /// re-export via `ContentRegistry.toJson()`.
  final Map<String, dynamic> raw;
}

/// A data-defined [Rule] — `trigger`/`subjectOf` resolved via a
/// registered trigger descriptor (see `ContentRegistry.registerTrigger`).
/// Shares its id space with [ContentDefinition] inside `ContentRegistry`.
class RuleDefinition {
  const RuleDefinition({
    required this.id,
    required this.rule,
    required this.raw,
  });

  final String id;
  final Rule rule;
  final Map<String, dynamic> raw;
}
```

- [ ] **Step 2: Write `content_definition_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ContentDefinition', () {
    test('holds every field as given', () {
      const definition = ContentDefinition(
        id: 'dragon_palm',
        type: 'skill',
        tags: {'fire', 'dragon'},
        costEffects: [],
        conditions: [],
        effects: [],
        requires: {'style:shaolin'},
        extra: {'flavorText': 'x'},
        raw: {'id': 'dragon_palm'},
      );

      expect(definition.id, equals('dragon_palm'));
      expect(definition.type, equals('skill'));
      expect(definition.tags, equals({'fire', 'dragon'}));
      expect(definition.requires, equals({'style:shaolin'}));
      expect(definition.extra['flavorText'], equals('x'));
      expect(definition.raw['id'], equals('dragon_palm'));
    });
  });

  group('RuleDefinition', () {
    test('holds id, rule, and raw', () {
      const rule = Rule(trigger: Object, effects: []);
      const definition =
          RuleDefinition(id: 'r1', rule: rule, raw: {'id': 'r1'});

      expect(definition.id, equals('r1'));
      expect(definition.rule, same(rule));
      expect(definition.raw['id'], equals('r1'));
    });
  });
}
```

- [ ] **Step 3: Run the test**

Also add, in this task, to `lib/build_engine.dart`:
```dart
export 'src/content/content_definition.dart';
```
(alphabetically positioned; `content_definition.dart` sorts before
`content_errors.dart`, so this export line moves above the one Task 1
added).

Run: `dart test test/content/content_definition_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/src/content/content_definition.dart \
  test/content/content_definition_test.dart lib/build_engine.dart
git commit -m "feat: add ContentDefinition and RuleDefinition data classes"
```

---

### Task 3: `ContentRegistry`

**Files:**
- Create: `lib/src/content/content_registry.dart`
- Test: `test/content/content_registry_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `ContentFieldException`, `ContentValidationException`,
    `ContentDuplicateIdException`, `ContentDependencyException`,
    `ContentNotFoundException`, `UnknownContentFactoryException`,
    `ContentField.*`.
  - Task 2: `ContentDefinition`, `RuleDefinition`.
  - Existing core: `Effect`/`Condition`/`Rule`
    (`lib/src/rule/{effect,condition,rule}.dart`), `Damage`, `Heal`,
    `ModifyStat`, `ModifyResource`, `ApplyStatus`, `RemoveStatus`,
    `AddTag`, `RemoveTag`, `CreateEntity`, `DestroyEntity`,
    `TransformEntity` (`lib/src/rule/effect.dart`), `HasTag`,
    `ResourceAbove`, `ResourceBelow`, `HealthBelow`, `StatusActive`,
    `RandomChance` (`lib/src/rule/condition.dart`), `EntityDamaged`,
    `EntityHealed`, `EntityKilled` (`lib/src/rule/effect_events.dart`),
    `EntityCreated`, `EntityDestroyed`
    (`lib/src/entity/entity_registry.dart`), `EntityId`
    (`lib/src/entity/entity_id.dart`).
- Produces:
  - `class ContentRegistry` with:
    - `ContentRegistry()` (pre-registers the built-in factories/triggers below)
    - `void registerEffectFactory(String key, Effect Function(Map<String, dynamic>) factory)`
    - `void registerConditionFactory(String key, Condition Function(Map<String, dynamic>) factory)`
    - `void registerTrigger(String key, Type eventType, EntityId? Function(Object) subjectOf)`
    - `ContentDefinition load(Map<String, dynamic> json)`
    - `List<ContentDefinition> loadAll(List<Map<String, dynamic>> jsonList)`
    - `RuleDefinition loadRule(Map<String, dynamic> json)`
    - `ContentDefinition get(String id)`
    - `ContentDefinition? find(String id)`
    - `RuleDefinition rule(String id)`
    - `List<ContentDefinition> allOfType(String type)`
    - `List<ContentDefinition> withTag(String tag)`
    - `List<Map<String, dynamic>> toJson()`
  - Built-in effect factory keys: `damage`, `heal`, `modifyStat`,
    `modifyResource`, `applyStatus`, `removeStatus`, `addTag`,
    `removeTag`, `createEntity`, `destroyEntity`, `transformEntity`.
  - Built-in condition factory keys: `hasTag`, `resourceAbove`,
    `resourceBelow`, `healthBelow`, `statusActive`, `randomChance`.
  - Built-in trigger keys: `EntityDamaged`, `EntityHealed`,
    `EntityKilled`, `EntityCreated`, `EntityDestroyed` (subject resolved
    from each event's `.id` field).

- [ ] **Step 1: Write `content_registry.dart`**

```dart
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../rule/condition.dart';
import '../rule/effect.dart';
import '../rule/effect_events.dart';
import '../rule/rule.dart';

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
    _registerBuiltInEffectFactories();
    _registerBuiltInConditionFactories();
    _registerBuiltInTriggers();
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

  void _registerBuiltInEffectFactories() {
    registerEffectFactory(
        'damage', (p) => Damage(ContentField.requireNum(p, 'amount')));
    registerEffectFactory(
        'heal', (p) => Heal(ContentField.requireNum(p, 'amount')));
    registerEffectFactory(
        'modifyStat',
        (p) => ModifyStat(ContentField.requireString(p, 'stat'),
            ContentField.requireNum(p, 'delta')));
    registerEffectFactory(
        'modifyResource',
        (p) => ModifyResource(ContentField.requireString(p, 'resource'),
            ContentField.requireNum(p, 'delta')));
    registerEffectFactory('applyStatus',
        (p) => ApplyStatus(ContentField.requireString(p, 'status')));
    registerEffectFactory('removeStatus',
        (p) => RemoveStatus(ContentField.requireString(p, 'status')));
    registerEffectFactory(
        'addTag', (p) => AddTag(ContentField.requireString(p, 'tag')));
    registerEffectFactory(
        'removeTag', (p) => RemoveTag(ContentField.requireString(p, 'tag')));
    registerEffectFactory('createEntity',
        (p) => CreateEntity(tags: ContentField.optionalStringSet(p, 'tags')));
    registerEffectFactory('destroyEntity', (p) => const DestroyEntity());
    registerEffectFactory('transformEntity',
        (p) => TransformEntity(ContentField.optionalStringSet(p, 'tags')));
  }

  void _registerBuiltInConditionFactories() {
    registerConditionFactory(
        'hasTag', (p) => HasTag(ContentField.requireString(p, 'tag')));
    registerConditionFactory(
        'resourceAbove',
        (p) => ResourceAbove(ContentField.requireString(p, 'resource'),
            ContentField.requireNum(p, 'threshold')));
    registerConditionFactory(
        'resourceBelow',
        (p) => ResourceBelow(ContentField.requireString(p, 'resource'),
            ContentField.requireNum(p, 'threshold')));
    registerConditionFactory('healthBelow',
        (p) => HealthBelow(ContentField.requireNum(p, 'threshold')));
    registerConditionFactory('statusActive',
        (p) => StatusActive(ContentField.requireString(p, 'status')));
    registerConditionFactory(
        'randomChance',
        (p) =>
            RandomChance(ContentField.requireNum(p, 'probability').toDouble()));
  }

  void _registerBuiltInTriggers() {
    registerTrigger('EntityDamaged', EntityDamaged, (e) => (e as EntityDamaged).id);
    registerTrigger('EntityHealed', EntityHealed, (e) => (e as EntityHealed).id);
    registerTrigger('EntityKilled', EntityKilled, (e) => (e as EntityKilled).id);
    registerTrigger('EntityCreated', EntityCreated, (e) => (e as EntityCreated).id);
    registerTrigger(
        'EntityDestroyed', EntityDestroyed, (e) => (e as EntityDestroyed).id);
  }
}
```

- [ ] **Step 2: Write `content_registry_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

Map<String, dynamic> _dragonPalm({
  String id = 'dragon_palm',
  List<Map<String, dynamic>> effects = const [
    {'type': 'damage', 'amount': 15},
  ],
  List<Map<String, dynamic>> conditions = const [],
  Set<String>? requires,
}) =>
    {
      'id': id,
      'type': 'skill',
      'tags': ['attack', 'fist', 'fire', 'dragon'],
      'components': {
        'cost': {'resource': 'qi', 'amount': 4},
      },
      if (conditions.isNotEmpty) 'conditions': conditions,
      'effects': effects,
      if (requires != null) 'requires': requires.toList(),
    };

void main() {
  group('load', () {
    test('parses a full envelope', () {
      final registry = ContentRegistry();
      final definition = registry.load(_dragonPalm());

      expect(definition.id, equals('dragon_palm'));
      expect(definition.type, equals('skill'));
      expect(definition.tags, equals({'attack', 'fist', 'fire', 'dragon'}));
      expect(definition.costEffects, hasLength(1));
      expect(definition.effects, hasLength(1));
      expect(definition.effects.single, isA<Damage>());
    });

    test('components.cost parses into a single ModifyResource cost effect',
        () {
      final registry = ContentRegistry();
      final definition = registry.load(_dragonPalm());
      final cost = definition.costEffects.single as ModifyResource;
      expect(cost.resource, equals('qi'));
      expect(cost.delta, equals(-4));
    });

    test('unrecognized top-level fields land in extra', () {
      final registry = ContentRegistry();
      final json = _dragonPalm();
      json['flavorText'] = 'A palm wreathed in flame.';
      final definition = registry.load(json);
      expect(definition.extra['flavorText'],
          equals('A palm wreathed in flame.'));
    });

    test('components sibling keys beside cost land in extra.components', () {
      final registry = ContentRegistry();
      final json = {
        'id': 'iron_sword',
        'type': 'item',
        'components': {
          'attack': {'damage': 12},
        },
      };
      final definition = registry.load(json);
      expect(definition.costEffects, isEmpty);
      expect(
        definition.extra['components'],
        equals({
          'attack': {'damage': 12},
        }),
      );
    });

    test('raw preserves the exact input map', () {
      final registry = ContentRegistry();
      final json = _dragonPalm();
      final definition = registry.load(json);
      expect(definition.raw, equals(json));
    });

    test(
        'createEntity/destroyEntity/transformEntity factories accept '
        'minimal params', () {
      final registry = ContentRegistry();
      final definition = registry.load(_dragonPalm(
        id: 'utility_test',
        effects: [
          {'type': 'createEntity'},
          {'type': 'destroyEntity'},
          {
            'type': 'transformEntity',
            'tags': ['x'],
          },
        ],
      ));
      expect(definition.effects, hasLength(3));
      expect(definition.effects[0], isA<CreateEntity>());
      expect(definition.effects[1], isA<DestroyEntity>());
      expect(definition.effects[2], isA<TransformEntity>());
    });
  });

  group('validation', () {
    test('missing id throws ContentFieldException', () {
      final registry = ContentRegistry();
      expect(() => registry.load({'type': 'skill'}),
          throwsA(isA<ContentFieldException>()));
    });

    test('missing type throws ContentValidationException naming the id', () {
      final registry = ContentRegistry();
      expect(
        () => registry.load({'id': 'dragon_palm'}),
        throwsA(
          isA<ContentValidationException>().having(
              (e) => e.toString(), 'message', contains('dragon_palm')),
        ),
      );
    });

    test('unknown effect type throws UnknownContentFactoryException', () {
      final registry = ContentRegistry();
      expect(
        () => registry.load(_dragonPalm(effects: [
          {'type': 'summonDragon', 'amount': 1},
        ])),
        throwsA(
          isA<UnknownContentFactoryException>().having(
              (e) => e.toString(), 'message', contains('summonDragon')),
        ),
      );
    });

    test('malformed components.cost missing resource throws with field path',
        () {
      final registry = ContentRegistry();
      final json = {
        'id': 'dragon_palm',
        'type': 'skill',
        'components': {
          'cost': {'amount': 4},
        },
      };
      expect(
        () => registry.load(json),
        throwsA(
          isA<ContentValidationException>().having(
              (e) => e.toString(),
              'message',
              contains('components.cost.resource')),
        ),
      );
    });

    test('effect factory validates its own params: damage requires amount',
        () {
      final registry = ContentRegistry();
      expect(
        () => registry.load(_dragonPalm(effects: [
          {'type': 'damage'},
        ])),
        throwsA(
          isA<ContentValidationException>().having((e) => e.toString(),
              'message', contains('effects[0].amount')),
        ),
      );
    });

    test('every built-in effect factory with a required param rejects its '
        'absence', () {
      final registry = ContentRegistry();
      final cases = <Map<String, dynamic>>[
        {'type': 'damage'},
        {'type': 'heal'},
        {'type': 'modifyStat', 'stat': 'punch'},
        {'type': 'modifyResource', 'resource': 'qi'},
        {'type': 'applyStatus'},
        {'type': 'removeStatus'},
        {'type': 'addTag'},
        {'type': 'removeTag'},
      ];
      for (final effect in cases) {
        expect(
          () => registry
              .load(_dragonPalm(id: 'x_${effect['type']}', effects: [effect])),
          throwsA(isA<ContentValidationException>()),
          reason: 'effect ${effect['type']} should validate its params',
        );
      }
    });

    test('every built-in condition factory with a required param rejects '
        'its absence', () {
      final registry = ContentRegistry();
      final cases = <Map<String, dynamic>>[
        {'type': 'hasTag'},
        {'type': 'resourceAbove', 'resource': 'qi'},
        {'type': 'resourceBelow', 'resource': 'qi'},
        {'type': 'healthBelow'},
        {'type': 'statusActive'},
        {'type': 'randomChance'},
      ];
      for (final condition in cases) {
        expect(
          () => registry.load(
              _dragonPalm(id: 'y_${condition['type']}', conditions: [condition])),
          throwsA(isA<ContentValidationException>()),
          reason: 'condition ${condition['type']} should validate its params',
        );
      }
    });
  });

  group('lookup', () {
    test('get/find/allOfType/withTag', () {
      final registry = ContentRegistry();
      registry.load(_dragonPalm());
      registry.load({
        'id': 'iron_sword',
        'type': 'item',
        'tags': ['weapon', 'sword'],
      });

      expect(registry.get('dragon_palm').type, equals('skill'));
      expect(registry.find('nonexistent'), isNull);
      expect(() => registry.get('nonexistent'),
          throwsA(isA<ContentNotFoundException>()));
      expect(registry.allOfType('item'), hasLength(1));
      expect(registry.allOfType('skill'), hasLength(1));
      expect(registry.withTag('dragon'), hasLength(1));
      expect(registry.withTag('weapon').single.id, equals('iron_sword'));
    });
  });

  group('dependency errors', () {
    test('requires referencing an unregistered id throws '
        'ContentDependencyException', () {
      final registry = ContentRegistry();
      expect(
        () => registry.load(_dragonPalm(requires: {'style:shaolin'})),
        throwsA(
          isA<ContentDependencyException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('dragon_palm'), contains('style:shaolin')),
          ),
        ),
      );
    });

    test('requires satisfied by an already-registered id succeeds', () {
      final registry = ContentRegistry();
      registry.load({'id': 'style:shaolin', 'type': 'style'});
      final definition =
          registry.load(_dragonPalm(requires: {'style:shaolin'}));
      expect(definition.requires, contains('style:shaolin'));
    });

    test('two definitions in the same loadAll batch may reference each '
        'other', () {
      final registry = ContentRegistry();
      final results = registry.loadAll([
        {
          'id': 'a',
          'type': 'skill',
          'requires': ['b'],
        },
        {
          'id': 'b',
          'type': 'skill',
          'requires': ['a'],
        },
      ]);
      expect(results, hasLength(2));
      expect(registry.get('a').requires, contains('b'));
      expect(registry.get('b').requires, contains('a'));
    });

    test('loadAll with an unresolvable requires registers nothing from the '
        'batch', () {
      final registry = ContentRegistry();
      expect(
        () => registry.loadAll([
          {'id': 'a', 'type': 'skill'},
          {
            'id': 'b',
            'type': 'skill',
            'requires': ['nonexistent'],
          },
        ]),
        throwsA(isA<ContentDependencyException>()),
      );
      expect(registry.find('a'), isNull);
      expect(registry.find('b'), isNull);
    });
  });

  group('duplicate ids', () {
    test('loading the same id twice throws ContentDuplicateIdException', () {
      final registry = ContentRegistry();
      registry.load(_dragonPalm());
      expect(() => registry.load(_dragonPalm()),
          throwsA(isA<ContentDuplicateIdException>()));
    });

    test('duplicate id within one loadAll batch throws and registers '
        'nothing', () {
      final registry = ContentRegistry();
      expect(
        () => registry.loadAll([
          {'id': 'a', 'type': 'skill'},
          {'id': 'a', 'type': 'skill'},
        ]),
        throwsA(isA<ContentDuplicateIdException>()),
      );
      expect(registry.find('a'), isNull);
    });

    test('a rule id colliding with a content id throws', () {
      final registry = ContentRegistry();
      registry.load({'id': 'shared_id', 'type': 'skill'});
      expect(
        () => registry.loadRule({
          'id': 'shared_id',
          'trigger': 'EntityDamaged',
          'effects': [
            {'type': 'heal', 'amount': 2},
          ],
        }),
        throwsA(isA<ContentDuplicateIdException>()),
      );
    });
  });

  group('rules', () {
    test('loadRule parses trigger/conditions/effects into a working Rule',
        () {
      final events = EventBus();
      final entities = EntityRegistry(events);
      final components = ComponentStore();
      final rules = RuleEngine(
        entities: entities,
        components: components,
        events: events,
        rng: RngService(1),
      );

      final registry = ContentRegistry();
      final definition = registry.loadRule({
        'id': 'shaolin_iron_body_heal',
        'trigger': 'EntityDamaged',
        'conditions': [
          {'type': 'hasTag', 'tag': 'stance:iron_body'},
        ],
        'effects': [
          {'type': 'heal', 'amount': 2},
        ],
      });

      rules.register(definition.rule);

      final subject = entities.create();
      components.add(subject, const HealthComponent(current: 50, max: 100));
      components.add(subject, const TagSet({'stance:iron_body'}));

      events.publish(EntityDamaged(subject, 10));

      expect(components.get<HealthComponent>(subject)!.current, equals(52));
    });

    test('unknown trigger key throws UnknownContentFactoryException', () {
      final registry = ContentRegistry();
      expect(
        () => registry.loadRule({
          'id': 'r1',
          'trigger': 'ActionCompleted',
          'effects': [
            {'type': 'heal', 'amount': 2},
          ],
        }),
        throwsA(isA<UnknownContentFactoryException>()),
      );
    });

    test('rule lookup via rule(id)', () {
      final registry = ContentRegistry();
      final definition = registry.loadRule({
        'id': 'r1',
        'trigger': 'EntityHealed',
        'effects': const [],
      });
      expect(registry.rule('r1'), same(definition));
      expect(
          () => registry.rule('nonexistent'), throwsA(isA<ContentNotFoundException>()));
    });
  });

  group('serialization', () {
    test('toJson round-trips through a fresh registry', () {
      final source = ContentRegistry();
      source.load(_dragonPalm());
      source.load({
        'id': 'style:shaolin',
        'type': 'style',
        'tags': ['martial'],
      });
      source.loadRule({
        'id': 'r1',
        'trigger': 'EntityDamaged',
        'effects': [
          {'type': 'heal', 'amount': 2},
        ],
      });

      final dumped = source.toJson();

      final rebuilt = ContentRegistry();
      final contentJson =
          dumped.where((j) => !j.containsKey('trigger')).toList();
      final ruleJson = dumped.where((j) => j.containsKey('trigger')).toList();
      rebuilt.loadAll(contentJson);
      for (final ruleEntry in ruleJson) {
        rebuilt.loadRule(ruleEntry);
      }

      expect(rebuilt.get('dragon_palm').type,
          equals(source.get('dragon_palm').type));
      expect(
          rebuilt.get('dragon_palm').tags, equals(source.get('dragon_palm').tags));
      expect(rebuilt.allOfType('style'), hasLength(1));
      expect(rebuilt.rule('r1').rule.trigger, equals(EntityDamaged));
    });
  });
}
```

- [ ] **Step 3: Wire the export and run**

Add, in this task, to `lib/build_engine.dart`:
```dart
export 'src/content/content_registry.dart';
```
(alphabetically positioned).

Run: `dart test test/content/content_registry_test.dart`
Expected: every group PASSES.

- [ ] **Step 4: Commit**

```bash
git add lib/src/content/content_registry.dart \
  test/content/content_registry_test.dart lib/build_engine.dart
git commit -m "feat: implement ContentRegistry — load/loadAll/loadRule, lookup, serialization"
```

---

### Task 4: Wire `ContentRegistry` into `PluginContext`

**Files:**
- Modify: `lib/src/plugin/plugin_context.dart`
- Modify: `test/plugin_context_test.dart`
- Modify (mechanical, identical one-line insertion in each): `test/plugin_manager_test.dart`, `test/plugins/combat/combat_plugin_test.dart`, `test/plugins/martial_arts/martial_technique_action_test.dart`, `test/plugins/martial_arts/martial_arts_plugin_test.dart`, `test/plugins/combat/combat_action_test.dart`, `test/integration/martial_arts_end_to_end_test.dart`, `test/plugins/combat/combat_system_test.dart`, `test/plugins/martial_arts/martial_item_test.dart`, `test/plugins/martial_arts/martial_styles_test.dart`, `test/integration/core_boots_without_plugins_test.dart`, `test/plugins/martial_arts/martial_arts_rules_test.dart`, `test/integration/combat_plugin_end_to_end_test.dart`

**Interfaces:**
- Consumes: `ContentRegistry` (Task 3, already exported from
  `package:build_engine/build_engine.dart`).
- Produces: `PluginContext.content` — every plugin's lifecycle methods
  can now reach `context.content`.

- [ ] **Step 1: Add the field to `PluginContext`**

In `lib/src/plugin/plugin_context.dart`, add an import and the new
field:

```dart
import '../component/component_store.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../modifier/modifier_collection.dart';
import '../query/query_engine.dart';
import '../rng/rng_service.dart';
import '../rule/rule_engine.dart';
import '../content/content_registry.dart';

/// The controlled access every plugin lifecycle method receives. Exposes
/// every core service that exists so far.
class PluginContext {
  const PluginContext({
    required this.entities,
    required this.components,
    required this.events,
    required this.rng,
    required this.rules,
    required this.queries,
    required this.modifiers,
    required this.content,
  });

  final EntityRegistry entities;
  final ComponentStore components;
  final EventBus events;
  final RngService rng;
  final RuleEngine rules;
  final QueryEngine queries;
  final ModifierCollection modifiers;
  final ContentRegistry content;
}
```

- [ ] **Step 2: Update every `PluginContext(...)` call site**

In each of the 13 files listed above under **Files**, find the
`PluginContext(` construction block. Every one of them ends with a line
reading either `modifiers: modifiers,` (only in
`test/plugin_context_test.dart`, which builds a local `modifiers`
variable earlier in the same test) or `modifiers: ModifierCollection(),`
(every other file, constructing it inline). Insert one new line
immediately after that line, before the closing `);`:

```dart
    content: ContentRegistry(),
```

For example, in `test/plugin_manager_test.dart` (and the same pattern in
the other 11 inline-construction files), the block changes from:

```dart
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
```

to:

```dart
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
```

And in `test/plugin_context_test.dart`, the block changes from:

```dart
    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: rules,
      queries: queries,
      modifiers: modifiers,
    );
```

to:

```dart
    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: rules,
      queries: queries,
      modifiers: modifiers,
      content: content,
    );
```

— which additionally needs a `content` variable declared alongside that
file's existing `entities`/`components`/.../`modifiers` local variables
(find where those are declared near the top of the test, e.g. `final
modifiers = ModifierCollection();`, and add `final content =
ContentRegistry();` next to it).

- [ ] **Step 3: Extend `plugin_context_test.dart`'s assertion**

In the same test that builds `context` (Step 2's
`test/plugin_context_test.dart` edit), find the existing assertions
(`expect(context.entities, same(entities));`,
`expect(context.components, same(components));`,
`expect(context.events, same(events));`, and similar for the other
fields) and add one more matching line:

```dart
    expect(context.content, same(content));
```

- [ ] **Step 4: Run the full suite**

Run: `dart test`
Expected: every test in the package PASSES — this is a purely additive,
mechanical change (one new required constructor field, satisfied
identically everywhere), so zero regressions are expected. If any file
was missed, the compiler error names it directly (`missing required
argument content`).

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugin/plugin_context.dart test/plugin_context_test.dart \
  test/plugin_manager_test.dart test/plugins/combat/combat_plugin_test.dart \
  test/plugins/martial_arts/martial_technique_action_test.dart \
  test/plugins/martial_arts/martial_arts_plugin_test.dart \
  test/plugins/combat/combat_action_test.dart \
  test/integration/martial_arts_end_to_end_test.dart \
  test/plugins/combat/combat_system_test.dart \
  test/plugins/martial_arts/martial_item_test.dart \
  test/plugins/martial_arts/martial_styles_test.dart \
  test/integration/core_boots_without_plugins_test.dart \
  test/plugins/martial_arts/martial_arts_rules_test.dart \
  test/integration/combat_plugin_end_to_end_test.dart
git commit -m "feat: expose ContentRegistry on PluginContext"
```

---

### Task 5: Integration test and architecture docs

**Files:**
- Create: `test/integration/content_registry_end_to_end_test.dart`
- Modify: `ARCHITECTURE.md`

**Interfaces:**
- Consumes: `ContentRegistry`, `ContentDefinition` (Tasks 2-3),
  `PluginContext.content` (Task 4), and the existing core triple
  `EntityRegistry`/`ComponentStore`/`EventBus`/`RuleEngine`/
  `RuleContext`/`EventCounter`/`RngService`.

- [ ] **Step 1: Write the integration test**

This proves the full loop `claude.md`'s own `dragon_palm` example
implies: load a skill definition from a JSON-shaped `Map`, resolve its
`costEffects`/`conditions`/`effects` against real engine state — no
plugin involved, only what `PluginContext` already carries — through a
manually-built `RuleContext`, the same public type `RuleEngine` and
`CombatSystem.executeAction` already use for exactly this purpose (see
`ARCHITECTURE.md`'s Combat section).

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('a data-loaded skill definition resolves through the real engine '
      'exactly like a hand-written Condition/Effect would', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final registry = ContentRegistry();

    final definition = registry.load({
      'id': 'dragon_palm',
      'type': 'skill',
      'tags': ['attack', 'fist', 'fire', 'dragon'],
      'components': {
        'cost': {'resource': 'qi', 'amount': 4},
      },
      'conditions': [
        {'type': 'resourceAbove', 'resource': 'qi', 'threshold': 3},
      ],
      'effects': [
        {'type': 'damage', 'amount': 15},
      ],
    });

    final actor = entities.create();
    final target = entities.create();
    components.add(actor, const ResourceComponent({'qi': 10}));
    components.add(target, const HealthComponent(current: 100, max: 100));

    RuleContext contextFor(EntityId subject) => RuleContext(
          subject: subject,
          triggerEvent: const Object(),
          entities: entities,
          components: components,
          events: events,
          rng: rng,
          eventCounts: EventCounter(events),
        );

    // Conditions are evaluated against the actor (do they qualify to use
    // this skill?); cost and effects run against the same actor/target
    // split `AttackAction`/`MartialTechniqueAction` already use.
    final qualifies =
        definition.conditions.every((c) => c.evaluate(contextFor(actor)));
    expect(qualifies, isTrue);

    for (final cost in definition.costEffects) {
      cost.apply(contextFor(actor));
    }
    expect(components.get<ResourceComponent>(actor)!.resources['qi'],
        equals(6));

    for (final effect in definition.effects) {
      effect.apply(contextFor(target));
    }
    expect(
        components.get<HealthComponent>(target)!.current, equals(85));

    // Below the threshold now demonstrates the loaded Condition rejects
    // exactly like the equivalent hand-written `ResourceAbove('qi', 3)`
    // would.
    components.add(actor, const ResourceComponent({'qi': 2}));
    final stillQualifies =
        definition.conditions.every((c) => c.evaluate(contextFor(actor)));
    expect(stillQualifies, isFalse);
  });
}
```

- [ ] **Step 2: Run it**

Run: `dart test test/integration/content_registry_end_to_end_test.dart`
Expected: PASS.

- [ ] **Step 3: Run the whole suite one more time**

Run: `dart test`
Expected: every test in the package PASSES.

- [ ] **Step 4: Update `ARCHITECTURE.md`**

Append a new section after the existing "MartialArts — the first
content plugin" section (end of the file), following that section's
established style (see the Combat and MartialArts sections already
there for the tone/level of detail to match):

```markdown
## Content Registry — the engine's Asset/Data Registry (`lib/src/content/`)

`ContentRegistry` is core service #12 from `claude.md`: the mechanism
that lets content (items, skills, styles, spells, trinkets, statuses)
and rules be defined as data instead of a new Dart class per piece of
content. It is Core, not a plugin — `type` fields on loaded content are
opaque strings the registry stores and indexes but never branches on.

One `ContentDefinition` envelope (id, type, tags, an optional single
resource cost, conditions, effects, cross-references via `requires`, and
a passthrough `extra` map for anything else) covers items/skills/
styles/spells/trinkets/statuses uniformly — they're structurally
identical from the engine's point of view, matching
`MartialItemDefinition`'s and `MartialTechniqueAction`'s existing "one
class covers many content items via data" precedent. `components.cost`
parses into exactly one `ModifyResource(resource, -amount)` — a direct
data-driven mirror of `CombatAction.costEffects` and of every
hand-written technique in `martial_technique_action.dart` (each has
exactly one resource cost).

Turning `{"type": "damage", "amount": 15}` into a real `Damage(15)` goes
through a flat keyed factory dispatch, not a recursive JSON-AST
interpreter — `claude.md` explicitly warns against the latter. The
registry's constructor pre-registers factories for Core's own existing
generic `Effect`/`Condition` classes only; a plugin registers more for
its own via the same `registerEffectFactory`/`registerConditionFactory`
methods it would use for anything else optional in this engine.
`HasComponent<T>`/`EventCount` are deliberately not among the built-ins
— both need a compile-time type argument a JSON string key can't supply
without a second name-to-`Type` registry, and no concrete content has
ever needed either from data, so adding it now would be exactly the
speculative abstraction `claude.md`'s IMPLEMENTATION STYLE section
forbids.

`RuleDefinition` covers data-defined `Rule`s through one more registry —
`registerTrigger` — because a `Rule`'s `trigger`/`subjectOf` are a `Type`
and a closure, neither directly JSON-expressible. Core pre-registers
triggers only for its own events (`EntityDamaged`, `EntityHealed`,
`EntityKilled`, `EntityCreated`, `EntityDestroyed`); `ContentRegistry`
never calls `RuleEngine.register` itself — turning a loaded
`RuleDefinition` into a live rule stays the caller's explicit choice,
the same "nothing wires itself up automatically" convention documented
above for `EntityDestroyed` component cleanup.

`loadAll` is fully atomic: every entry is parsed, then every id is
checked for duplicates, then every `requires` is checked against the
union of the registry and the whole batch, and only then does anything
get registered — so two definitions in one batch can reference each
other in either order, and a bad entry anywhere in a batch leaves the
registry exactly as it was before the call.

`ContentRegistry.toJson()`/`loadAll`/`loadRule` round-trip losslessly at
the data level — like `Container.toJson()`/`fromJson()` before it, this
is a self-contained capability of this module only, not the engine-wide
Serialization service `claude.md` describes (still a separate future
pass), and it re-exports each definition's original decoded JSON rather
than attempting to re-serialize live `Effect`/`Condition` objects.

This pass also grew `PluginContext` with a `content` field (alongside
the existing seven services) — every plugin can now register its own
factories/triggers and load/query content from any lifecycle method.
```

- [ ] **Step 5: Commit**

```bash
git add test/integration/content_registry_end_to_end_test.dart ARCHITECTURE.md
git commit -m "test: add content registry end-to-end integration test; document in ARCHITECTURE.md"
```
