# Technique Learning System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a generic Technique plugin implementing the
UNKNOWN → DISCOVERED → LEARNING → LEARNED → EVOLVED lifecycle, keeping
Discovery/Learning/Mastery as three genuinely independent axes, and reusing
the existing Evolution system (already TrainingProfile-weighted) unchanged.

**Architecture:** New plugin at `lib/src/plugins/technique/` + barrel
`lib/technique_plugin.dart`, depending on nothing but Core (mirrors
`ElementalPlugin`/`ItemPlugin`). Key finding from inspection: **no new Core
primitive is needed for "Learned."** `ProgressionEngine` already exists
specifically for this — its own doc comment names "technique learning,
technique tier" as an intended use case, and its `unlock(id, subject, tier)`
method is already documented as covering "learning a subject outright." The
three axes map onto three independent subject keys, so no storage collides
even though two of them share an underlying tracker type:

| Axis | Service | Subject | Storage |
|---|---|---|---|
| Discovery | `DiscoveryTracker` | `technique:<id>` | `DiscoveryComponent` |
| Learning | `ProgressionEngine` | `technique:<id>:knowledge` | `MasteryComponent` (via `MasteryTracker`) |
| Mastery | `MasteryTracker` | `technique:<id>` | `MasteryComponent` (via `MasteryTracker`) |

Learning and Mastery both ultimately store in `MasteryComponent`, but under
different subject strings, so they never collide — the same technique used
to keep Item's Discovery and Mastery independent under the identical
subject string but different component *types*; here two axes share a
component type but differ by subject string instead. Evolution needs **zero
new engine code** — `EvolutionResolver`'s existing tag-weighted-by-
`TrainingProfile` mechanism is already exactly what the milestone asks for;
this plan only adds *content* (technique `EvolutionDefinition`s) that uses
it. Tome eligibility is enforced at a plugin-level `addTechniqueToTome` call
boundary, mirroring `ItemPlugin.addItemToTome` — `TomeService`/`Container`/
`PlacementRule` stay untouched, same reasoning as the Item milestone
(`PlacementRule.isSatisfied` has no owner parameter to check owner-scoped
state against).

**Tech Stack:** Dart 3.7, `package:test`, existing `build_engine` Core
services only.

**Spec:** The milestone brief in the current conversation.

## Global Constraints

- Core must not gain any technique-specific vocabulary.
- Do not create `MartialTechniqueLearningSystem` — reuse
  `ProgressionEngine`/`DiscoveryTracker`/`MasteryTracker`/`EvolutionResolver`
  as-is.
- Discovery, Learning, and Mastery must be independently queryable — no
  single boolean collapses them.
- Do not modify `TomeService`, `Container`, or `PlacementRule`.
- Do not auto-evolve a technique on learning — evolution stays an explicit,
  separate operation.
- Do not implement UI, animations, real training minigames, combat action
  interpretation, new combat mechanics, magic, or cultivation.
- `dart analyze` must stay clean and no existing test may regress.
- Do not commit.

---

## File Structure

```
lib/src/plugins/technique/
  technique_definition.dart   - TechniqueDefinition
  technique_vocabulary.dart   - TechniqueIds, techniqueSubject(), techniqueKnowledgeSubject(), techniqueReferenceType
  technique_content.dart      - 3 base + 8 evolved techniques as data + parsing
  technique_events.dart       - TechniqueAddedToTome
  technique_lifecycle.dart    - discover/learn/mastery/tome-gate functions + exceptions
  technique_evolution.dart    - toEvolutionDefinition/evolveTechnique wrapper
  technique_plugin.dart       - TechniquePlugin (GamePlugin)
lib/technique_plugin.dart     - public barrel

test/plugins/technique/
  technique_definition_test.dart
  technique_content_test.dart
  technique_lifecycle_test.dart
  technique_evolution_test.dart
  technique_plugin_test.dart

test/integration/
  technique_end_to_end_test.dart          - full lifecycle + Tome + determinism
  learning_progression_reuse_test.dart    - unrelated content reuses Learning/Evolution primitives with zero Technique import

test/integration/architecture_dependency_test.dart  - MODIFIED (add Technique barrel + groups)
```

---

### Task 1: `TechniqueDefinition`

**Files:**
- Create: `lib/src/plugins/technique/technique_definition.dart`
- Test: `test/plugins/technique/technique_definition_test.dart`

**Interfaces:**
- Produces: `TechniqueDefinition({required String id, required String name, required String tier, required Set<String> tags, required Map<String, num> properties, List<Condition> requirements = const [], List<EvolutionCandidate> evolutionCandidates = const [], List<Modifier> Function(EntityId owner) modifiersFor})`
- Produces: `EvolutionDefinition toEvolutionDefinition()` instance method.

- [ ] **Step 1: Write `technique_definition.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// A learnable movement/ability's immutable, content-derived shape —
/// the third occurrence of the `MartialItemDefinition`/`ItemDefinition`
/// pattern. [tier] is a plain string from the existing `EvolutionTiers`
/// vocabulary (`basic`/`intermediate`/`advanced`/`master`) — no new tier
/// enum. [requirements] reuses `ContentDefinition.conditions` verbatim
/// (gates the LEARNING operation, not Tome placement — that's gated by
/// `isTechniqueLearned` instead). [evolutionCandidates] plus [tier]/[id]
/// are exactly what `EvolutionDefinition` needs — [toEvolutionDefinition]
/// builds one on demand rather than storing a redundant nested object.
/// [properties]/[modifiersFor] mirror `ItemDefinition`'s exact shape:
/// descriptive only, never auto-applied this pass (no combat action
/// interpretation yet).
class TechniqueDefinition {
  const TechniqueDefinition({
    required this.id,
    required this.name,
    required this.tier,
    required this.tags,
    required this.properties,
    this.requirements = const [],
    this.evolutionCandidates = const [],
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final String name;
  final String tier;
  final Set<String> tags;
  final Map<String, num> properties;
  final List<Condition> requirements;
  final List<EvolutionCandidate> evolutionCandidates;
  final List<Modifier> Function(EntityId owner) modifiersFor;

  static List<Modifier> _noModifiers(EntityId owner) => const [];

  /// Builds the `EvolutionDefinition` this technique represents, for
  /// `EvolutionResolver.resolve` to consume — see `technique_evolution.dart`.
  EvolutionDefinition toEvolutionDefinition() =>
      EvolutionDefinition(id: id, tier: tier, candidates: evolutionCandidates);
}
```

