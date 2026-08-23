# Physique Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `PhysiquePlugin` — a new, independent content plugin
(Sturdy/Power/Burst/Endurance body types) depending only on Core, whose
one synergy mechanic with MartialArts is proven to work through generic
tags and the Modifier Engine alone, with zero Dart import in either
direction.

**Architecture:** `PhysiqueComponent` holds only a stable physique id.
`physiqueContentDefinitions` load through `ContentRegistry`;
`modifiers`/`affinities` (not part of `ContentRegistry`'s native
vocabulary) land on `ContentDefinition.extra` and
`physiqueDefinitionFromContent` turns that into a typed
`PhysiqueDefinition` whose `modifiersFor(character)` builds real
`Modifier` objects — mirroring MartialArts' own
`martialTechniqueFromDefinition`. `initializePhysique` is a plain,
idempotent function (not a `Rule`) that picks via `context.rng`,
attaches the component, registers two conditional synergy `Modifier`s
per character (`×1.25` strong / `×0.85` anti, gated on `'western'`/
`'eastern'` tags), and publishes `PhysiqueAssigned`. The one MartialArts
change: `learnStyle` grants the `'western'`/`'eastern'` tradition tag it
was already missing — the explicitly-permitted generic interoperability
hook, not Physique-specific logic.

**Tech Stack:** Dart `^3.7.0`, `package:test`, package `build_engine`.

**Spec:** `docs/superpowers/specs/2026-08-23-physique-plugin-design.md`

## Global Constraints

- `PhysiquePlugin.dependencies => const []` — Core only. No file under
  `lib/src/plugins/physique/` may reference `martial_arts`, `combat`,
  or `elemental`.
- No file under `lib/src/plugins/martial_arts/` or
  `lib/src/plugins/combat/` may reference `physique`.
- The only change to MartialArts is the one tradition-tag grant in
  `learnStyle` — no other MartialArts file changes, no behavior change
  to anything already shipped there.
- Do not create `WesternSynergySystem`, `EasternSynergySystem`, or
  `MartialArtsPhysiqueSystem` — synergy is two plain conditional
  `Modifier`s per physique, nothing else.
- No explicit "neutral ×1.00" modifier — an entity with neither
  tradition tag has no active modifier for that stat, which
  `ModifierResolver` already treats as the identity.
- `PhysiqueComponent` holds only the physique id — no tags, no
  affinity, no modifiers duplicated onto it.
- No changes to `PluginSdk`, `ContentRegistry`, Combat, or a fifth
  physique type. No Cultivation, no Magic.
- `dart:math`'s `Random` must never appear in this plugin — only
  `context.rng` (`RngService`).
- Run `dart analyze` and the full `dart test` suite after every task;
  both must stay clean/green.

---

### Task 1: `PhysiqueTypes` and `PhysiqueComponent`

**Files:**
- Create: `lib/src/plugins/physique/physique_types.dart`
- Create: `lib/src/plugins/physique/physique_component.dart`
- Create: `lib/physique_plugin.dart`
- Test: `test/plugins/physique/physique_types_test.dart`
- Test: `test/plugins/physique/physique_component_test.dart`

- [ ] **Step 1: Write `physique_types.dart`**

```dart
/// The four physique types this plugin implements. Not components — a
/// physique is data, attached to a character via a [PhysiqueComponent]
/// holding only this stable id.
abstract final class PhysiqueTypes {
  static const sturdy = 'sturdy';
  static const power = 'power';
  static const burst = 'burst';
  static const endurance = 'endurance';

  /// All four ids, in a fixed order — `initializePhysique` indexes into
  /// this list via `RngService.nextInt`, so this order is part of what
  /// makes a given seed's outcome deterministic.
  static const all = [sturdy, power, burst, endurance];
}
```

- [ ] **Step 2: Write `physique_component.dart`**

```dart
/// A character's assigned physique — deliberately minimal: only the
/// stable [physiqueId] (see `PhysiqueTypes`). Everything else about a
/// physique (tags, primary affinity, synergy modifiers) is data, held
/// in `ContentRegistry`/`ModifierCollection` and resolved from this id
/// when needed, never duplicated onto the component itself.
class PhysiqueComponent {
  const PhysiqueComponent(this.physiqueId);

  final String physiqueId;
}
```

- [ ] **Step 3: Write `lib/physique_plugin.dart`**

```dart
/// Public API for PhysiquePlugin — a character's body type
/// (Sturdy/Power/Burst/Endurance). Depends on nothing but Core; never
/// imports MartialArtsPlugin or CombatPlugin. Import this, not
/// `lib/src/...` directly.
library;

export 'src/plugins/physique/physique_component.dart';
export 'src/plugins/physique/physique_types.dart';
```

- [ ] **Step 4: Write `physique_types_test.dart`**

```dart
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('PhysiqueTypes names the four physiques', () {
    expect(PhysiqueTypes.sturdy, equals('sturdy'));
    expect(PhysiqueTypes.power, equals('power'));
    expect(PhysiqueTypes.burst, equals('burst'));
    expect(PhysiqueTypes.endurance, equals('endurance'));
  });

  test('PhysiqueTypes.all lists all four, in a fixed order', () {
    expect(
      PhysiqueTypes.all,
      equals([
        PhysiqueTypes.sturdy,
        PhysiqueTypes.power,
        PhysiqueTypes.burst,
        PhysiqueTypes.endurance,
      ]),
    );
  });
}
```

- [ ] **Step 5: Write `physique_component_test.dart`**

```dart
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('PhysiqueComponent stores the given physique id', () {
    const component = PhysiqueComponent('sturdy');
    expect(component.physiqueId, equals('sturdy'));
  });
}
```

- [ ] **Step 6: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes).

```bash
git add lib/src/plugins/physique/physique_types.dart \
  lib/src/plugins/physique/physique_component.dart \
  lib/physique_plugin.dart \
  test/plugins/physique/physique_types_test.dart \
  test/plugins/physique/physique_component_test.dart
git commit -m "feat: add PhysiqueTypes and PhysiqueComponent"
```

