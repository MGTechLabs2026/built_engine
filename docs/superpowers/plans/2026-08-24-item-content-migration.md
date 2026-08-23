# Item Content Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate MartialArts' 8 items/trinkets and Elemental's 1 item
from hardcoded Dart `const` object literals to `ContentRegistry`-loaded
data, closing `ARCHITECTURE_AUDIT.md`'s Finding #7, with zero behavior
change (every existing test's assertions are preserved, only how each
test obtains the item object changes).

**Architecture:** Each plugin gets its own `*_item_content.dart` file:
JSON-shaped `const` definitions (`'modifiers'` a list of `{stat,
operation, value, condition?}` maps, `condition` optional and
`modifiers` possibly empty), a `*ItemDefinitionFromContent(ContentDefinition)`
parser (mirrors `physiqueDefinitionFromContent`), and a thin
`*Item(id, context)` resolver used at every call site instead of the old
bare `const` identifier. `equipItem`/`equipElementalItem` and the
`MartialItemDefinition`/`ElementalItemDefinition` classes themselves do
not change. New `MartialItemIds`/`ElementalItemIds` constant classes
replace `martial_arts_rules.dart`'s `momentumTrinket.id`/`qiPendant.id`
reads.

**Tech Stack:** Dart `^3.7.0`, `package:test`, package `build_engine`.

**Spec:** `docs/superpowers/specs/2026-08-24-item-content-migration-design.md`

## Global Constraints

- Only these files' *content* migrates: MartialArts' 5 items + 3
  trinkets (`martial_item.dart`), Elemental's 1 item
  (`elemental_item.dart`). No other plugin, no `MartialTechniqueAction`,
  no `MartialStyles`/`Elements`/`PhysiqueTypes`, no Combat file.
- `MartialItemDefinition`/`ElementalItemDefinition` classes and
  `equipItem`/`equipElementalItem` functions keep their exact current
  signatures and behavior — only how a definition is *obtained* changes.
- No caching/global state in the new `*Item(id, context)` resolvers —
  each call re-resolves from `context.content`, exactly like
  `physiqueDefinitionFromContent` is called fresh each time.
- `condition` on a parsed `Modifier` must be `null` (not a stray
  `HasTagQuery`) when the raw JSON entry has no `'condition'` key.
- No change to `PluginSdk`, `ContentRegistry`, `Modifier`,
  `ModifierResolver`, or any Combat file.
- Every existing test's assertions (expected values, expected tag sets,
  expected modifier counts) must be preserved exactly — only the
  mechanism for obtaining the item object changes.
- Run `dart analyze` and the full `dart test` suite after every task;
  both must stay clean/green, **except** where a task's own instructions
  explicitly say a specific test file is expected to fail until a later
  task lands (see Task 3 and Task 5's notes — mirrors the same
  circular-test-dependency shape the Physique plugin plan hit, and is
  handled the same way: production code + its dependent tests land
  together in one task).

---

### Task 1: `MartialItemIds` and `ElementalItemIds`

**Files:**
- Modify: `lib/src/plugins/martial_arts/martial_vocabulary.dart`
- Modify: `lib/src/plugins/elemental/elemental_vocabulary.dart`
- Test: `test/plugins/martial_arts/martial_vocabulary_test.dart`
- Test: `test/plugins/elemental/elemental_vocabulary_test.dart`

- [ ] **Step 1: Append to `martial_vocabulary.dart`**

The file currently ends with `MartialStances`'s closing `}`. Append, at
the end of the file:

```dart

/// Stable content ids for MartialArts' items/trinkets
/// (`martial_item_content.dart`) — referenced by content definitions,
/// `martial_arts_rules.dart`'s passive-regen rules (`.momentumTrinket`/
/// `.qiPendant`), and by `martialItem(id, context)` call sites, so a
/// rename here propagates everywhere instead of silently breaking a
/// second, independently-typed string literal.
abstract final class MartialItemIds {
  static const brassKnuckles = 'brass_knuckles';
  static const ironPalmWraps = 'iron_palm_wraps';
  static const taiChiSilkSash = 'tai_chi_silk_sash';
  static const sparringGloves = 'sparring_gloves';
  static const weightedVest = 'weighted_vest';
  static const momentumTrinket = 'momentum_trinket';
  static const qiPendant = 'qi_pendant';
  static const counterstrikeRing = 'counterstrike_ring';
}
```

- [ ] **Step 2: Append to `elemental_vocabulary.dart`**

The file currently ends with `ElementalStatuses`'s closing `}`. Append,
at the end of the file:

```dart

/// Stable content ids for Elemental's items
/// (`elemental_item_content.dart`) — same rationale as
/// `MartialItemIds` above.
abstract final class ElementalItemIds {
  static const emberCharm = 'ember_charm';
}
```

- [ ] **Step 3: Extend `martial_vocabulary_test.dart`**

Find:

```dart
  test('MartialStances names the three MartialArts stance tags', () {
    expect(MartialStances.guard, equals('stance:guard'));
    expect(MartialStances.ironBody, equals('stance:iron_body'));
    expect(MartialStances.taiChi, equals('stance:tai_chi'));
  });
}
```

Replace with:

```dart
  test('MartialStances names the three MartialArts stance tags', () {
    expect(MartialStances.guard, equals('stance:guard'));
    expect(MartialStances.ironBody, equals('stance:iron_body'));
    expect(MartialStances.taiChi, equals('stance:tai_chi'));
  });

  test('MartialItemIds names all 8 items/trinkets', () {
    expect(MartialItemIds.brassKnuckles, equals('brass_knuckles'));
    expect(MartialItemIds.ironPalmWraps, equals('iron_palm_wraps'));
    expect(MartialItemIds.taiChiSilkSash, equals('tai_chi_silk_sash'));
    expect(MartialItemIds.sparringGloves, equals('sparring_gloves'));
    expect(MartialItemIds.weightedVest, equals('weighted_vest'));
    expect(MartialItemIds.momentumTrinket, equals('momentum_trinket'));
    expect(MartialItemIds.qiPendant, equals('qi_pendant'));
    expect(MartialItemIds.counterstrikeRing, equals('counterstrike_ring'));
  });
}
```

- [ ] **Step 4: Extend `elemental_vocabulary_test.dart`**

Read the file first (it mirrors `martial_vocabulary_test.dart`'s shape —
one `test(...)` per constants class, ending with a closing `}`). Insert a
new test, following the same style as the file's existing tests, after
the last existing test and before the file's closing `}`:

```dart
  test('ElementalItemIds names the one Elemental item', () {
    expect(ElementalItemIds.emberCharm, equals('ember_charm'));
  });
```

- [ ] **Step 5: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes).

```bash
git add lib/src/plugins/martial_arts/martial_vocabulary.dart \
  lib/src/plugins/elemental/elemental_vocabulary.dart \
  test/plugins/martial_arts/martial_vocabulary_test.dart \
  test/plugins/elemental/elemental_vocabulary_test.dart
git commit -m "feat: add MartialItemIds and ElementalItemIds constants"
```

---

### Task 2: `martial_item_content.dart` (content + parser + resolver)

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_item_content.dart`
- Test: `test/plugins/martial_arts/martial_item_content_test.dart`

**Interfaces:**
- Consumes: `ContentDefinition`, `ContentRegistry`, `Modifier`,
  `ModifierOperation`, `ModifierSource`, `HasTagQuery`, `EntityId`,
  `PluginContext` (`package:build_engine/build_engine.dart`);
  `MartialItemDefinition` (same-directory `martial_item.dart`);
  `MartialItemIds`, `MartialStances` (same-directory
  `martial_vocabulary.dart`, Task 1).
- Produces: `const martialItemContentDefinitions`,
  `MartialItemDefinition martialItemDefinitionFromContent(ContentDefinition
  definition)`, `MartialItemDefinition martialItem(String id,
  PluginContext context)`.

- [ ] **Step 1: Write `martial_item_content.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'martial_item.dart';
import 'martial_vocabulary.dart';

/// The 5 items + 3 trinkets this plugin implements, as data — loaded
/// into `PluginContext.content` via `PluginSdk.registerContentBatch` in
/// `MartialArtsPlugin.initialize`, mirroring
/// `martialTechniqueContentDefinitions` and
/// `physiqueContentDefinitions`.
///
/// `modifiers` isn't part of `ContentRegistry`'s native vocabulary
/// (`Modifier` isn't an `Effect`/`Condition`) — it lands verbatim on
/// `ContentDefinition.extra`, exactly like
/// `physique_content.dart`'s `modifiers` field.
/// `physiqueDefinitionFromContent` always required a `'condition'` key
/// (every physique's modifiers are tag-gated); items are less uniform —
/// most have an unconditional modifier (no `'condition'` key at all),
/// and two trinkets (`momentum_trinket`/`qi_pendant`) have no static
/// modifiers whatsoever (their behavior comes entirely from the
/// `equipped:<id>` tag `equipItem` grants, read by
/// `martial_arts_rules.dart`'s passive-regen rules) — so both
/// `'condition'` and a non-empty `'modifiers'` list are optional here.
const martialItemContentDefinitions = <Map<String, dynamic>>[
  {
    'id': MartialItemIds.brassKnuckles,
    'type': 'martial_item',
    'tags': ['martial', 'fist', 'western'],
    'modifiers': [
      {'stat': 'punch', 'operation': 'add', 'value': 6},
    ],
  },
  {
    'id': MartialItemIds.ironPalmWraps,
    'type': 'martial_item',
    'tags': ['martial', 'palm', 'eastern'],
    'modifiers': [
      {'stat': 'palm', 'operation': 'add', 'value': 6},
    ],
  },
  {
    'id': MartialItemIds.taiChiSilkSash,
    'type': 'martial_item',
    'tags': ['martial', 'internal', 'eastern', 'qi'],
    'modifiers': [
      {'stat': 'internal', 'operation': 'add', 'value': 5},
    ],
  },
  {
    'id': MartialItemIds.sparringGloves,
    'type': 'martial_item',
    'tags': ['martial', 'fist', 'western'],
    'modifiers': [
      {'stat': 'punch', 'operation': 'add', 'value': 3},
    ],
  },
  {
    'id': MartialItemIds.weightedVest,
    'type': 'martial_item',
    'tags': ['martial', 'fist', 'western', 'external'],
    'modifiers': [
      {'stat': 'punch', 'operation': 'multiply', 'value': 1.1},
    ],
  },
  {
    'id': MartialItemIds.momentumTrinket,
    'type': 'martial_trinket',
    'tags': ['martial', 'western'],
    'modifiers': <Map<String, dynamic>>[],
  },
  {
    'id': MartialItemIds.qiPendant,
    'type': 'martial_trinket',
    'tags': ['martial', 'qi', 'eastern'],
    'modifiers': <Map<String, dynamic>>[],
  },
  {
    'id': MartialItemIds.counterstrikeRing,
    'type': 'martial_trinket',
    'tags': ['martial', 'eastern', 'counter'],
    'modifiers': [
      {
        'stat': 'internal',
        'operation': 'add',
        'value': 3,
        'condition': MartialStances.taiChi,
      },
    ],
  },
];