- [ ] **Step 2: Write the failing test** — `test/plugins/technique/technique_definition_test.dart`

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_definition.dart';
import 'package:test/test.dart';

void main() {
  test('TechniqueDefinition carries id/name/tier/tags/properties', () {
    const definition = TechniqueDefinition(
      id: 'basic_punch',
      name: 'Basic Punch',
      tier: EvolutionTiers.basic,
      tags: {'technique', 'fist'},
      properties: {'damage': 6},
    );

    expect(definition.id, equals('basic_punch'));
    expect(definition.name, equals('Basic Punch'));
    expect(definition.tier, equals(EvolutionTiers.basic));
    expect(definition.properties['damage'], equals(6));
  });

  test('toEvolutionDefinition builds a matching EvolutionDefinition', () {
    const definition = TechniqueDefinition(
      id: 'basic_punch',
      name: 'Basic Punch',
      tier: EvolutionTiers.basic,
      tags: {'technique'},
      properties: {},
      evolutionCandidates: [
        EvolutionCandidate(targetId: 'light_punch', tags: {'precision'}),
      ],
    );

    final evolution = definition.toEvolutionDefinition();

    expect(evolution.id, equals('basic_punch'));
    expect(evolution.tier, equals(EvolutionTiers.basic));
    expect(evolution.candidates.single.targetId, equals('light_punch'));
  });

  test('modifiersFor defaults to no modifiers when unset', () {
    const definition = TechniqueDefinition(
      id: 'basic_punch',
      name: 'Basic Punch',
      tier: EvolutionTiers.basic,
      tags: {},
      properties: {},
    );

    expect(definition.modifiersFor(const EntityId(1)), isEmpty);
  });
}
```

- [ ] **Step 3: Run to verify fail, then pass**

Run: `dart test test/plugins/technique/technique_definition_test.dart`

---

### Task 2: Vocabulary + content data + parsing

**Files:**
- Create: `lib/src/plugins/technique/technique_vocabulary.dart`
- Create: `lib/src/plugins/technique/technique_content.dart`
- Test: `test/plugins/technique/technique_content_test.dart`

**Interfaces:**
- Consumes: `TechniqueDefinition` (Task 1).
- Produces: `TechniqueIds` (id constants), `String techniqueSubject(String id)`, `String techniqueKnowledgeSubject(String id)`, `const techniqueReferenceType`.
- Produces: `const techniqueContentDefinitions`, `TechniqueDefinition techniqueDefinitionFromContent(ContentDefinition)`, `TechniqueDefinition techniqueDefinition(String id, PluginContext context)`.

- [ ] **Step 1: Write `technique_vocabulary.dart`**

```dart
/// Stable content ids for the Technique plugin's starter set
/// (`technique_content.dart`).
abstract final class TechniqueIds {
  static const basicPunch = 'basic_punch';
  static const basicSlash = 'basic_slash';
  static const basicGuard = 'basic_guard';
  static const lightPunch = 'light_punch';
  static const heavyPunch = 'heavy_punch';
  static const fastPunch = 'fast_punch';
  static const counterPunch = 'counter_punch';
  static const quickSlash = 'quick_slash';
  static const heavySlash = 'heavy_slash';
  static const fastGuard = 'fast_guard';
  static const counterGuard = 'counter_guard';
}

/// The canonical Discovery *and* Mastery subject for technique
/// [definitionId] — `'technique:<id>'`. Discovery and Mastery may safely
/// share this one string: they're stored in different component types
/// (`DiscoveryComponent` vs `MasteryComponent`), so there is no collision.
String techniqueSubject(String definitionId) => 'technique:$definitionId';

/// The canonical Learning (`ProgressionEngine`) subject for technique
/// [definitionId] — deliberately a *different* string from
/// [techniqueSubject], even though both are ultimately stored via
/// `MasteryTracker`/`MasteryComponent`: `ProgressionEngine.addExperience`
/// and `MasteryTracker.increase` would otherwise silently share one
/// number, collapsing Learning and Mastery into the same axis — exactly
/// what this milestone forbids ("Discovery != Learning != Mastery").
String techniqueKnowledgeSubject(String definitionId) =>
    'technique:$definitionId:knowledge';

/// The `BuildComponentRef.referenceType` every technique occupies a Tome
/// slot under — the canonical replacement for the bare `'technique'`
/// string literal already used ad hoc across test fixtures (e.g.
/// `test/tome/tome_service_test.dart`, `vertical_slice_runner.dart`).
const techniqueReferenceType = 'technique';
```

- [ ] **Step 2: Write `technique_content.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';
import 'technique_vocabulary.dart';