---

### Task 2: `PhysiqueDefinition` and physique content

**Files:**
- Create: `lib/src/plugins/physique/physique_content.dart`
- Modify: `lib/physique_plugin.dart`
- Test: `test/plugins/physique/physique_content_test.dart`

**Interfaces:**
- Consumes: `ContentDefinition`, `ContentRegistry`, `Modifier`,
  `ModifierOperation`, `ModifierSource`, `HasTagQuery`, `EntityId`
  (`package:build_engine/build_engine.dart`) — all pre-existing.
- Produces: `const physiqueContentDefinitions`, `class PhysiqueDefinition
  { final String id; final Set<String> tags; final String
  primaryAffinity; final List<Modifier> Function(EntityId)
  modifiersFor; }`, `PhysiqueDefinition
  physiqueDefinitionFromContent(ContentDefinition definition)`.

- [ ] **Step 1: Write `physique_content.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// The four physique definitions this plugin implements, as data —
/// loaded into `PluginContext.content` via `PluginSdk.registerContentBatch`
/// in `PhysiquePlugin.initialize`, mirroring MartialArts'
/// `martialTechniqueContentDefinitions` and Elemental's
/// `elementalContentDefinitions`.
///
/// `affinities`/`modifiers` are Physique-specific fields `ContentRegistry`
/// doesn't recognize — they surface verbatim on `ContentDefinition.extra`,
/// exactly like `martial_technique_content.dart`'s `baseDamage`/
/// `damageStat`. `modifiers` isn't part of `ContentRegistry`'s vocabulary
/// at all (`Modifier` isn't an `Effect`/`Condition`) —
/// `physiqueDefinitionFromContent` below turns this raw shape into real
/// `Modifier`-producing closures, the same way `martialTechniqueFromDefinition`
/// turns its own `extra` fields into a real `MartialTechniqueAction`.
///
/// Each `modifiers` entry's `condition` is a bare tag name — `'western'`/
/// `'eastern'`, the generic tags MartialArts grants a character via
/// `learnStyle`. Physique never imports MartialArts to know this; it
/// only agrees on the tag *names*.
const physiqueContentDefinitions = <Map<String, dynamic>>[
  {
    'id': 'sturdy',
    'type': 'physique',
    'tags': ['physique', 'defense', 'western_affinity'],
    'affinities': ['defense'],
    'modifiers': [
      {
        'stat': 'defense',
        'operation': 'multiply',
        'value': 1.25,
        'condition': 'western',
      },
      {
        'stat': 'defense',
        'operation': 'multiply',
        'value': 0.85,
        'condition': 'eastern',
      },
    ],
  },
  {
    'id': 'power',
    'type': 'physique',
    'tags': ['physique', 'strength', 'western_affinity'],
    'affinities': ['strength'],
    'modifiers': [
      {
        'stat': 'strength',
        'operation': 'multiply',
        'value': 1.25,
        'condition': 'western',
      },
      {
        'stat': 'strength',
        'operation': 'multiply',
        'value': 0.85,
        'condition': 'eastern',
      },
    ],
  },
  {
    'id': 'burst',
    'type': 'physique',
    'tags': ['physique', 'speed', 'eastern_affinity'],
    'affinities': ['speed'],
    'modifiers': [
      {
        'stat': 'speed',
        'operation': 'multiply',
        'value': 1.25,
        'condition': 'eastern',
      },
      {
        'stat': 'speed',
        'operation': 'multiply',
        'value': 0.85,
        'condition': 'western',
      },
    ],
  },
  {
    'id': 'endurance',
    'type': 'physique',
    'tags': ['physique', 'stamina', 'eastern_affinity'],
    'affinities': ['stamina'],
    'modifiers': [
      {
        'stat': 'stamina',
        'operation': 'multiply',
        'value': 1.25,
        'condition': 'eastern',
      },
      {
        'stat': 'stamina',
        'operation': 'multiply',
        'value': 0.85,
        'condition': 'western',
      },
    ],
  },
];

/// A parsed, runtime-usable physique — [modifiersFor] builds this
/// physique's synergy `Modifier`s for a specific character, read from
/// [physiqueContentDefinitions] via [physiqueDefinitionFromContent].
class PhysiqueDefinition {
  const PhysiqueDefinition({
    required this.id,
    required this.tags,
    required this.primaryAffinity,
    required this.modifiersFor,
  });

  final String id;
  final Set<String> tags;

  /// The stat name this physique's synergy modifiers target —
  /// `'defense'`/`'strength'`/`'speed'`/`'stamina'`, an arbitrary,
  /// caller-chosen string like every other stat name in this engine
  /// (the same convention `damageStat` already follows). Not read by
  /// Core or Combat; whatever future content resolves this stat name
  /// benefits from the synergy for free.
  final String primaryAffinity;

  final List<Modifier> Function(EntityId character) modifiersFor;
}

/// Builds a [PhysiqueDefinition] from a loaded [ContentDefinition].
/// `extra['affinities']` (a one-element list today; the field stays a
/// list for a physique that later needs more than one) supplies
/// [PhysiqueDefinition.primaryAffinity]; `extra['modifiers']` supplies
/// [PhysiqueDefinition.modifiersFor] — each raw entry becomes exactly
/// one conditional `Modifier`, gated on a bare tag name via
/// `HasTagQuery`. No explicit "neutral ×1.00" modifier is registered
/// for either tradition tag — an entity with neither tag simply has no
/// active modifier for this stat, and `ModifierResolver` already treats
/// an empty modifier set as the identity (base value unchanged), which
/// *is* "neutral".
PhysiqueDefinition physiqueDefinitionFromContent(
    ContentDefinition definition) {
  final affinities =
      (definition.extra['affinities'] as List).map((e) => e as String).toList();
  final rawModifiers = (definition.extra['modifiers'] as List)
      .map((e) => (e as Map).map((k, v) => MapEntry(k as String, v)))
      .toList();

  List<Modifier> modifiersFor(EntityId character) => [
        for (var i = 0; i < rawModifiers.length; i++)
          Modifier(
            source:
                ModifierSource('physique:${definition.id}:$i:${character.value}'),
            target: character,
            stat: rawModifiers[i]['stat'] as String,
            operation: _operationFor(rawModifiers[i]['operation'] as String),
            value: rawModifiers[i]['value'] as num,
            condition: HasTagQuery(rawModifiers[i]['condition'] as String),
          ),
      ];

  return PhysiqueDefinition(
    id: definition.id,
    tags: definition.tags,
    primaryAffinity: affinities.first,
    modifiersFor: modifiersFor,
  );
}

ModifierOperation _operationFor(String name) => switch (name) {
      'add' => ModifierOperation.add,
      'multiply' => ModifierOperation.multiply,
      'override' => ModifierOperation.override,
      'min' => ModifierOperation.min,
      'max' => ModifierOperation.max,
      _ => throw ArgumentError('unknown modifier operation: $name'),
    };
```