/// Builds a [MartialItemDefinition] from a loaded [ContentDefinition].
/// `extra['modifiers']` supplies [MartialItemDefinition.modifiersFor] —
/// each raw entry becomes one `Modifier`, unconditional unless the entry
/// has a `'condition'` key (in which case it's gated via `HasTagQuery`).
/// An empty `extra['modifiers']` list produces a `modifiersFor` that
/// always returns `const []` — the same behavior
/// `MartialItemDefinition`'s own `_noModifiers` default already
/// provides for a definition with no `modifiersFor` at all.
MartialItemDefinition martialItemDefinitionFromContent(
    ContentDefinition definition) {
  final rawModifiers = (definition.extra['modifiers'] as List)
      .map((e) => (e as Map).map((k, v) => MapEntry(k as String, v)))
      .toList();

  List<Modifier> modifiersFor(EntityId wearer) => [
        for (var i = 0; i < rawModifiers.length; i++)
          Modifier(
            source:
                ModifierSource('item:${definition.id}:$i:${wearer.value}'),
            target: wearer,
            stat: rawModifiers[i]['stat'] as String,
            operation: _operationFor(rawModifiers[i]['operation'] as String),
            value: rawModifiers[i]['value'] as num,
            condition: rawModifiers[i].containsKey('condition')
                ? HasTagQuery(rawModifiers[i]['condition'] as String)
                : null,
          ),
      ];

  return MartialItemDefinition(
    id: definition.id,
    tags: definition.tags,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses item [id] from [context]'s loaded content in one
/// call — the replacement for the old bare `const` item identifiers
/// (`brassKnuckles`, etc.) everywhere they were previously referenced.
/// Stateless: re-resolves from `context.content` on every call, no
/// caching.
MartialItemDefinition martialItem(String id, PluginContext context) =>
    martialItemDefinitionFromContent(context.content.get(id));

ModifierOperation _operationFor(String name) => switch (name) {
      'add' => ModifierOperation.add,
      'multiply' => ModifierOperation.multiply,
      'override' => ModifierOperation.override,
      'min' => ModifierOperation.min,
      'max' => ModifierOperation.max,
      _ => throw ArgumentError('unknown modifier operation: $name'),
    };
```

- [ ] **Step 2: Write `martial_item_content_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('all 8 item/trinket definitions load atomically as a batch', () {
    final registry = ContentRegistry();
    final definitions = registry.loadAll(martialItemContentDefinitions);
    expect(definitions, hasLength(8));
    expect(registry.allOfType('martial_item'), hasLength(5));
    expect(registry.allOfType('martial_trinket'), hasLength(3));
  });

  group('martialItemDefinitionFromContent', () {
    test('parses an item with a single unconditional modifier', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.brassKnuckles));

      expect(definition.id, equals('brass_knuckles'));
      expect(definition.tags, equals({'martial', 'fist', 'western'}));

      final wearer = const EntityId(1);
      final modifiers = definition.modifiersFor(wearer);
      expect(modifiers, hasLength(1));
      expect(modifiers.single.target, equals(wearer));
      expect(modifiers.single.stat, equals('punch'));
      expect(modifiers.single.operation, equals(ModifierOperation.add));
      expect(modifiers.single.value, equals(6));
      expect(modifiers.single.condition, isNull);
    });

    test('parses a trinket with an empty modifiers list', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.momentumTrinket));

      expect(definition.modifiersFor(const EntityId(1)), isEmpty);
    });

    test('parses a conditional modifier gated by a tag', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.counterstrikeRing));

      final modifiers = definition.modifiersFor(const EntityId(1));
      expect(modifiers, hasLength(1));
      expect(modifiers.single.condition, isNotNull);
      expect(modifiers.single.stat, equals('internal'));
      expect(modifiers.single.value, equals(3));
    });

    test('parses a multiply-operation modifier', () {
      final registry = ContentRegistry();
      registry.loadAll(martialItemContentDefinitions);
      final definition = martialItemDefinitionFromContent(
          registry.get(MartialItemIds.weightedVest));

      final modifiers = definition.modifiersFor(const EntityId(1));
      expect(modifiers.single.operation, equals(ModifierOperation.multiply));
      expect(modifiers.single.value, equals(1.1));
    });
  });

  test('martialItem resolves and parses in one call', () {
    final registry = ContentRegistry();
    registry.loadAll(martialItemContentDefinitions);
    final context = PluginContext(
      entities: EntityRegistry(EventBus()),
      components: ComponentStore(),
      events: EventBus(),
      rng: RngService(1),
      rules: RuleEngine(
        entities: EntityRegistry(EventBus()),
        components: ComponentStore(),
        events: EventBus(),
        rng: RngService(1),
      ),
      queries: QueryEngine(QueryScope(components: ComponentStore())),
      modifiers: ModifierCollection(),
      content: registry,
    );

    final definition = martialItem(MartialItemIds.ironPalmWraps, context);
    expect(definition.id, equals('iron_palm_wraps'));
  });
}
```

- [ ] **Step 3: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes — this file doesn't yet touch `martial_item.dart`,
`martial_arts_plugin.dart`, or any existing test, so nothing else should
change).

```bash
git add lib/src/plugins/martial_arts/martial_item_content.dart \
  test/plugins/martial_arts/martial_item_content_test.dart