/// 3 base techniques + their 8 evolved branches, as data — loaded via
/// `PluginSdk.registerContentBatch` in `TechniquePlugin.initialize`.
/// Candidate tags match `TrainingDimensions` constants directly (`speed`/
/// `power`/`reaction`/`precision`) so `EvolutionResolver`'s existing
/// tag-weighted-by-`TrainingProfile` mechanism picks them up with zero
/// new resolver code — exactly the milestone's "high speed -> faster
/// candidates gain weight" example. Evolved branches are terminal
/// (no further `evolution` field) and carry no `requirements` — keeping
/// this plugin's shipped content fully standalone (no MartialArts tag
/// dependency) is what makes the "no Technique -> MartialArts dependency
/// unless content requires it" architecture check trivially true by
/// construction.
const techniqueContentDefinitions = <Map<String, dynamic>>[
  {
    'id': TechniqueIds.basicPunch,
    'type': 'technique',
    'name': 'Basic Punch',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'fist'],
    'properties': {'damage': 6},
    'evolution': [
      {'targetId': TechniqueIds.lightPunch, 'tags': [TrainingDimensions.precision]},
      {'targetId': TechniqueIds.heavyPunch, 'tags': [TrainingDimensions.power]},
      {'targetId': TechniqueIds.fastPunch, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.counterPunch, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.basicSlash,
    'type': 'technique',
    'name': 'Basic Slash',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'blade'],
    'properties': {'damage': 8},
    'evolution': [
      {'targetId': TechniqueIds.quickSlash, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.heavySlash, 'tags': [TrainingDimensions.power]},
    ],
  },
  {
    'id': TechniqueIds.basicGuard,
    'type': 'technique',
    'name': 'Basic Guard',
    'tier': EvolutionTiers.basic,
    'tags': ['technique', 'guard'],
    'properties': {'defense': 4},
    'evolution': [
      {'targetId': TechniqueIds.fastGuard, 'tags': [TrainingDimensions.speed]},
      {'targetId': TechniqueIds.counterGuard, 'tags': [TrainingDimensions.reaction]},
    ],
  },
  {
    'id': TechniqueIds.lightPunch,
    'type': 'technique',
    'name': 'Light Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'precision'],
    'properties': {'damage': 5, 'accuracy': 2},
  },
  {
    'id': TechniqueIds.heavyPunch,
    'type': 'technique',
    'name': 'Heavy Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'power'],
    'properties': {'damage': 11},
  },
  {
    'id': TechniqueIds.fastPunch,
    'type': 'technique',
    'name': 'Fast Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'speed'],
    'properties': {'damage': 5, 'hits': 2},
  },
  {
    'id': TechniqueIds.counterPunch,
    'type': 'technique',
    'name': 'Counter Punch',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'fist', 'counter'],
    'properties': {'damage': 7},
  },
  {
    'id': TechniqueIds.quickSlash,
    'type': 'technique',
    'name': 'Quick Slash',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'blade', 'speed'],
    'properties': {'damage': 6, 'hits': 2},
  },
  {
    'id': TechniqueIds.heavySlash,
    'type': 'technique',
    'name': 'Heavy Slash',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'blade', 'power'],
    'properties': {'damage': 15},
  },
  {
    'id': TechniqueIds.fastGuard,
    'type': 'technique',
    'name': 'Fast Guard',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'guard', 'speed'],
    'properties': {'defense': 3},
  },
  {
    'id': TechniqueIds.counterGuard,
    'type': 'technique',
    'name': 'Counter Guard',
    'tier': EvolutionTiers.intermediate,
    'tags': ['technique', 'guard', 'counter'],
    'properties': {'defense': 5},
  },
];