- [ ] **Step 2: Update `lib/physique_plugin.dart`**

```dart
/// Public API for PhysiquePlugin — a character's body type
/// (Sturdy/Power/Burst/Endurance). Depends on nothing but Core; never
/// imports MartialArtsPlugin or CombatPlugin. Import this, not
/// `lib/src/...` directly.
library;

export 'src/plugins/physique/physique_component.dart';
export 'src/plugins/physique/physique_content.dart';
export 'src/plugins/physique/physique_types.dart';
```

- [ ] **Step 3: Write `physique_content_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('all 4 physique definitions load atomically as a batch', () {
    final registry = ContentRegistry();
    final definitions = registry.loadAll(physiqueContentDefinitions);
    expect(definitions, hasLength(4));
    expect(registry.allOfType('physique'), hasLength(4));
  });

  group('physiqueDefinitionFromContent', () {
    test('parses sturdy: id, tags, and primary affinity', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      final definition = physiqueDefinitionFromContent(registry.get('sturdy'));
      expect(definition.id, equals('sturdy'));
      expect(definition.tags,
          equals({'physique', 'defense', 'western_affinity'}));
      expect(definition.primaryAffinity, equals('defense'));
    });

    test('parses power/burst/endurance primary affinities', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      expect(physiqueDefinitionFromContent(registry.get('power')).primaryAffinity,
          equals('strength'));
      expect(physiqueDefinitionFromContent(registry.get('burst')).primaryAffinity,
          equals('speed'));
      expect(
          physiqueDefinitionFromContent(registry.get('endurance'))
              .primaryAffinity,
          equals('stamina'));
    });

    test(
        'modifiersFor builds exactly 2 conditional multiply modifiers on '
        'the primary affinity stat, targeting the given character', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      final definition = physiqueDefinitionFromContent(registry.get('sturdy'));
      final character = const EntityId(1);

      final modifiers = definition.modifiersFor(character);

      expect(modifiers, hasLength(2));
      for (final modifier in modifiers) {
        expect(modifier.target, equals(character));
        expect(modifier.stat, equals('defense'));
        expect(modifier.operation, equals(ModifierOperation.multiply));
        expect(modifier.condition, isNotNull);
      }
      expect(modifiers.map((m) => m.value).toSet(), equals({1.25, 0.85}));
    });

    test('modifiersFor builds a fresh set per call, targeting whichever '
        'character is given', () {
      final registry = ContentRegistry();
      registry.loadAll(physiqueContentDefinitions);
      final definition = physiqueDefinitionFromContent(registry.get('sturdy'));

      final a = const EntityId(1);
      final b = const EntityId(2);

      expect(definition.modifiersFor(a).every((m) => m.target == a), isTrue);
      expect(definition.modifiersFor(b).every((m) => m.target == b), isTrue);
    });
  });
}
```

- [ ] **Step 4: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes).

```bash
git add lib/src/plugins/physique/physique_content.dart \
  lib/physique_plugin.dart \
  test/plugins/physique/physique_content_test.dart
git commit -m "feat: add PhysiqueDefinition and physique content definitions"
```

---

### Task 3: `PhysiqueAssigned` event and `initializePhysique`

**Files:**
- Create: `lib/src/plugins/physique/physique_events.dart`
- Create: `lib/src/plugins/physique/physique_initialization.dart`
- Modify: `lib/physique_plugin.dart`
- Test: `test/plugins/physique/physique_events_test.dart`
- Test: `test/plugins/physique/physique_initialization_test.dart`

**Interfaces:**
- Consumes: `PhysiqueComponent` (Task 1), `PhysiqueDefinition`,
  `physiqueDefinitionFromContent` (Task 2), `PhysiqueTypes` (Task 1) —
  all via `package:build_engine/physique_plugin.dart`; `EntityId`,
  `PluginContext` (`package:build_engine/build_engine.dart`).
- Produces: `class PhysiqueAssigned { final EntityId character; final
  String physiqueId; }`, `String initializePhysique(EntityId character,
  PluginContext context)`.

- [ ] **Step 1: Write `physique_events.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// Published by `initializePhysique` once a character's physique has
/// been selected and its `PhysiqueComponent` attached.
class PhysiqueAssigned {
  const PhysiqueAssigned(this.character, this.physiqueId);

  final EntityId character;
  final String physiqueId;
}
```