git commit -m "feat: add martial_item_content.dart (data + parser + resolver)"
```

---

### Task 3: Wire MartialArts items into `ContentRegistry` + update all MartialArts call sites

This task lands `martial_item.dart`'s trim-down, `martial_arts_plugin.dart`'s
registration, `martial_arts_rules.dart`'s id-constant switch, the barrel
export, AND the 3 affected test files together — in that order — because
none of the 3 test files can pass until the production wiring exists
(mirrors the same shape of interdependency the Physique plugin's Task 3+4
combination hit; see that plan's ledger if available for precedent). Do
not split this into smaller commits that leave tests red.

**Files:**
- Modify: `lib/src/plugins/martial_arts/martial_item.dart`
- Modify: `lib/src/plugins/martial_arts/martial_arts_plugin.dart`
- Modify: `lib/src/plugins/martial_arts/martial_arts_rules.dart`
- Modify: `lib/martial_arts_plugin.dart`
- Modify: `test/plugins/martial_arts/martial_item_test.dart`
- Modify: `test/plugins/martial_arts/martial_arts_plugin_test.dart`
- Modify: `test/integration/martial_arts_end_to_end_test.dart`

- [ ] **Step 1: Replace `martial_item.dart`**

Replace the entire file with:

```dart
import 'package:build_engine/build_engine.dart';

import 'martial_loadout_component.dart';

/// A wearable item or trinket. Trinkets are simply items whose behavior
/// comes from a `Rule` reacting to their `equipped:<id>` tag (see
/// `martial_arts_rules.dart`) rather than from [modifiersFor] — one class
/// covers both, matching CLAUDE.md's "don't create a new source-code
/// class for every individual item" guidance. Instances are built from
/// loaded content via `martialItemDefinitionFromContent`/`martialItem`
/// (`martial_item_content.dart`), never hand-written here.
class MartialItemDefinition {
  const MartialItemDefinition({
    required this.id,
    required this.tags,
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final Set<String> tags;
  final List<Modifier> Function(EntityId wearer) modifiersFor;

  static List<Modifier> _noModifiers(EntityId wearer) => const [];
}

/// Creates an entity for [item] (carrying its tags), registers its
/// [MartialItemDefinition.modifiersFor] against [wearer], tags [wearer]
/// `equipped:<item.id>`, and records the new item entity on [wearer]'s
/// `MartialLoadoutComponent` (creating it if absent). Returns the new item
/// entity.
EntityId equipItem(
  MartialItemDefinition item,
  EntityId wearer,
  PluginContext context,
) {
  final itemEntity = context.entities.create();
  context.components.add(itemEntity, TagSet(item.tags));
  for (final modifier in item.modifiersFor(wearer)) {
    context.modifiers.add(modifier);
  }
  AddTag('equipped:${item.id}').apply(context.ruleContextFor(wearer));
  final loadout = context.components.get<MartialLoadoutComponent>(wearer);
  context.components.add(
    wearer,
    MartialLoadoutComponent(
      equippedItems: [...?loadout?.equippedItems, itemEntity],
    ),
  );
  return itemEntity;
}
```

- [ ] **Step 2: Update `martial_arts_plugin.dart`**

Find:

```dart
import 'package:build_engine/build_engine.dart';

import 'martial_arts_rules.dart';
import 'martial_loadout_component.dart';
import 'martial_technique_content.dart';
```

Replace with:

```dart
import 'package:build_engine/build_engine.dart';

import 'martial_arts_rules.dart';
import 'martial_item_content.dart';
import 'martial_loadout_component.dart';
import 'martial_technique_content.dart';
import 'martial_vocabulary.dart';
```

Find:

```dart
    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find('jab') == null) {
      sdk.registerContentBatch(martialTechniqueContentDefinitions);
    }
  }
```

Replace with:

```dart
    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find('jab') == null) {
      sdk.registerContentBatch(martialTechniqueContentDefinitions);
    }
    if (context.content.find(MartialItemIds.brassKnuckles) == null) {
      sdk.registerContentBatch(martialItemContentDefinitions);
    }
  }
```

- [ ] **Step 3: Update `martial_arts_rules.dart`**

Find:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'martial_conditions.dart';
import 'martial_item.dart';
import 'martial_vocabulary.dart';
```

Replace with:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'martial_conditions.dart';
import 'martial_vocabulary.dart';
```

(`martial_item.dart` is no longer imported directly — `.id` is no longer
read off a `MartialItemDefinition` instance here.)

Find:

```dart
      _passiveResourceRegenRule(
        requiresTag: 'equipped:${momentumTrinket.id}',
        resource: MartialResources.momentum,
        amount: 3,
      ),
      _passiveResourceRegenRule(
        requiresTag: 'equipped:${qiPendant.id}',
        resource: MartialResources.qi,
        amount: 2,
      ),
```

Replace with:

```dart
      _passiveResourceRegenRule(
        requiresTag: 'equipped:${MartialItemIds.momentumTrinket}',
        resource: MartialResources.momentum,
        amount: 3,
      ),
      _passiveResourceRegenRule(
        requiresTag: 'equipped:${MartialItemIds.qiPendant}',
        resource: MartialResources.qi,
        amount: 2,
      ),