/// Builds a [TechniqueDefinition] from a loaded [ContentDefinition].
/// `extra['name']`/`extra['tier']` supply the two fields `ContentRegistry`
/// doesn't natively parse; `definition.conditions` (native) supplies
/// [TechniqueDefinition.requirements] verbatim; `extra['evolution']`
/// supplies [TechniqueDefinition.evolutionCandidates]; `extra['properties']`
/// supplies properties + [TechniqueDefinition.modifiersFor], exactly
/// mirroring `itemDefinitionFromContent`.
TechniqueDefinition techniqueDefinitionFromContent(ContentDefinition definition) {
  final rawProperties =
      (definition.extra['properties'] as Map?) ?? const <String, dynamic>{};
  final properties = <String, num>{
    for (final entry in rawProperties.entries)
      entry.key as String: entry.value as num,
  };

  final rawEvolution = (definition.extra['evolution'] as List?) ?? const [];
  final evolutionCandidates = [
    for (final entry in rawEvolution)
      EvolutionCandidate(
        targetId: (entry as Map)['targetId'] as String,
        tags: {
          for (final tag in (entry['tags'] as List? ?? const [])) tag as String,
        },
      ),
  ];

  List<Modifier> modifiersFor(EntityId owner) => [
        for (final entry in properties.entries)
          Modifier(
            source: ModifierSource(
                'technique:${definition.id}:${entry.key}:${owner.value}'),
            target: owner,
            stat: entry.key,
            operation: ModifierOperation.add,
            value: entry.value,
          ),
      ];

  return TechniqueDefinition(
    id: definition.id,
    name: definition.extra['name'] as String,
    tier: definition.extra['tier'] as String,
    tags: definition.tags,
    properties: properties,
    requirements: definition.conditions,
    evolutionCandidates: evolutionCandidates,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses technique [id] from [context]'s loaded content —
/// the same convenience `itemDefinition`/`martialItem` already provide.
TechniqueDefinition techniqueDefinition(String id, PluginContext context) =>
    techniqueDefinitionFromContent(context.content.get(id));
```

- [ ] **Step 3: Write the failing test** — `test/plugins/technique/technique_content_test.dart`

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('all 11 techniques load through ContentRegistry', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);

    for (final id in [
      TechniqueIds.basicPunch,
      TechniqueIds.basicSlash,
      TechniqueIds.basicGuard,
      TechniqueIds.lightPunch,
      TechniqueIds.heavyPunch,
      TechniqueIds.fastPunch,
      TechniqueIds.counterPunch,
      TechniqueIds.quickSlash,
      TechniqueIds.heavySlash,
      TechniqueIds.fastGuard,
      TechniqueIds.counterGuard,
    ]) {
      expect(registry.find(id), isNotNull, reason: '$id should be loaded');
    }
  });

  test('techniqueDefinitionFromContent parses name/tier/properties/evolution', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);

    final basicPunch = techniqueDefinitionFromContent(registry.get(TechniqueIds.basicPunch));

    expect(basicPunch.name, equals('Basic Punch'));
    expect(basicPunch.tier, equals(EvolutionTiers.basic));
    expect(basicPunch.properties['damage'], equals(6));
    expect(basicPunch.evolutionCandidates, hasLength(4));
    expect(
      basicPunch.evolutionCandidates.map((c) => c.targetId),
      containsAll([
        TechniqueIds.lightPunch,
        TechniqueIds.heavyPunch,
        TechniqueIds.fastPunch,
        TechniqueIds.counterPunch,
      ]),
    );
  });

  test('candidate tags match TrainingDimensions vocabulary', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);
    final basicPunch = techniqueDefinitionFromContent(registry.get(TechniqueIds.basicPunch));

    final fastPunch = basicPunch.evolutionCandidates
        .firstWhere((c) => c.targetId == TechniqueIds.fastPunch);

    expect(fastPunch.tags, contains(TrainingDimensions.speed));
  });

  test('an evolved (terminal) technique has no further evolution candidates', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);
    final lightPunch = techniqueDefinitionFromContent(registry.get(TechniqueIds.lightPunch));

    expect(lightPunch.evolutionCandidates, isEmpty);
    expect(lightPunch.tier, equals(EvolutionTiers.intermediate));
  });
}
```

- [ ] **Step 4: Run to verify fail, then pass**

Run: `dart test test/plugins/technique/technique_content_test.dart`

---

### Task 3: `TechniqueAddedToTome` event

**Files:**
- Create: `lib/src/plugins/technique/technique_events.dart`

Same rationale as `ItemAddedToTome`: `TomeService` has no `EventBus`, so
this is the one genuinely new event; Discovery/Learning/Mastery changes
already publish generically via `SubjectDiscovered`/`ProgressionChanged`/
`ProgressionTierReached`/`MasteryChanged`/`MasteryLevelReached`.

- [ ] **Step 1: Write `technique_events.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// Published by `addTechniqueToTome` once a technique has actually been
/// inserted into [owner]'s Tome — the one new event this plugin adds, for
/// the same reason `ItemAddedToTome` was: `TomeService` has no `EventBus`
/// of its own to hook a "was inserted" event onto otherwise.
class TechniqueAddedToTome {
  const TechniqueAddedToTome(this.owner, this.definitionId, this.slot);

  final EntityId owner;
  final String definitionId;
  final SlotId slot;
}
```

---

### Task 4: Lifecycle functions (Discovery / Learning / Mastery / Tome gate)

**Files:**
- Create: `lib/src/plugins/technique/technique_lifecycle.dart`
- Test: `test/plugins/technique/technique_lifecycle_test.dart`

**Interfaces:**
- Consumes: `TechniqueDefinition` (Task 1), vocabulary (Task 2), `TechniqueAddedToTome` (Task 3).
- Produces:
  - `void discoverTechnique(EntityId owner, TechniqueDefinition technique, PluginContext context)`
  - `bool isTechniqueDiscovered(EntityId owner, TechniqueDefinition technique, PluginContext context)`
  - `class LearningAttemptResult { final bool learned; final num experienceGained; final num totalExperience; }`
  - `LearningAttemptResult attemptToLearnTechnique(EntityId owner, TechniqueDefinition technique, num experienceGained, PluginContext context)`
  - `bool isTechniqueLearned(EntityId owner, TechniqueDefinition technique, PluginContext context)`
  - `void trainTechniqueMastery(EntityId owner, TechniqueDefinition technique, num amount, PluginContext context)`
  - `int techniqueMasteryLevel(EntityId owner, TechniqueDefinition technique, PluginContext context)`
  - `void addTechniqueToTome(EntityId owner, SlotId slot, TechniqueDefinition technique, PluginContext context)`
  - `class TechniqueNotDiscoveredException implements Exception { final String definitionId; }`
  - `class TechniqueRequirementsNotMetException implements Exception { final String definitionId; }`
  - `class TechniqueNotLearnedException implements Exception { final String definitionId; }`

- [ ] **Step 1: Write `technique_lifecycle.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';
import 'technique_events.dart';
import 'technique_vocabulary.dart';

class TechniqueNotDiscoveredException implements Exception {
  const TechniqueNotDiscoveredException(this.definitionId);
  final String definitionId;
  @override
  String toString() => 'Technique not discovered: $definitionId';
}

class TechniqueRequirementsNotMetException implements Exception {
  const TechniqueRequirementsNotMetException(this.definitionId);
  final String definitionId;
  @override
  String toString() => 'Technique requirements not met: $definitionId';
}

class TechniqueNotLearnedException implements Exception {
  const TechniqueNotLearnedException(this.definitionId);
  final String definitionId;
  @override
  String toString() => 'Technique not learned: $definitionId';
}

/// The result of one [attemptToLearnTechnique] call — success (crossed the
/// single learning threshold) or partial progress, never both silently
/// conflated. Mirrors `TrainingResult`'s own "pure data, no hidden
/// decision" shape.
class LearningAttemptResult {
  const LearningAttemptResult({
    required this.learned,
    required this.experienceGained,
    required this.totalExperience,
  });

  final bool learned;
  final num experienceGained;
  final num totalExperience;
}

/// Moves [owner]'s discovery state for [technique] to `discovered` — the
/// DISCOVERED state. Delegates entirely to the existing generic
/// `DiscoveryTracker`.
void discoverTechnique(EntityId owner, TechniqueDefinition technique, PluginContext context) =>
    context.discovery.discover(owner, techniqueSubject(technique.id));

/// Whether [owner] has at least discovered [technique] — reuses the
/// generic `IsDiscovered` condition rather than reading `DiscoveryState`
/// directly, the same pattern `usabilityConditionsFor` (Item plugin) uses.
bool isTechniqueDiscovered(
  EntityId owner,
  TechniqueDefinition technique,
  PluginContext context,
) =>
    IsDiscovered(techniqueSubject(technique.id)).evaluate(context.ruleContextFor(owner));

/// Attempts to learn [technique]: requires [technique] to be at least
/// discovered (else [TechniqueNotDiscoveredException]) and every one of
/// [TechniqueDefinition.requirements] to pass (else
/// [TechniqueRequirementsNotMetException]) — the two hard gates on even
/// *attempting* to learn. On a met gate, adds [experienceGained] to the
/// LEARNING axis via `ProgressionEngine.addExperience` (the "generic
/// progression primitive" this milestone calls for — `ProgressionEngine`'s
/// own doc comment already names "technique learning" as an intended use).
/// Crossing the single registered threshold is SUCCESS (LEARNED);
/// otherwise this is PROGRESS, not failure in the sense of "nothing
/// happened" — `LearningAttemptResult.learned` is the caller's signal,
/// never an exception. Deliberately never touches Evolution — "do not
/// automatically evolve the technique when it is merely learned."
LearningAttemptResult attemptToLearnTechnique(
  EntityId owner,
  TechniqueDefinition technique,
  num experienceGained,
  PluginContext context,
) {
  if (!isTechniqueDiscovered(owner, technique, context)) {
    throw TechniqueNotDiscoveredException(technique.id);
  }
  final ruleContext = context.ruleContextFor(owner);
  final requirementsMet =
      technique.requirements.every((condition) => condition.evaluate(ruleContext));
  if (!requirementsMet) {
    throw TechniqueRequirementsNotMetException(technique.id);
  }

  final subject = techniqueKnowledgeSubject(technique.id);
  context.progression.addExperience(owner, subject, experienceGained);
  return LearningAttemptResult(
    learned: context.progression.tierOf(owner, subject) >= 1,
    experienceGained: experienceGained,
    totalExperience: context.progression.experienceOf(owner, subject),
  );
}

/// Whether [owner] has successfully learned [technique] — the LEARNED
/// state, read live from `ProgressionEngine.tierOf`. Never stored
/// separately; can't desync from the experience it's based on.
bool isTechniqueLearned(EntityId owner, TechniqueDefinition technique, PluginContext context) =>
    context.progression.tierOf(owner, techniqueKnowledgeSubject(technique.id)) >= 1;

/// Adds [amount] of proficiency to [owner]'s MASTERY of [technique] — the
/// third, independent axis. Deliberately unrelated to
/// [attemptToLearnTechnique]/[isTechniqueLearned]: different subject
/// string ([techniqueSubject], not [techniqueKnowledgeSubject]), so
/// training mastery never moves the learned state and vice versa.
void trainTechniqueMastery(
  EntityId owner,
  TechniqueDefinition technique,
  num amount,
  PluginContext context,
) =>
    context.mastery.increase(owner, techniqueSubject(technique.id), amount);

/// [owner]'s current mastery level for [technique] — `0` if no
/// `MasteryDefinition` was registered for this subject or none has been
/// reached yet.
int techniqueMasteryLevel(
  EntityId owner,
  TechniqueDefinition technique,
  PluginContext context,
) =>
    context.mastery.levelOf(owner, techniqueSubject(technique.id));

/// Inserts [technique] into [owner]'s Tome at [slot] — but only if
/// [isTechniqueLearned] first. Throws [TechniqueNotLearnedException]
/// (leaving the Tome untouched) otherwise; on success, publishes
/// [TechniqueAddedToTome]. Mirrors `ItemPlugin.addItemToTome` exactly —
/// same reasoning for gating here rather than inside `TomeService`.
void addTechniqueToTome(
  EntityId owner,
  SlotId slot,
  TechniqueDefinition technique,
  PluginContext context,
) {
  if (!isTechniqueLearned(owner, technique, context)) {
    throw TechniqueNotLearnedException(technique.id);
  }
  context.tome.insert(
    owner,
    slot,
    BuildComponentRef(referenceType: techniqueReferenceType, contentId: technique.id),
  );
  context.events.publish(TechniqueAddedToTome(owner, technique.id, slot));
}
```

- [ ] **Step 2: Write the failing test** — `test/plugins/technique/technique_lifecycle_test.dart`

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_lifecycle.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

// Shares `mastery`/`progression`/`discovery` between RuleEngine and
// PluginContext, per ARCHITECTURE.md's bootstrap example — required
// whenever a caller writes through PluginContext.progression/.mastery
// directly and also reads through context.ruleContextFor (as
// isTechniqueDiscovered/attemptToLearnTechnique's requirements check do).
PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final mastery = MasteryTracker(components: components, events: events);
  final progression =
      ProgressionEngine(components: components, events: events, mastery: mastery);
  final discovery = DiscoveryTracker(components: components, events: events);
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
      mastery: mastery,
      progression: progression,
      discovery: discovery,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    mastery: mastery,
    progression: progression,
    discovery: discovery,
  );
}