- [ ] **Step 2: Write `physique_initialization.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'physique_component.dart';
import 'physique_content.dart';
import 'physique_events.dart';
import 'physique_types.dart';

/// The one generic character-initialization mechanism this plugin
/// provides: given [character] and [context], ensures it has exactly
/// one [PhysiqueComponent] (idempotent — a character that already has
/// one is left untouched, and its existing id is returned), selecting
/// uniformly among [PhysiqueTypes.all] via `context.rng` — never
/// `dart:math` directly, so the same seed and the same sequence of
/// prior `RngService` draws always produce the same physique. Registers
/// the selected physique's synergy `Modifier`s and publishes
/// [PhysiqueAssigned].
///
/// Deliberately a plain function, not a `Rule` reacting to
/// `EntityCreated` — not every entity Core creates is a "character"
/// (battle entities, item entities, ...), so nothing about entity
/// creation alone says when this should run. Whoever creates a
/// character (a future content plugin, a game's own character-creation
/// flow — never this plugin, and never a game-specific
/// "NewGameManager") calls this explicitly, the same way
/// `learnStyle`/`attuneToElement`/`equipItem` are each called
/// explicitly rather than wired to fire automatically.
String initializePhysique(EntityId character, PluginContext context) {
  final existing = context.components.get<PhysiqueComponent>(character);
  if (existing != null) return existing.physiqueId;

  final physiqueId =
      PhysiqueTypes.all[context.rng.nextInt(PhysiqueTypes.all.length)];
  final definition =
      physiqueDefinitionFromContent(context.content.get(physiqueId));

  context.components.add(character, PhysiqueComponent(physiqueId));
  for (final modifier in definition.modifiersFor(character)) {
    context.modifiers.add(modifier);
  }
  context.events.publish(PhysiqueAssigned(character, physiqueId));

  return physiqueId;
}
```

- [ ] **Step 3: Update `lib/physique_plugin.dart`**

```dart
/// Public API for PhysiquePlugin — a character's body type
/// (Sturdy/Power/Burst/Endurance). Depends on nothing but Core; never
/// imports MartialArtsPlugin or CombatPlugin. Import this, not
/// `lib/src/...` directly.
library;

export 'src/plugins/physique/physique_component.dart';
export 'src/plugins/physique/physique_content.dart';
export 'src/plugins/physique/physique_events.dart';
export 'src/plugins/physique/physique_initialization.dart';
export 'src/plugins/physique/physique_types.dart';
```

- [ ] **Step 4: Write `physique_events_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('PhysiqueAssigned stores the character and physique id', () {
    const character = EntityId(1);
    const event = PhysiqueAssigned(character, 'sturdy');
    expect(event.character, equals(character));
    expect(event.physiqueId, equals('sturdy'));
  });
}
```

- [ ] **Step 5: Write `physique_initialization_test.dart`**

Note: `initializePhysique` reads `context.content`, so every context in
this file must have `PhysiquePlugin` initialized on it first (the
content isn't loaded otherwise, and `context.content.get(physiqueId)`
would throw `ContentNotFoundException`).

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext(int seed) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(seed);
  final context = PluginContext(
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
  PhysiquePlugin().initialize(context);
  return context;
}

void main() {
  test('1: every character receives exactly one physique', () {
    final context = _newContext(1);
    final character = context.entities.create();

    initializePhysique(character, context);

    final component = context.components.get<PhysiqueComponent>(character);
    expect(component, isNotNull);
    expect(PhysiqueTypes.all, contains(component!.physiqueId));
  });

  test('2: physique selection uses RngService (context.rng), not '
      'dart:math directly', () {
    final context = _newContext(42);
    final character = context.entities.create();

    final physiqueId = initializePhysique(character, context);

    expect(PhysiqueTypes.all, contains(physiqueId));
    // Structural confirmation this used context.rng, not dart:math's
    // Random, is that determinism (test 3, same file) holds at all —
    // an unseeded, process-global Random could not produce it.
  });

  test('3: a deterministic seed produces a deterministic physique', () {
    final contextA = _newContext(7);
    final contextB = _newContext(7);

    final physiqueA =
        initializePhysique(contextA.entities.create(), contextA);
    final physiqueB =
        initializePhysique(contextB.entities.create(), contextB);

    expect(physiqueA, equals(physiqueB));
  });

  test('4: different seeds can produce different physiques', () {
    final results = <String>{};
    for (var seed = 1; seed <= 20; seed++) {
      final context = _newContext(seed);
      results.add(initializePhysique(context.entities.create(), context));
    }

    expect(results.length, greaterThan(1));
  });

  test('is idempotent: a character that already has a physique keeps it',
      () {
    final context = _newContext(1);
    final character = context.entities.create();

    final first = initializePhysique(character, context);
    final second = initializePhysique(character, context);

    expect(second, equals(first));
  });

  test("registers the assigned physique's synergy modifiers", () {
    final context = _newContext(1);
    final character = context.entities.create();

    final physiqueId = initializePhysique(character, context);
    final definition =
        physiqueDefinitionFromContent(context.content.get(physiqueId));

    // No tradition tag yet: neither conditional modifier is active.
    expect(
      context.modifiers.activeModifiersFor(
          character, definition.primaryAffinity, context.components),
      isEmpty,
    );

    // Granting both tradition tags proves both modifiers were
    // genuinely registered (not just structurally absent either way).
    context.components.add(character, TagSet({'western', 'eastern'}));
    expect(
      context.modifiers.activeModifiersFor(
          character, definition.primaryAffinity, context.components),
      hasLength(2),
    );
  });

  test('publishes PhysiqueAssigned', () {
    final context = _newContext(1);
    final character = context.entities.create();
    final published = <PhysiqueAssigned>[];
    context.events.subscribe<PhysiqueAssigned>(published.add);

    final physiqueId = initializePhysique(character, context);

    expect(published, hasLength(1));
    expect(published.single.character, equals(character));
    expect(published.single.physiqueId, equals(physiqueId));
  });

  test('publishes nothing on the idempotent second call', () {
    final context = _newContext(1);
    final character = context.entities.create();
    initializePhysique(character, context);

    final published = <PhysiqueAssigned>[];
    context.events.subscribe<PhysiqueAssigned>(published.add);
    initializePhysique(character, context);

    expect(published, isEmpty);
  });
}
```

- [ ] **Step 6: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes).

```bash
git add lib/src/plugins/physique/physique_events.dart \
  lib/src/plugins/physique/physique_initialization.dart \
  lib/physique_plugin.dart \
  test/plugins/physique/physique_events_test.dart \
  test/plugins/physique/physique_initialization_test.dart