```

Also update the doc comment above `buildMartialArtsRules()` — find:

```dart
/// The two `_passiveResourceRegenRule` calls read their target trinket's
/// `.id` directly (`momentumTrinket.id`/`qiPendant.id`) rather than a
/// second, independently-typed `'momentum_trinket'`/`'qi_pendant'`
/// literal — a renamed trinket id would otherwise silently break the
/// rule that's supposed to react to it (`ARCHITECTURE_AUDIT.md`'s
/// observation B).
```

Replace with:

```dart
/// The two `_passiveResourceRegenRule` calls read
/// `MartialItemIds.momentumTrinket`/`MartialItemIds.qiPendant` rather
/// than a second, independently-typed `'momentum_trinket'`/`'qi_pendant'`
/// literal — a renamed trinket id would otherwise silently break the
/// rule that's supposed to react to it (`ARCHITECTURE_AUDIT.md`'s
/// observation B).
```

- [ ] **Step 4: Update `lib/martial_arts_plugin.dart`**

Find:

```dart
export 'src/plugins/martial_arts/martial_arts_plugin.dart';
export 'src/plugins/martial_arts/martial_arts_rules.dart';
export 'src/plugins/martial_arts/martial_conditions.dart';
export 'src/plugins/martial_arts/martial_item.dart';
export 'src/plugins/martial_arts/martial_loadout_component.dart';
```

Replace with:

```dart
export 'src/plugins/martial_arts/martial_arts_plugin.dart';
export 'src/plugins/martial_arts/martial_arts_rules.dart';
export 'src/plugins/martial_arts/martial_conditions.dart';
export 'src/plugins/martial_arts/martial_item.dart';
export 'src/plugins/martial_arts/martial_item_content.dart';
export 'src/plugins/martial_arts/martial_loadout_component.dart';
```

- [ ] **Step 5: Update `martial_item_test.dart`**

Replace the entire file with:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
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
  MartialArtsPlugin().initialize(context);
  return context;
}

void main() {
  group('content lists', () {
    test('5 martial_item entries and 3 martial_trinket entries', () {
      final context = _newContext();
      expect(context.content.allOfType('martial_item'), hasLength(5));
      expect(context.content.allOfType('martial_trinket'), hasLength(3));
    });

    test('every item/trinket id is unique', () {
      final context = _newContext();
      final ids = [
        ...context.content.allOfType('martial_item'),
        ...context.content.allOfType('martial_trinket'),
      ].map((d) => d.id);
      expect(ids.toSet(), hasLength(8));
    });
  });

  group('equipItem', () {
    test('creates an item entity carrying the item\'s tags', () {
      final context = _newContext();
      final wearer = context.entities.create();
      final brassKnuckles = martialItem(MartialItemIds.brassKnuckles, context);

      final itemEntity = equipItem(brassKnuckles, wearer, context);

      expect(
        context.components.get<TagSet>(itemEntity)!.tags,
        equals(brassKnuckles.tags),
      );
    });

    test('registers the item\'s modifiers against the wearer', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(martialItem(MartialItemIds.brassKnuckles, context), wearer, context);

      final resolved = const ModifierResolver().resolve(
        10,
        context.modifiers.activeModifiersFor(wearer, 'punch', context.components),
      );
      expect(resolved, equals(16));
    });

    test('add and multiply modifiers from different items stack correctly',
        () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(martialItem(MartialItemIds.brassKnuckles, context), wearer,
          context); // +6 add to punch
      equipItem(martialItem(MartialItemIds.weightedVest, context), wearer,
          context); // x1.1 multiply on punch

      final resolved = const ModifierResolver().resolve(
        10,
        context.modifiers.activeModifiersFor(wearer, 'punch', context.components),
      );
      expect(resolved, closeTo((10 + 6) * 1.1, 0.0001));
    });

    test('grants the wearer an equipped:<id> tag without erasing other tags',
        () {
      final context = _newContext();
      final wearer = context.entities.create();
      learnStyle(wearer, MartialStyles.boxing, context);

      equipItem(martialItem(MartialItemIds.brassKnuckles, context), wearer, context);

      final tags = context.components.get<TagSet>(wearer)!.tags;
      expect(tags, containsAll({'martial', 'style:boxing', 'equipped:brass_knuckles'}));
    });

    test('records the equipped item on MartialLoadoutComponent, '
        'accumulating across multiple equips', () {
      final context = _newContext();
      final wearer = context.entities.create();

      final first = equipItem(
          martialItem(MartialItemIds.brassKnuckles, context), wearer, context);
      final second = equipItem(
          martialItem(MartialItemIds.momentumTrinket, context), wearer, context);

      final loadout = context.components.get<MartialLoadoutComponent>(wearer)!;
      expect(loadout.equippedItems, equals([first, second]));
    });

    test('trinkets with no static modifiers register none', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(martialItem(MartialItemIds.momentumTrinket, context), wearer, context);

      expect(
        context.modifiers
            .activeModifiersFor(wearer, 'momentum', context.components),
        isEmpty,
      );
    });

    test('counterstrike ring only boosts internal damage while the tai chi '
        'stance tag is active', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(martialItem(MartialItemIds.counterstrikeRing, context), wearer, context);

      expect(
        context.modifiers
            .activeModifiersFor(wearer, 'internal', context.components),
        isEmpty,
      );

      context.components.add(
        wearer,
        TagSet({...context.components.get<TagSet>(wearer)!.tags, 'stance:tai_chi'}),
      );

      final active = context.modifiers
          .activeModifiersFor(wearer, 'internal', context.components);
      expect(active, hasLength(1));
      expect(active.single.value, equals(3));
    });
  });
}
```

- [ ] **Step 6: Update `martial_arts_plugin_test.dart`**

Find:

```dart
    test('removes MartialLoadoutComponent when its entity is destroyed', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);

      final wearer = context.entities.create();
      equipItem(brassKnuckles, wearer, context);
      expect(context.components.has<MartialLoadoutComponent>(wearer), isTrue);

      context.entities.destroy(wearer);

      expect(context.components.has<MartialLoadoutComponent>(wearer), isFalse);
    });

    test('component cleanup stops after unregister', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);

      final wearer = context.entities.create();
      equipItem(brassKnuckles, wearer, context);

      plugin.unregister(context);
      context.entities.destroy(wearer);

      expect(context.components.has<MartialLoadoutComponent>(wearer), isTrue);
    });
```