void main() {
  late PluginContext context;
  late TechniqueDefinition basicPunch;

  setUp(() {
    context = _newContext();
    context.content.loadAll(techniqueContentDefinitions);
    basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
    context.progression.define(
      const ProgressionDefinition(subject: 'technique:basic_punch:knowledge', thresholds: [10]),
    );
    context.mastery.define(
      const MasteryDefinition(subject: 'technique:basic_punch', thresholds: [5, 15, 30]),
    );
  });

  test('a technique can be discovered', () {
    final owner = context.entities.create();

    discoverTechnique(owner, basicPunch, context);

    expect(isTechniqueDiscovered(owner, basicPunch, context), isTrue);
  });

  test('learning without discovery throws', () {
    final owner = context.entities.create();

    expect(
      () => attemptToLearnTechnique(owner, basicPunch, 10, context),
      throwsA(isA<TechniqueNotDiscoveredException>()),
    );
  });

  test('a learning attempt below the threshold yields progress, not learned', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);

    final result = attemptToLearnTechnique(owner, basicPunch, 4, context);

    expect(result.learned, isFalse);
    expect(result.totalExperience, equals(4));
    expect(isTechniqueLearned(owner, basicPunch, context), isFalse);
  });

  test('a learning attempt that crosses the threshold succeeds -> LEARNED', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);
    attemptToLearnTechnique(owner, basicPunch, 4, context);

    final result = attemptToLearnTechnique(owner, basicPunch, 6, context);

    expect(result.learned, isTrue);
    expect(isTechniqueLearned(owner, basicPunch, context), isTrue);
  });

  test('mastery independence: training mastery does not affect learned state, '
      'and learning does not affect mastery', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);

    trainTechniqueMastery(owner, basicPunch, 30, context);
    expect(techniqueMasteryLevel(owner, basicPunch, context), equals(3));
    expect(isTechniqueLearned(owner, basicPunch, context), isFalse);

    attemptToLearnTechnique(owner, basicPunch, 10, context);
    expect(isTechniqueLearned(owner, basicPunch, context), isTrue);
    // mastery, trained independently above, is unaffected by learning:
    expect(techniqueMasteryLevel(owner, basicPunch, context), equals(3));
  });

  test('a discovered-but-unlearned technique cannot enter the Tome', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    context.tome.createTome(owner, 'basic_tome');

    expect(
      () => addTechniqueToTome(owner, const SlotId('technique'), basicPunch, context),
      throwsA(isA<TechniqueNotLearnedException>()),
    );
    expect(context.tome.inspect(owner), isEmpty);
  });

  test('a learned technique can enter the Tome', () {
    final owner = context.entities.create();
    discoverTechnique(owner, basicPunch, context);
    attemptToLearnTechnique(owner, basicPunch, 10, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    context.tome.createTome(owner, 'basic_tome');

    TechniqueAddedToTome? published;
    context.events.subscribe<TechniqueAddedToTome>((e) => published = e);

    addTechniqueToTome(owner, const SlotId('technique'), basicPunch, context);

    expect(
      context.tome.inspect(owner).single.buildComponentRef.contentId,
      equals(TechniqueIds.basicPunch),
    );
    expect(published, isNotNull);
  });
}
```

- [ ] **Step 3: Run to verify fail, then pass**

Run: `dart test test/plugins/technique/technique_lifecycle_test.dart`

---

### Task 5: Evolution wrapper

**Files:**
- Create: `lib/src/plugins/technique/technique_evolution.dart`
- Test: `test/plugins/technique/technique_evolution_test.dart`

**Interfaces:**
- Consumes: `TechniqueDefinition.toEvolutionDefinition` (Task 1).
- Produces: `EvolutionResult evolveTechnique(EntityId owner, TechniqueDefinition technique, TrainingProfile profile, PluginContext context)`.

- [ ] **Step 1: Write `technique_evolution.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';