git commit -m "feat: add PhysiqueAssigned event and initializePhysique"
```

---

### Task 4: `PhysiquePlugin`

**Files:**
- Create: `lib/src/plugins/physique/physique_plugin.dart`
- Modify: `lib/physique_plugin.dart`
- Test: `test/plugins/physique/physique_plugin_test.dart`

**Interfaces:**
- Consumes: `GamePlugin`, `PluginContext`, `PluginSdk`
  (`package:build_engine/build_engine.dart`); `PhysiqueComponent`,
  `physiqueContentDefinitions`, `PhysiqueTypes` (Tasks 1-2, via
  `package:build_engine/physique_plugin.dart`).
- Produces: `class PhysiquePlugin extends GamePlugin`.

- [ ] **Step 1: Write `physique_plugin.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'physique_component.dart';
import 'physique_content.dart';
import 'physique_types.dart';

/// Physique as an ordinary content plugin: four body-type definitions
/// (Sturdy/Power/Burst/Endurance), each with a primary affinity and a
/// pair of conditional synergy `Modifier`s, expressed entirely through
/// Core's public APIs. Depends on nothing but Core (`dependencies =>
/// const []`) — not Combat, not MartialArts. Interoperates with
/// MartialArts purely through the generic `'western'`/`'eastern'` tags
/// MartialArts' own `learnStyle` grants a character — see
/// `ARCHITECTURE.md`'s Physique section for the full design.
class PhysiquePlugin extends GamePlugin {
  @override
  String get id => 'physique';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can
  /// be `initialize`d again after `unregister`.
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);

    sdk.registerComponentCleanup<PhysiqueComponent>();

    sdk.registerTag('physique',
        description: 'Any physique-related entity or content.');
    sdk.registerTag('defense', description: "Sturdy's primary affinity.");
    sdk.registerTag('strength', description: "Power's primary affinity.");
    sdk.registerTag('speed', description: "Burst's primary affinity.");
    sdk.registerTag('stamina',
        description: "Endurance's primary affinity.");
    sdk.registerTag('western_affinity',
        description:
            'A physique with strong synergy against western martial traditions.');
    sdk.registerTag('eastern_affinity',
        description:
            'A physique with strong synergy against eastern martial traditions.');

    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find(PhysiqueTypes.sturdy) == null) {
      sdk.registerContentBatch(physiqueContentDefinitions);
    }
  }

  /// Mirrors [initialize]: cancels every subscription [sdk] took out —
  /// component cleanup — so an unregistered `PhysiquePlugin` stops
  /// reacting to events entirely.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
```

- [ ] **Step 2: Update `lib/physique_plugin.dart`**

```dart
/// Public API for PhysiquePlugin — a character's body type
/// (Sturdy/Power/Burst/Endurance). Depends on nothing but Core; never
/// imports MartialArtsPlugin or CombatPlugin. Import this, not
/// `lib/src/...` directly.
library;

export 'src/plugins/physique/physique_component.dart';
export 'src/plugins/physique/physique_content.dart';
export 'src/plugins/physique/physique_events.dart';
export 'src/plugins/physique/physique_initialization.dart';
export 'src/plugins/physique/physique_plugin.dart';
export 'src/plugins/physique/physique_types.dart';
```

- [ ] **Step 3: Write `physique_plugin_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
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
}

void main() {
  test('has id "physique", a version, and no dependencies', () {
    final plugin = PhysiquePlugin();
    expect(plugin.id, equals('physique'));
    expect(plugin.version, isNotEmpty);
    expect(plugin.dependencies, isEmpty);
  });

  test('initialize loads all 4 physique content definitions', () {
    final context = _newContext();
    PhysiquePlugin().initialize(context);

    expect(context.content.allOfType('physique'), hasLength(4));
    for (final id in PhysiqueTypes.all) {
      expect(context.content.get(id), isNotNull);
    }
  });

  test('removes PhysiqueComponent when its entity is destroyed', () {
    final context = _newContext();
    final plugin = PhysiquePlugin();
    plugin.initialize(context);

    final character = context.entities.create();
    initializePhysique(character, context);
    expect(context.components.has<PhysiqueComponent>(character), isTrue);

    context.entities.destroy(character);

    expect(context.components.has<PhysiqueComponent>(character), isFalse);
  });

  test('component cleanup stops after unregister', () {
    final context = _newContext();
    final plugin = PhysiquePlugin();
    plugin.initialize(context);

    final character = context.entities.create();
    initializePhysique(character, context);

    plugin.unregister(context);
    context.entities.destroy(character);

    expect(context.components.has<PhysiqueComponent>(character), isTrue);
  });

  test('re-initializing on the same context does not throw '
      'ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = PhysiquePlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.allOfType('physique'), hasLength(4));
  });

  test('registers, initializes, starts, stops, and unregisters through '
      'PluginManager with no other plugin present', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(PhysiquePlugin());

    manager.initialize(context);
    manager.start(context);

    final character = context.entities.create();
    final physiqueId = initializePhysique(character, context);
    expect(PhysiqueTypes.all, contains(physiqueId));

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });
}
```

- [ ] **Step 4: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes).

```bash
git add lib/src/plugins/physique/physique_plugin.dart \
  lib/physique_plugin.dart \
  test/plugins/physique/physique_plugin_test.dart
git commit -m "feat: add PhysiquePlugin"
```

---

### Task 5: The one MartialArts touch — tradition tags in `learnStyle`

**Files:**
- Modify: `lib/src/plugins/martial_arts/martial_styles.dart`
- Modify: `test/plugins/martial_arts/martial_styles_test.dart`

**Interfaces:**
- Consumes: nothing new — `AddTag` and `context.ruleContextFor` are
  already imported/used in this file.
- Produces: `learnStyle` now additionally grants `'western'` (Boxing)
  or `'eastern'` (Shaolin, Tai Chi) to the entity.

- [ ] **Step 1: Update `martial_styles.dart`**

Replace the entire file with:

```dart
import 'package:build_engine/build_engine.dart';

import 'martial_vocabulary.dart';