Replace with:

```dart
    test('removes MartialLoadoutComponent when its entity is destroyed', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);

      final wearer = context.entities.create();
      equipItem(martialItem(MartialItemIds.brassKnuckles, context), wearer, context);
      expect(context.components.has<MartialLoadoutComponent>(wearer), isTrue);

      context.entities.destroy(wearer);

      expect(context.components.has<MartialLoadoutComponent>(wearer), isFalse);
    });

    test('component cleanup stops after unregister', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);

      final wearer = context.entities.create();
      equipItem(martialItem(MartialItemIds.brassKnuckles, context), wearer, context);

      plugin.unregister(context);
      context.entities.destroy(wearer);

      expect(context.components.has<MartialLoadoutComponent>(wearer), isTrue);
    });
```

- [ ] **Step 7: Update `martial_arts_end_to_end_test.dart`**

Find:

```dart
    learnStyle(player, MartialStyles.boxing, context);
    equipItem(brassKnuckles, player, context);
    equipItem(momentumTrinket, player, context);
```

Replace with:

```dart
    learnStyle(player, MartialStyles.boxing, context);
    equipItem(martialItem(MartialItemIds.brassKnuckles, context), player, context);
    equipItem(martialItem(MartialItemIds.momentumTrinket, context), player, context);
```

- [ ] **Step 8: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes, including all 3 updated files and every pre-existing test —
run `dart test test/plugins/martial_arts/ test/integration/martial_arts_end_to_end_test.dart`
specifically first to confirm nothing there regressed, then the full
suite).

```bash
git add lib/src/plugins/martial_arts/martial_item.dart \
  lib/src/plugins/martial_arts/martial_arts_plugin.dart \
  lib/src/plugins/martial_arts/martial_arts_rules.dart \
  lib/martial_arts_plugin.dart \
  test/plugins/martial_arts/martial_item_test.dart \
  test/plugins/martial_arts/martial_arts_plugin_test.dart \
  test/integration/martial_arts_end_to_end_test.dart
git commit -m "feat: load MartialArts items/trinkets from ContentRegistry"
```

---

### Task 4: `elemental_item_content.dart` (content + parser + resolver)

**Files:**
- Create: `lib/src/plugins/elemental/elemental_item_content.dart`
- Test: `test/plugins/elemental/elemental_item_content_test.dart`

**Interfaces:**
- Consumes: `ContentDefinition`, `ContentRegistry`, `Modifier`,
  `ModifierOperation`, `ModifierSource`, `HasTagQuery`, `EntityId`,
  `PluginContext` (`package:build_engine/build_engine.dart`);
  `ElementalItemDefinition` (same-directory `elemental_item.dart`);
  `ElementalItemIds` (same-directory `elemental_vocabulary.dart`, Task 1).
- Produces: `const elementalItemContentDefinitions`,
  `ElementalItemDefinition elementalItemDefinitionFromContent(ContentDefinition
  definition)`, `ElementalItemDefinition elementalItem(String id,
  PluginContext context)`.

- [ ] **Step 1: Write `elemental_item_content.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'elemental_item.dart';
import 'elemental_vocabulary.dart';

/// Elemental's one item, as data — loaded into `PluginContext.content`
/// via `PluginSdk.registerContentBatch` in `ElementalPlugin.initialize`,
/// mirroring `martialItemContentDefinitions`
/// (`../martial_arts/martial_item_content.dart`), the same pattern
/// applied to Elemental.
const elementalItemContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ElementalItemIds.emberCharm,
    'type': 'elemental_item',
    'tags': ['magic', 'fire', 'elemental', 'trinket'],
    'modifiers': [
      {
        'stat': 'punch',
        'operation': 'add',
        'value': 4,
        'condition': 'martial',
      },
    ],
  },
];

/// Builds an [ElementalItemDefinition] from a loaded [ContentDefinition].
/// See `martialItemDefinitionFromContent`
/// (`../martial_arts/martial_item_content.dart`) for the full parsing
/// rationale — this is the identical pattern, independently applied
/// here (Elemental never imports MartialArts).
ElementalItemDefinition elementalItemDefinitionFromContent(
    ContentDefinition definition) {
  final rawModifiers = (definition.extra['modifiers'] as List)
      .map((e) => (e as Map).map((k, v) => MapEntry(k as String, v)))
      .toList();

  List<Modifier> modifiersFor(EntityId wearer) => [
        for (var i = 0; i < rawModifiers.length; i++)
          Modifier(
            source:
                ModifierSource('item:${definition.id}:$i:${wearer.value}'),
            target: wearer,
            stat: rawModifiers[i]['stat'] as String,
            operation: _operationFor(rawModifiers[i]['operation'] as String),
            value: rawModifiers[i]['value'] as num,
            condition: rawModifiers[i].containsKey('condition')
                ? HasTagQuery(rawModifiers[i]['condition'] as String)
                : null,
          ),
      ];

  return ElementalItemDefinition(
    id: definition.id,
    tags: definition.tags,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses item [id] from [context]'s loaded content in one
/// call — the replacement for the old bare `const emberCharm` identifier
/// everywhere it was previously referenced. Stateless: re-resolves from
/// `context.content` on every call, no caching.
ElementalItemDefinition elementalItem(String id, PluginContext context) =>
    elementalItemDefinitionFromContent(context.content.get(id));

ModifierOperation _operationFor(String name) => switch (name) {
      'add' => ModifierOperation.add,
      'multiply' => ModifierOperation.multiply,
      'override' => ModifierOperation.override,
      'min' => ModifierOperation.min,
      'max' => ModifierOperation.max,
      _ => throw ArgumentError('unknown modifier operation: $name'),
    };
```