/// Resolves [technique]'s evolution candidates for [owner], weighted by
/// [profile] — a thin, discoverable wrapper over the existing
/// `EvolutionResolver`, which already does everything this milestone asks
/// for (candidate eligibility via `Condition`, weighting via
/// `TrainingProfile`-tag-matched `Modifier`s, the final draw via
/// `context.rng`). No new resolution logic lives here — see
/// `EvolutionResolver` itself for the mechanism. Never called
/// automatically by [attemptToLearnTechnique]; evolution stays an
/// explicit, separate operation the caller invokes when ready.
EvolutionResult evolveTechnique(
  EntityId owner,
  TechniqueDefinition technique,
  TrainingProfile profile,
  PluginContext context,
) =>
    const EvolutionResolver().resolve(
      context: context.ruleContextFor(owner),
      current: technique.toEvolutionDefinition(),
      profile: profile,
    );
```

- [ ] **Step 2: Write the failing test** — `test/plugins/technique/technique_evolution_test.dart`

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_evolution.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

PluginContext _newContext(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('branching evolution resolves to exactly one of the 4 basic_punch branches', () {
    final context = _newContext(7);
    context.content.loadAll(techniqueContentDefinitions);
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
    final owner = context.entities.create();

    final result = evolveTechnique(
      owner,
      basicPunch,
      const TrainingProfile({TrainingDimensions.speed: 0.5}),
      context,
    );

    expect(result.evolved, isTrue);
    expect(
      [
        TechniqueIds.lightPunch,
        TechniqueIds.heavyPunch,
        TechniqueIds.fastPunch,
        TechniqueIds.counterPunch,
      ],
      contains(result.chosenCandidate!.targetId),
    );
  });

  test('a high-speed training profile makes fast_punch win meaningfully more often', () {
    var fastWins = 0;
    const trials = 50;
    for (var seed = 0; seed < trials; seed++) {
      final context = _newContext(seed);
      context.content.loadAll(techniqueContentDefinitions);
      final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
      final owner = context.entities.create();

      final result = evolveTechnique(
        owner,
        basicPunch,
        const TrainingProfile({TrainingDimensions.speed: 0.95}),
        context,
      );
      if (result.chosenCandidate?.targetId == TechniqueIds.fastPunch) fastWins++;
    }

    // With 4 roughly-equal-weight candidates and speed at 0.95, fast_punch's
    // weight (~1.95) dominates the other three (~1.0 each); a bare-plurality
    // threshold (trials/4) already exceeds chance (25%) and is what the
    // profile's influence is being asserted against.
    expect(fastWins, greaterThan(trials ~/ 4));
  });

  test('deterministic: the same seed yields the same chosen candidate', () {
    EvolutionCandidate? runOnce() {
      final context = _newContext(42);
      context.content.loadAll(techniqueContentDefinitions);
      final basicSlash = techniqueDefinition(TechniqueIds.basicSlash, context);
      final owner = context.entities.create();
      return evolveTechnique(
        owner,
        basicSlash,
        const TrainingProfile({TrainingDimensions.power: 0.7}),
        context,
      ).chosenCandidate;
    }

    expect(runOnce()?.targetId, equals(runOnce()?.targetId));
  });
}
```

- [ ] **Step 3: Run to verify fail, then pass**

Run: `dart test test/plugins/technique/technique_evolution_test.dart`

---

### Task 6: `TechniquePlugin` + barrel

**Files:**
- Create: `lib/src/plugins/technique/technique_plugin.dart`
- Create: `lib/technique_plugin.dart`
- Test: `test/plugins/technique/technique_plugin_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: `class TechniquePlugin extends GamePlugin` (`id => 'technique'`, `dependencies => const []`).

- [ ] **Step 1: Write `lib/src/plugins/technique/technique_plugin.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'technique_content.dart';
import 'technique_vocabulary.dart';