/// The three martial styles this plugin's vertical slice implements. Not
/// components — a style is a marker tag (`style:<id>`) granted by
/// [learnStyle]. `martial` is granted alongside it so any future content
/// plugin can query "is this a martial-arts practitioner" without knowing
/// which specific style.
abstract final class MartialStyles {
  static const boxing = 'boxing';
  static const shaolin = 'shaolin';
  static const taiChi = 'taiChi';
}

/// Grants [entity] the `martial`, `style:$styleId`, and broad-tradition
/// (`'western'`/`'eastern'`) tags. The tradition tag is the one generic
/// interoperability hook another plugin (e.g. Physique) needs to react
/// to "which martial tradition is this character trained in" without
/// either plugin importing the other. It reuses vocabulary MartialArts
/// already owns: individual technique content
/// (`martial_technique_content.dart`) is already tagged
/// `'western'`/`'eastern'` per technique; this just makes the same fact
/// available on the entity itself.
///
/// Learning [MartialStyles.shaolin] additionally registers a permanent
/// conditional `Modifier` — `+4 add` to `palm`, active only while
/// `stance:iron_body` is present — implementing Shaolin's
/// defensive-synergy-into-offense mechanic entirely through the Modifier
/// Engine. This content-specific branch belongs here, in the content
/// plugin, not in Core or Combat.
void learnStyle(EntityId entity, String styleId, PluginContext context) {
  final ctx = context.ruleContextFor(entity);
  const AddTag('martial').apply(ctx);
  AddTag('style:$styleId').apply(ctx);
  AddTag(_traditionTagFor(styleId)).apply(ctx);
  if (styleId == MartialStyles.shaolin) {
    context.modifiers.add(Modifier(
      source: ModifierSource('style:shaolin:synergy:${entity.value}'),
      target: entity,
      stat: 'palm',
      operation: ModifierOperation.add,
      value: 4,
      condition: HasTagQuery(MartialStances.ironBody),
    ));
  }
}

/// The broad martial tradition [styleId] belongs to.
String _traditionTagFor(String styleId) => switch (styleId) {
      MartialStyles.boxing => 'western',
      MartialStyles.shaolin || MartialStyles.taiChi => 'eastern',
      _ => throw ArgumentError('unknown style id: $styleId'),
    };
```

- [ ] **Step 2: Extend `martial_styles_test.dart`**

Find the last test in the `group('learnStyle', ...)` block:

```dart
    test('style id constants have the expected values', () {
      expect(MartialStyles.boxing, equals('boxing'));
      expect(MartialStyles.shaolin, equals('shaolin'));
      expect(MartialStyles.taiChi, equals('taiChi'));
    });
  });
}
```

Insert a new test immediately before the closing `});` (i.e. still
inside the `group`, after the "style id constants" test):

```dart
    test('style id constants have the expected values', () {
      expect(MartialStyles.boxing, equals('boxing'));
      expect(MartialStyles.shaolin, equals('shaolin'));
      expect(MartialStyles.taiChi, equals('taiChi'));
    });

    test('grants the western tradition tag for boxing, eastern for '
        'shaolin and taiChi', () {
      final context = _newContext();
      final boxer = context.entities.create();
      final shaolinMonk = context.entities.create();
      final taiChiPractitioner = context.entities.create();

      learnStyle(boxer, MartialStyles.boxing, context);
      learnStyle(shaolinMonk, MartialStyles.shaolin, context);
      learnStyle(taiChiPractitioner, MartialStyles.taiChi, context);

      expect(
          context.components.get<TagSet>(boxer)!.tags, contains('western'));
      expect(context.components.get<TagSet>(boxer)!.tags,
          isNot(contains('eastern')));
      expect(context.components.get<TagSet>(shaolinMonk)!.tags,
          contains('eastern'));
      expect(context.components.get<TagSet>(shaolinMonk)!.tags,
          isNot(contains('western')));
      expect(context.components.get<TagSet>(taiChiPractitioner)!.tags,
          contains('eastern'));
      expect(context.components.get<TagSet>(taiChiPractitioner)!.tags,
          isNot(contains('western')));
    });
  });
}
```

- [ ] **Step 3: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes, including every pre-existing MartialArts test — run `dart
test test/plugins/martial_arts/ test/integration/martial_arts_end_to_end_test.dart`
specifically to confirm nothing there regressed).

```bash
git add lib/src/plugins/martial_arts/martial_styles.dart \
  test/plugins/martial_arts/martial_styles_test.dart
git commit -m "feat: grant western/eastern tradition tags in learnStyle"
```

---

### Task 6: Cross-plugin synergy tests and dependency-governance extension

**Files:**
- Create: `test/integration/physique_synergy_test.dart`
- Modify: `test/integration/architecture_dependency_test.dart`

**Interfaces:**
- Consumes: `PhysiquePlugin`, `PhysiqueTypes`, `PhysiqueComponent`,
  `initializePhysique`, `physiqueDefinitionFromContent`
  (`package:build_engine/physique_plugin.dart`); `MartialArtsPlugin`,
  `learnStyle`, `MartialStyles` (`package:build_engine/martial_arts_plugin.dart`);
  `CombatPlugin` (`package:build_engine/combat_plugin.dart`); Core
  services (`package:build_engine/build_engine.dart`) — all pre-existing.

- [ ] **Step 1: Write `physique_synergy_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:build_engine/physique_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
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
}