- [ ] **Step 2: Write `elemental_item_content_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/elemental_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('the 1 item definition loads as a batch', () {
    final registry = ContentRegistry();
    final definitions = registry.loadAll(elementalItemContentDefinitions);
    expect(definitions, hasLength(1));
    expect(registry.allOfType('elemental_item'), hasLength(1));
  });

  test('elementalItemDefinitionFromContent parses id, tags, and a single '
      'conditional modifier', () {
    final registry = ContentRegistry();
    registry.loadAll(elementalItemContentDefinitions);
    final definition = elementalItemDefinitionFromContent(
        registry.get(ElementalItemIds.emberCharm));

    expect(definition.id, equals('ember_charm'));
    expect(definition.tags, equals({'magic', 'fire', 'elemental', 'trinket'}));

    final wearer = const EntityId(1);
    final modifiers = definition.modifiersFor(wearer);
    expect(modifiers, hasLength(1));
    expect(modifiers.single.target, equals(wearer));
    expect(modifiers.single.stat, equals('punch'));
    expect(modifiers.single.operation, equals(ModifierOperation.add));
    expect(modifiers.single.value, equals(4));
    expect(modifiers.single.condition, isNotNull);
  });

  test('elementalItem resolves and parses in one call', () {
    final registry = ContentRegistry();
    registry.loadAll(elementalItemContentDefinitions);
    final context = PluginContext(
      entities: EntityRegistry(EventBus()),
      components: ComponentStore(),
      events: EventBus(),
      rng: RngService(1),
      rules: RuleEngine(
        entities: EntityRegistry(EventBus()),
        components: ComponentStore(),
        events: EventBus(),
        rng: RngService(1),
      ),
      queries: QueryEngine(QueryScope(components: ComponentStore())),
      modifiers: ModifierCollection(),
      content: registry,
    );

    final definition = elementalItem(ElementalItemIds.emberCharm, context);
    expect(definition.id, equals('ember_charm'));
  });
}
```

- [ ] **Step 3: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes — this file doesn't yet touch `elemental_item.dart`,
`elemental_plugin.dart`, or any existing test).

```bash
git add lib/src/plugins/elemental/elemental_item_content.dart \
  test/plugins/elemental/elemental_item_content_test.dart
git commit -m "feat: add elemental_item_content.dart (data + parser + resolver)"
```

---

### Task 5: Wire Elemental's item into `ContentRegistry` + update all Elemental call sites

Same shape as Task 3: production wiring + the 2 affected test files land
together, since neither test file can pass until the wiring exists.

**Files:**
- Modify: `lib/src/plugins/elemental/elemental_item.dart`
- Modify: `lib/src/plugins/elemental/elemental_plugin.dart`
- Modify: `lib/elemental_plugin.dart`
- Modify: `test/plugins/elemental/elemental_item_test.dart`
- Modify: `test/integration/cross_plugin_synergy_test.dart`

- [ ] **Step 1: Replace `elemental_item.dart`**

Replace the entire file with:

```dart
import 'package:build_engine/build_engine.dart';

/// A wearable item or trinket for Elemental — mirrors
/// `MartialItemDefinition`/`equipItem`'s exact shape (the second
/// occurrence of an already-proven pattern, not a new one). Deliberately
/// has no item-entity-creation or loadout-tracking — nothing here needs
/// inventory bookkeeping. Instances are built from loaded content via
/// `elementalItemDefinitionFromContent`/`elementalItem`
/// (`elemental_item_content.dart`), never hand-written here.
class ElementalItemDefinition {
  const ElementalItemDefinition({
    required this.id,
    required this.tags,
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final Set<String> tags;
  final List<Modifier> Function(EntityId wearer) modifiersFor;

  static List<Modifier> _noModifiers(EntityId wearer) => const [];
}

/// Registers [item]'s modifiers against [wearer] and tags [wearer]
/// `equipped:<item.id>`.
void equipElementalItem(
  ElementalItemDefinition item,
  EntityId wearer,
  PluginContext context,
) {
  for (final modifier in item.modifiersFor(wearer)) {
    context.modifiers.add(modifier);
  }
  AddTag('equipped:${item.id}').apply(context.ruleContextFor(wearer));
}
```

- [ ] **Step 2: Update `elemental_plugin.dart`**

Find:

```dart
import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';
import 'elemental_conditions.dart';
import 'elemental_content.dart';
import 'elemental_effects.dart';
import 'elemental_rules.dart';
```

Replace with:

```dart
import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';
import 'elemental_conditions.dart';
import 'elemental_content.dart';
import 'elemental_effects.dart';
import 'elemental_item_content.dart';
import 'elemental_rules.dart';
import 'elemental_vocabulary.dart';
```

Find:

```dart
    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find('fireball') == null) {
      sdk.registerContentBatch(elementalContentDefinitions);
    }
  }
```

Replace with:

```dart
    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find('fireball') == null) {
      sdk.registerContentBatch(elementalContentDefinitions);
    }
    if (context.content.find(ElementalItemIds.emberCharm) == null) {
      sdk.registerContentBatch(elementalItemContentDefinitions);
    }
  }
```

- [ ] **Step 3: Update `lib/elemental_plugin.dart`**

Find:

```dart
export 'src/plugins/elemental/elemental_affinity_component.dart';
export 'src/plugins/elemental/elemental_conditions.dart';
export 'src/plugins/elemental/elemental_content.dart';
export 'src/plugins/elemental/elemental_effects.dart';
export 'src/plugins/elemental/elemental_item.dart';
export 'src/plugins/elemental/elemental_rules.dart';
export 'src/plugins/elemental/elemental_vocabulary.dart';
export 'src/plugins/elemental/elements.dart';
export 'src/plugins/elemental/elemental_plugin.dart';
```

Replace with:

```dart
export 'src/plugins/elemental/elemental_affinity_component.dart';
export 'src/plugins/elemental/elemental_conditions.dart';
export 'src/plugins/elemental/elemental_content.dart';
export 'src/plugins/elemental/elemental_effects.dart';
export 'src/plugins/elemental/elemental_item.dart';
export 'src/plugins/elemental/elemental_item_content.dart';
export 'src/plugins/elemental/elemental_rules.dart';
export 'src/plugins/elemental/elemental_vocabulary.dart';
export 'src/plugins/elemental/elements.dart';
export 'src/plugins/elemental/elemental_plugin.dart';
```

- [ ] **Step 4: Replace `elemental_item_test.dart`**

Replace the entire file with:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/elemental_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
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
  ElementalPlugin().initialize(context);
  return context;
}

void main() {
  group('emberCharm', () {
    test('has the expected id and tags', () {
      final context = _newContext();
      final emberCharm = elementalItem(ElementalItemIds.emberCharm, context);
      expect(emberCharm.id, equals('ember_charm'));
      expect(emberCharm.tags,
          equals({'magic', 'fire', 'elemental', 'trinket'}));
    });

    test('modifiersFor returns a single +4 add punch modifier', () {
      final context = _newContext();
      final emberCharm = elementalItem(ElementalItemIds.emberCharm, context);
      const wearer = EntityId(1);
      final modifiers = emberCharm.modifiersFor(wearer);

      expect(modifiers, hasLength(1));
      final modifier = modifiers.single;
      expect(modifier.target, equals(wearer));
      expect(modifier.stat, equals('punch'));
      expect(modifier.operation, equals(ModifierOperation.add));
      expect(modifier.value, equals(4));
    });
  });

  group('equipElementalItem', () {
    test("registers the item's modifiers against a martial wearer", () {
      final context = _newContext();
      final wearer = context.entities.create();
      AddTag('martial').apply(context.ruleContextFor(wearer));

      equipElementalItem(
          elementalItem(ElementalItemIds.emberCharm, context), wearer, context);

      final active = context.modifiers
          .activeModifiersFor(wearer, 'punch', context.components);
      expect(active, hasLength(1));
    });

    test('the modifier does not apply to a non-martial wearer', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipElementalItem(
          elementalItem(ElementalItemIds.emberCharm, context), wearer, context);

      final active = context.modifiers
          .activeModifiersFor(wearer, 'punch', context.components);
      expect(active, isEmpty);
    });

    test('tags the wearer equipped:<id>', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipElementalItem(
          elementalItem(ElementalItemIds.emberCharm, context), wearer, context);

      expect(context.components.get<TagSet>(wearer)!.tags,
          contains('equipped:ember_charm'));
    });
  });
}
```

- [ ] **Step 5: Update `cross_plugin_synergy_test.dart`**

Find:

```dart
    learnStyle(enchanted, MartialStyles.boxing, context);
    equipElementalItem(emberCharm, enchanted, context);
```

Replace with:

```dart
    learnStyle(enchanted, MartialStyles.boxing, context);
    equipElementalItem(
        elementalItem(ElementalItemIds.emberCharm, context), enchanted, context);
```

- [ ] **Step 6: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes — run `dart test test/plugins/elemental/ test/integration/`
specifically first to confirm nothing there regressed, then the full
suite).

```bash
git add lib/src/plugins/elemental/elemental_item.dart \
  lib/src/plugins/elemental/elemental_plugin.dart \
  lib/elemental_plugin.dart \
  test/plugins/elemental/elemental_item_test.dart \
  test/integration/cross_plugin_synergy_test.dart
git commit -m "feat: load Elemental's item from ContentRegistry"
```

---

### Task 6: Documentation

**Files:**
- Modify: `ARCHITECTURE_AUDIT.md`

- [ ] **Step 1: Update Finding #7's status in `ARCHITECTURE_AUDIT.md`**

Find the Finding #7 section (starts `## 7. Hardcoded content`) and its
"Recommended fix" paragraph ending "...should get its own brainstorm/spec
before implementation, same as the prior audit's recommendation."

Insert, immediately after that paragraph (still inside section 7, before
the `## 8. Global mutable state` heading):

```markdown

**Status: ✅ Fixed (2026-08-24).** Both plugins' item/trinket content
migrated to `ContentRegistry`, following exactly the recommended
data/runtime-split pattern — see
`docs/superpowers/specs/2026-08-24-item-content-migration-design.md` and
`docs/superpowers/plans/2026-08-24-item-content-migration.md` for the
full design and task-by-task implementation record.
```

Also update the Summary table's row for category 7 — find:

```markdown
| 7 | Hardcoded content | ⚠️ 1 finding (Low) |
```

Replace with:

```markdown
| 7 | Hardcoded content | ⚠️ 1 finding (Low) → ✅ Fixed |
```

- [ ] **Step 2: Commit**

```bash
git add ARCHITECTURE_AUDIT.md
git commit -m "docs: mark ARCHITECTURE_AUDIT.md Finding 7 as fixed"
```