/// The Technique plugin: generic learnable movements/abilities (Basic
/// Punch/Slash/Guard and their 8 evolved branches), built entirely with
/// `PluginSdk`, depending on nothing but Core — not Combat, not
/// MartialArts. A third proof (after `ElementalPlugin`/`ItemPlugin`) that
/// "copy Elemental, not MartialArts" produces a fully decoupled content
/// plugin.
///
/// Registers a single-tier `ProgressionDefinition` per base technique
/// (its LEARNING threshold) and a multi-tier `MasteryDefinition` (its
/// proficiency curve) — two independent registrations under two
/// deliberately different subject strings (see
/// `technique_vocabulary.dart`), keeping Discovery/Learning/Mastery from
/// ever colliding in storage. No `ComponentStore` cleanup is registered:
/// unlike `ItemPlugin` (which creates a per-owned-copy `ItemInstance`
/// entity), nothing here attaches a new component type to any entity —
/// every axis is tracked entirely through the existing
/// Discovery/Progression/Mastery trackers, keyed by subject strings, with
/// zero new ECS state of its own.
class TechniquePlugin extends GamePlugin {
  @override
  String get id => 'technique';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can be
  /// `initialize`d again after `unregister`.
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);

    sdk.registerTag('technique', description: 'A learnable movement/ability.');

    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find(TechniqueIds.basicPunch) == null) {
      sdk.registerContentBatch(techniqueContentDefinitions);
    }

    // A single-tier LEARNING threshold per base technique — evolved
    // (terminal) branches aren't independently "learned" in this pass.
    for (final id in [TechniqueIds.basicPunch, TechniqueIds.basicSlash, TechniqueIds.basicGuard]) {
      context.progression.define(
        ProgressionDefinition(subject: techniqueKnowledgeSubject(id), thresholds: const [10]),
      );
      context.mastery.define(
        MasteryDefinition(subject: techniqueSubject(id), thresholds: const [5, 15, 30]),
      );
    }
  }

  /// Nothing to tear down beyond the SDK's own bookkeeping — this plugin
  /// registers no rules, no event subscriptions, no component cleanup.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
```

- [ ] **Step 2: Write the barrel `lib/technique_plugin.dart`**

```dart
/// The Technique plugin's public surface — import this, never
/// `package:build_engine/src/plugins/technique/...` directly.
library;

export 'src/plugins/technique/technique_content.dart'
    show techniqueContentDefinitions, techniqueDefinition, techniqueDefinitionFromContent;
export 'src/plugins/technique/technique_definition.dart';
export 'src/plugins/technique/technique_evolution.dart';
export 'src/plugins/technique/technique_events.dart';
export 'src/plugins/technique/technique_lifecycle.dart';
export 'src/plugins/technique/technique_plugin.dart';
export 'src/plugins/technique/technique_vocabulary.dart';
```

- [ ] **Step 3: Write the failing test** — `test/plugins/technique/technique_plugin_test.dart` (mirrors `test/plugins/item/item_plugin_test.dart`)

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final mastery = MasteryTracker(components: components, events: events);
  final progression =
      ProgressionEngine(components: components, events: events, mastery: mastery);
  final discovery = DiscoveryTracker(components: components, events: events);
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
      mastery: mastery,
      progression: progression,
      discovery: discovery,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    mastery: mastery,
    progression: progression,
    discovery: discovery,
  );
}

void main() {
  test('declares no dependencies', () {
    expect(TechniquePlugin().dependencies, isEmpty);
  });

  test('initialize registers all 11 techniques and the learning/mastery definitions', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);

    expect(context.content.get(TechniqueIds.basicPunch), isNotNull);
    expect(context.content.get(TechniqueIds.lightPunch), isNotNull);
    expect(context.progression.definitionOf('technique:basic_punch:knowledge'), isNotNull);
    expect(context.mastery.definitionOf('technique:basic_punch'), isNotNull);
  });

  test('re-initializing on the same context does not throw ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = TechniquePlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.get(TechniqueIds.basicPunch).type, equals('technique'));
  });

  test('TechniquePlugin runs standalone (no Combat, no MartialArts) end to end', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(TechniquePlugin());
    manager.initialize(context);
    manager.start(context);

    final owner = context.entities.create();
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    context.tome.createTome(owner, 'basic_tome');

    discoverTechnique(owner, basicPunch, context);
    attemptToLearnTechnique(owner, basicPunch, 10, context);
    addTechniqueToTome(owner, const SlotId('technique'), basicPunch, context);

    expect(
      context.tome.inspect(owner).single.buildComponentRef.contentId,
      equals(TechniqueIds.basicPunch),
    );

    manager.stop(context);
    manager.unregister(context);
  });
}
```

- [ ] **Step 4: Run to verify fail, then pass**

Run: `dart test test/plugins/technique/technique_plugin_test.dart`

---

### Task 7: Architecture dependency checks + integration tests

**Files:**
- Modify: `test/integration/architecture_dependency_test.dart`
- Create: `test/integration/technique_end_to_end_test.dart`
- Create: `test/integration/learning_progression_reuse_test.dart`

- [ ] **Step 1: Add the Technique barrel and symmetric group to `architecture_dependency_test.dart`**

Add `_techniqueBarrel = 'technique_plugin.dart'` to `_pluginBarrels` (group H
auto-covers it), and a new group mirroring Item's:

```dart
group('Technique plugin is fully decoupled from every other plugin', () {
  test('Technique does not reference MartialArts', () {
    _assertNoPluginImport(
        'martial_arts', _martialArtsBarrel, 'lib/src/plugins/technique');
  });

  test('Technique does not reference Elemental', () {
    _assertNoPluginImport(
        'elemental', _elementalBarrel, 'lib/src/plugins/technique');
  });

  test('Technique does not reference Physique', () {
    _assertNoPluginImport(
        'physique', _physiqueBarrel, 'lib/src/plugins/technique');
  });

  test('Technique does not reference Combat', () {
    _assertNoPluginImport('combat', _combatBarrel, 'lib/src/plugins/technique');
  });

  test('Technique does not reference AutoCombat', () {
    _assertNoPluginImport(
        'auto_combat', _autoCombatBarrel, 'lib/src/plugins/technique');
  });

  test('Technique does not reference Item', () {
    _assertNoPluginImport('item', _itemBarrel, 'lib/src/plugins/technique');
  });
});
```

- [ ] **Step 2: Write `test/integration/technique_end_to_end_test.dart`** (full lifecycle: discover → learning progress → learned → Tome; determinism)

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final mastery = MasteryTracker(components: components, events: events);
  final progression =
      ProgressionEngine(components: components, events: events, mastery: mastery);
  final discovery = DiscoveryTracker(components: components, events: events);
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
      mastery: mastery,
      progression: progression,
      discovery: discovery,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    mastery: mastery,
    progression: progression,
    discovery: discovery,
  );
}