void main() {
  test('5: PhysiquePlugin works without MartialArtsPlugin', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(PhysiquePlugin());
    manager.initialize(context);
    manager.start(context);

    final character = context.entities.create();
    final physiqueId = initializePhysique(character, context);

    expect(PhysiqueTypes.all, contains(physiqueId));
    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test('6: MartialArtsPlugin works without PhysiquePlugin', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(CombatPlugin());
    manager.register(MartialArtsPlugin());
    manager.initialize(context);
    manager.start(context);

    final entity = context.entities.create();
    learnStyle(entity, MartialStyles.boxing, context);

    expect(
        context.components.get<TagSet>(entity)!.tags, contains('western'));
    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test('7: both plugins can coexist', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(CombatPlugin());
    manager.register(MartialArtsPlugin());
    manager.register(PhysiquePlugin());
    manager.initialize(context);
    manager.start(context);

    final character = context.entities.create();
    learnStyle(character, MartialStyles.boxing, context);
    final physiqueId = initializePhysique(character, context);

    expect(PhysiqueTypes.all, contains(physiqueId));
    expect(context.components.get<TagSet>(character)!.tags,
        contains('western'));
    expect(context.components.get<PhysiqueComponent>(character)!.physiqueId,
        equals(physiqueId));

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  group('8 & 9: Sturdy/Power synergy with western/eastern traditions', () {
    for (final physiqueId in [PhysiqueTypes.sturdy, PhysiqueTypes.power]) {
      test('$physiqueId: western synergy is 1.25x, eastern is 0.85x', () {
        final context = _newContext();
        PhysiquePlugin().initialize(context);
        final definition =
            physiqueDefinitionFromContent(context.content.get(physiqueId));

        final westernCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(westernCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(westernCharacter, MartialStyles.boxing, context);
        final westernResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(westernCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(westernResolved, equals(125));

        final easternCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(easternCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(easternCharacter, MartialStyles.shaolin, context);
        final easternResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(easternCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(easternResolved, equals(85));
      });
    }
  });

  group('10 & 11: Burst/Endurance synergy with eastern/western traditions',
      () {
    for (final physiqueId in [PhysiqueTypes.burst, PhysiqueTypes.endurance]) {
      test('$physiqueId: eastern synergy is 1.25x, western is 0.85x', () {
        final context = _newContext();
        PhysiquePlugin().initialize(context);
        final definition =
            physiqueDefinitionFromContent(context.content.get(physiqueId));

        final easternCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(easternCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(easternCharacter, MartialStyles.taiChi, context);
        final easternResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(easternCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(easternResolved, equals(125));

        final westernCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(westernCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(westernCharacter, MartialStyles.boxing, context);
        final westernResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(westernCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(westernResolved, equals(85));
      });
    }
  });

  test('neutral: no martial style learned means no synergy modifier '
      'applies', () {
    final context = _newContext();
    PhysiquePlugin().initialize(context);
    final definition =
        physiqueDefinitionFromContent(context.content.get(PhysiqueTypes.sturdy));

    final character = context.entities.create();
    for (final modifier in definition.modifiersFor(character)) {
      context.modifiers.add(modifier);
    }

    final resolved = const ModifierResolver().resolve(
      100,
      context.modifiers
          .activeModifiersFor(character, definition.primaryAffinity, context.components),
    );
    expect(resolved, equals(100));
  });
}
```

- [ ] **Step 2: Extend `architecture_dependency_test.dart` (scenario 12)**

Find:

```dart
const _combatBarrel = 'combat_plugin.dart';
const _martialArtsBarrel = 'martial_arts_plugin.dart';
const _elementalBarrel = 'elemental_plugin.dart';
const _pluginBarrels = [_combatBarrel, _martialArtsBarrel, _elementalBarrel];
```

Replace with:

```dart
const _combatBarrel = 'combat_plugin.dart';
const _martialArtsBarrel = 'martial_arts_plugin.dart';
const _elementalBarrel = 'elemental_plugin.dart';
const _physiqueBarrel = 'physique_plugin.dart';
const _pluginBarrels = [
  _combatBarrel,
  _martialArtsBarrel,
  _elementalBarrel,
  _physiqueBarrel,
];
```

Find:

```dart
  group('Combat remains unaware of both content plugins', () {
    test('Combat does not reference MartialArts', () {
      _assertNoPluginImport(
          'martial_arts', _martialArtsBarrel, 'lib/src/plugins/combat');
    });

    test('Combat does not reference Elemental', () {
      _assertNoPluginImport(
          'elemental', _elementalBarrel, 'lib/src/plugins/combat');
    });
  });
```

Replace with (adds a new MartialArts↔Physique group, and extends the
Combat group with a Physique check):

```dart
  group('MartialArts and Physique do not import each other', () {
    test('MartialArts does not reference Physique', () {
      _assertNoPluginImport(
          'physique', _physiqueBarrel, 'lib/src/plugins/martial_arts');
    });

    test('Physique does not reference MartialArts', () {
      _assertNoPluginImport('martial_arts', _martialArtsBarrel,
          'lib/src/plugins/physique');
    });
  });

  group('Combat remains unaware of both content plugins', () {
    test('Combat does not reference MartialArts', () {
      _assertNoPluginImport(
          'martial_arts', _martialArtsBarrel, 'lib/src/plugins/combat');
    });

    test('Combat does not reference Elemental', () {
      _assertNoPluginImport(
          'elemental', _elementalBarrel, 'lib/src/plugins/combat');
    });

    test('Combat does not reference Physique', () {
      _assertNoPluginImport(
          'physique', _physiqueBarrel, 'lib/src/plugins/combat');
    });
  });
```

(`_pluginBarrels` now including `_physiqueBarrel` also automatically
extends group H's per-core-directory checks to cover Physique, with no
further edit needed there.)

- [ ] **Step 3: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes — run `dart test test/integration/` specifically first to
confirm the new and extended integration tests pass, then the full
suite).

```bash
git add test/integration/physique_synergy_test.dart \
  test/integration/architecture_dependency_test.dart
git commit -m "test: prove Physique/MartialArts coexistence, synergy math, and non-dependency"
```

---

### Task 7: Documentation

**Files:**
- Modify: `ARCHITECTURE.md`
- Modify: `PLUGIN_SYSTEM.md`

- [ ] **Step 1: Append a Physique section to `ARCHITECTURE.md`**

Append, at the end of the file:

```markdown
## Physique (`lib/src/plugins/physique/`, `lib/physique_plugin.dart`)

A character's body type — Sturdy/Power/Burst/Endurance — the second
independent content plugin depending on nothing but Core (after
Elemental), and the first plugin built with a real cross-plugin
mechanic as a first-class design goal from the start, rather than
retrofitted onto an existing example.

**Runtime component.** `PhysiqueComponent` holds only the stable
physique id — no tags, no affinity, no modifiers duplicated onto it.
Everything else is data, resolved from `ContentRegistry` when needed.

**Data definition.** `physiqueContentDefinitions` (`physique_content.dart`)
loads through `ContentRegistry` exactly like Elemental's spells and
MartialArts' migrated techniques. `modifiers`/`affinities` aren't part
of `ContentRegistry`'s native vocabulary (`Modifier` isn't an `Effect`/
`Condition`) — they land in `ContentDefinition.extra` verbatim, and
`physiqueDefinitionFromContent` turns that into a typed
`PhysiqueDefinition` whose `modifiersFor(character)` builds real
`Modifier` objects, mirroring `martialTechniqueFromDefinition`'s
`baseDamage`/`damageStat` pattern exactly.

**Random assignment.** `initializePhysique(character, context)` — a
plain function, not a `Rule` on `EntityCreated` (not every entity is a
character, so creation alone can't say when to run this) — is
idempotent (returns the existing id if the character already has a
`PhysiqueComponent`), selects uniformly via `context.rng.nextInt(4)`
(never `dart:math` directly, so a run stays reproducible from its
seed), attaches the component, registers the physique's two synergy
`Modifier`s, and publishes `PhysiqueAssigned`. Matches
`learnStyle`/`attuneToElement`/`equipItem`'s existing "explicit
function, caller decides when" idiom — no game-specific
`NewGameManager` needed; whoever creates a character calls this.

**Tag model.** Each physique's content carries descriptive tags
(`physique`, its primary-affinity name, `western_affinity`/
`eastern_affinity`) — metadata, not read by any condition, the same
role `MartialTechniqueAction.tags` already plays. The tags that
actually drive synergy are different: `'western'`/`'eastern'`, granted
on the *character entity* by MartialArts' `learnStyle`. Physique never
inspects a physique's own descriptive tags to decide anything.

**Synergy model.** Each physique registers two conditional `Modifier`s
targeting its primary-affinity stat (`defense`/`strength`/`speed`/
`stamina` — an arbitrary, caller-chosen name exactly like `damageStat`):
`×1.25` gated on `HasTagQuery('western')` or `HasTagQuery('eastern')`
(whichever tradition that physique favors), `×0.85` gated on the other.
No explicit "neutral ×1.00" modifier exists — `ModifierResolver`
already treats an empty active-modifier set as the identity, so an
entity with neither tradition tag is neutral for free. This is the same
mechanism Shaolin's own iron-body synergy proved, and the same one
`ElementalPlugin`'s `emberCharm` proved again across a different plugin
pair — Physique is the third independent proof of the identical
pattern.

**The one MartialArts touch.** `learnStyle` now also grants a broad
tradition tag — `'western'` for Boxing, `'eastern'` for Shaolin and Tai
Chi — reusing vocabulary MartialArts' own technique content
(`martial_technique_content.dart`) already uses per-technique. This is
the single line Physique's synergy needs to have anything to check on
the character; it adds no Physique-specific vocabulary to MartialArts
(Physique is never named), and any future plugin can read the same two
tags.

**Dependency direction.** `PhysiquePlugin.dependencies => const []` —
Core only. No file under `lib/src/plugins/physique/` references
`martial_arts`/`combat`/`elemental`; no file under
`lib/src/plugins/martial_arts/` or `lib/src/plugins/combat/` references
`physique`. `test/integration/architecture_dependency_test.dart` — the
automated dependency-governance test built in the prior
cross-plugin-interop pass — now checks Physique in both directions
against MartialArts and Combat, alongside its existing Elemental
checks, making this a permanent, CI-enforceable property.
```

- [ ] **Step 2: Add a Physique section to `PLUGIN_SYSTEM.md`**

Insert after the existing "Writing a third-party plugin" section
(before "Plugins must not reach into each other's private
implementation"):

```markdown
## A second worked example: Physique and generic interop

`PhysiquePlugin` (`lib/src/plugins/physique/`) is a second full example
alongside `ElementalPlugin`, chosen specifically to demonstrate
cross-plugin interoperability without a shared import — worth reading
once you've built your first plugin from the "Writing a third-party
plugin" steps above.

- **Custom content fields via `extra`.** `ContentRegistry` has no
  native vocabulary for arbitrary data like `Modifier`s — Physique's
  `modifiers`/`affinities` fields land on `ContentDefinition.extra`
  verbatim, and a small parser (`physiqueDefinitionFromContent`) turns
  that into real, typed objects. Any plugin with data `ContentRegistry`
  doesn't natively understand can use the same trick.
- **Cross-plugin synergy needs no shared import — only a shared
  vocabulary.** Physique never imports MartialArts. Its `emberCharm`-
  style mechanic here is a conditional `Modifier` gated on a tag name
  (`'western'`/`'eastern'`) that MartialArts happens to grant. Two
  plugins that agree on a tag string, a stat name, or an event type
  can interoperate with zero coupling in either direction — this is
  the whole reason `claude.md`'s TAGS section calls tags "the universal
  language for content interoperability."
- **A generic interoperability hook is not the same as
  plugin-specific logic.** MartialArts needed one addition —
  `learnStyle` granting a `'western'`/`'eastern'` tradition tag — for
  Physique's synergy to have anything to check. That tag names no
  other plugin and serves any future consumer, which is what makes it
  a generic hook rather than an exception to "plugins don't know about
  each other."
- **A generic initialization function, not a `Rule` on
  `EntityCreated`.** `initializePhysique` is explicit and idempotent,
  called by whoever creates a character — not every entity is a
  character, so entity creation alone can't decide this. See
  `ARCHITECTURE.md`'s Physique section for the full design.
```

- [ ] **Step 3: Commit**

```bash
git add ARCHITECTURE.md PLUGIN_SYSTEM.md
git commit -m "docs: document the Physique plugin"
```