void main() {
  test(
      'full technique lifecycle: discover -> learning (progress) -> learned '
      '-> Tome -> evolution', () {
    final context = _newContext();
    TechniquePlugin().initialize(context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
    );
    final character = context.characters.create();
    context.tome.createTome(character, 'basic_tome');
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);

    // discover
    discoverTechnique(character, basicPunch, context);
    expect(isTechniqueDiscovered(character, basicPunch, context), isTrue);
    expect(isTechniqueLearned(character, basicPunch, context), isFalse);
    expect(
      () => addTechniqueToTome(character, const SlotId('technique'), basicPunch, context),
      throwsA(isA<TechniqueNotLearnedException>()),
    );

    // learning: below threshold -> still not learned (LEARNING)
    final partial = attemptToLearnTechnique(character, basicPunch, 6, context);
    expect(partial.learned, isFalse);
    expect(isTechniqueLearned(character, basicPunch, context), isFalse);

    // learning: crosses threshold -> learned
    final complete = attemptToLearnTechnique(character, basicPunch, 4, context);
    expect(complete.learned, isTrue);
    expect(isTechniqueLearned(character, basicPunch, context), isTrue);

    // Tome
    addTechniqueToTome(character, const SlotId('technique'), basicPunch, context);
    final build = context.tome.resolve(character);
    expect(
      build.components.any((c) =>
          c.referenceType == techniqueReferenceType && c.contentId == TechniqueIds.basicPunch),
      isTrue,
    );

    // evolution — a separate, explicit operation
    final evolution = evolveTechnique(
      character,
      basicPunch,
      const TrainingProfile({TrainingDimensions.power: 0.8}),
      context,
    );
    expect(evolution.evolved, isTrue);
  });

  test('deterministic: two identically-seeded runs learn and evolve the same way', () {
    (bool, String?) runOnce() {
      final context = _newContext();
      TechniquePlugin().initialize(context);
      final character = context.characters.create();
      final basicSlash = techniqueDefinition(TechniqueIds.basicSlash, context);

      discoverTechnique(character, basicSlash, context);
      final result = attemptToLearnTechnique(character, basicSlash, 10, context);
      final evolution = evolveTechnique(
        character,
        basicSlash,
        const TrainingProfile({TrainingDimensions.speed: 0.7}),
        context,
      );
      return (result.learned, evolution.chosenCandidate?.targetId);
    }

    expect(runOnce(), equals(runOnce()));
  });
}
```

- [ ] **Step 3: Write `test/integration/learning_progression_reuse_test.dart`** (test #9 — proves the primitives are technique-agnostic, zero Technique import)

```dart
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

/// Proves `ProgressionEngine` (the Learning primitive) and
/// `EvolutionResolver` serve a domain that has nothing to do with
/// techniques at all, with zero import of `technique_plugin.dart` or
/// anything under `lib/src/plugins/technique/` — the milestone's own
/// "unrelated content can reuse learning/evolution primitives"
/// requirement, proven structurally rather than asserted in prose.
void main() {
  test('a made-up "recipe learning" domain reuses ProgressionEngine directly', () {
    final events = EventBus();
    final components = ComponentStore();
    final mastery = MasteryTracker(components: components, events: events);
    final progression =
        ProgressionEngine(components: components, events: events, mastery: mastery);
    const cook = EntityId(1);
    const subject = 'recipe:herbal_soup:knowledge';

    progression.define(const ProgressionDefinition(subject: subject, thresholds: [5]));
    progression.addExperience(cook, subject, 3);
    expect(progression.tierOf(cook, subject), equals(0));

    progression.addExperience(cook, subject, 2);
    expect(progression.tierOf(cook, subject), equals(1));
  });

  test('the same EvolutionResolver serves a made-up "recipe upgrade" tree', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(9);
    final context = RuleContext(
      subject: const EntityId(1),
      triggerEvent: const Object(),
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      eventCounts: EventCounter(events),
    );
    const recipeTree = EvolutionDefinition(
      id: 'herbal_soup',
      tier: EvolutionTiers.basic,
      candidates: [
        EvolutionCandidate(targetId: 'hearty_herbal_soup', tags: {'power'}),
        EvolutionCandidate(targetId: 'delicate_herbal_soup', tags: {'precision'}),
      ],
    );
    const profile = TrainingProfile({TrainingDimensions.precision: 0.8});

    final result = const EvolutionResolver().resolve(
      context: context,
      current: recipeTree,
      profile: profile,
    );

    expect(result.evolved, isTrue);
    expect(
      ['hearty_herbal_soup', 'delicate_herbal_soup'],
      contains(result.chosenCandidate!.targetId),
    );
  });
}
```

- [ ] **Step 4: Run everything Technique-related together**

Run: `dart test test/plugins/technique/ test/integration/technique_end_to_end_test.dart test/integration/learning_progression_reuse_test.dart test/integration/architecture_dependency_test.dart`

---

### Task 8: Full quality gate

- [ ] **Step 1:** `dart test` — expect PASS, baseline 763 + this plan's new tests, zero regressions.
- [ ] **Step 2:** `dart analyze` — expect `No issues found!`.
- [ ] **Step 3:** Do not commit (per milestone instructions) unless the user explicitly asks.

---

## Self-Review Notes

- **Spec coverage:** Discovery/Learning/Mastery as 3 independent axes —
  Task 4 (three different subjects, two different tracker types). "Smallest
  generic progression primitive" — resolved as "already exists"
  (`ProgressionEngine`), zero new Core code, documented in the Architecture
  section above. Tier as content data — Task 1/2 (`EvolutionTiers`, already
  existing, reused verbatim). Learning operation success/progress — Task 4's
  `LearningAttemptResult`. Evolution reuse + TrainingProfile weighting —
  Task 5 (zero new resolver logic). Content (3 base + 8 branches) — Task 2.
  Tome eligibility — Task 4's `addTechniqueToTome`. All 10 named test
  scenarios — Tasks 1, 2, 4, 5, 7. No Technique->MartialArts dependency —
  Task 7 (by construction: zero import) + explicit architecture-test group.
- **Not implemented, by design, per "DO NOT IMPLEMENT":** UI, animations,
  real training minigames (the plan's tests submit a raw `experienceGained`
  number directly — no `TrainingExercise`/minigame simulation), combat
  action interpretation (`modifiersFor` exposed but never auto-applied,
  matching `ItemDefinition`'s precedent), new combat mechanics, magic,
  cultivation.
