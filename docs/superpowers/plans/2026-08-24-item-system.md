# Item System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a generic, content-agnostic Item plugin implementing the
UNKNOWN → DISCOVERED → LOCKED → TRAIN MASTERY → USABLE → TOME lifecycle for
physical equipment, built entirely on existing Core services (Discovery,
Mastery, ContentRegistry, Tome, Condition/Rule/Effect) with zero new Core
concepts.

**Architecture:** New plugin at `lib/src/plugins/item/` + barrel
`lib/item_plugin.dart`, depending on nothing but Core (mirrors
`ElementalPlugin`, the documented "copy this, not MartialArts" reference
plugin). "LOCKED"/"USABLE" map directly onto the existing generic
`DiscoveryState.discovered`/`.unlocked` — no new state enum. Mastery
gating reuses the existing `MasteryAtLeast` condition and `UnlockSubject`
effect. Tome rejection of an unusable item happens at the Item plugin's own
call boundary (`addItemToTome`), not by modifying `TomeService`/
`Container`/`PlacementRule` — `PlacementRule.isSatisfied` has no owner
parameter to check owner-scoped Discovery/Mastery state against, so
Tome internals stay untouched per the milestone's own instruction.

**Tech Stack:** Dart 3.7, `package:test`, existing `build_engine` Core
services only.

**Spec:** The milestone brief in the current conversation (no separate
spec file — the brief itself, together with this plan's own File
Structure/task interfaces, is the full spec for this pass).

## Global Constraints

- Core must not gain any item-specific vocabulary — every new concept
  lives under `lib/src/plugins/item/`.
- Do not create `SwordSystem`/`WeaponSystem`/`ItemMasterySystem`/
  `EquipmentMasterySystem` — reuse the existing generic `MasteryTracker`.
- Do not duplicate Discovery/Mastery state on `ItemInstance` — query the
  existing trackers instead of storing a second copy.
- Do not modify `TomeService`, `Container`, or `PlacementRule`.
- Do not implement UI, shops, crafting, loot tables, weapon animations,
  combat action interpretation, new combat mechanics, magic, cultivation,
  or meta progression.
- `dart analyze` must stay clean and no existing test may regress.
- Do not commit (per the milestone instructions) — leave changes staged
  in the working tree only.

---

## File Structure

```
lib/src/plugins/item/
  item_requirement.dart   - ItemRequirement (masterySubject, minimumLevel)
  item_definition.dart    - ItemDefinition (immutable content-derived shape)
  item_instance.dart      - ItemInstance (runtime component: definitionId, owner)
  item_vocabulary.dart    - ItemIds, ItemCategories, itemSubject(), itemReferenceType
  item_content.dart       - itemContentDefinitions (6 items) + parsing
  item_events.dart        - ItemAddedToTome
  item_lifecycle.dart     - ownItem/discoverItem/usability/addItemToTome/exception
  item_rules.dart         - buildItemUsabilityRules()
  item_plugin.dart        - ItemPlugin (GamePlugin)
lib/item_plugin.dart      - public barrel

test/plugins/item/
  item_definition_test.dart
  item_instance_test.dart
  item_content_test.dart
  item_lifecycle_test.dart
  item_plugin_test.dart

test/integration/
  item_end_to_end_test.dart   - standalone-run + full lifecycle + determinism

test/integration/architecture_dependency_test.dart  - MODIFIED (add Item barrel + groups)
```

---

### Task 1: Item domain types — `ItemRequirement`, `ItemDefinition`, `ItemInstance`

**Files:**
- Create: `lib/src/plugins/item/item_requirement.dart`
- Create: `lib/src/plugins/item/item_definition.dart`
- Create: `lib/src/plugins/item/item_instance.dart`
- Test: `test/plugins/item/item_definition_test.dart`
- Test: `test/plugins/item/item_instance_test.dart`

**Interfaces:**
- Produces: `ItemRequirement({required String masterySubject, required int minimumLevel})`
- Produces: `ItemDefinition({required String id, required String category, required Set<String> tags, required Map<String, num> properties, ItemRequirement? requirement, List<Modifier> Function(EntityId owner) modifiersFor})`
- Produces: `ItemInstance({required String definitionId, required EntityId owner})` — a plain component, no methods.

- [ ] **Step 1: Write `item_requirement.dart`**

```dart
/// A generic mastery gate an [ItemDefinition] can require before it is
/// usable — reuses the existing `MasteryTracker`/`MasteryAtLeast`
/// machinery rather than inventing an item-specific mastery concept.
/// [masterySubject] is an arbitrary mastery subject string (typically,
/// but not necessarily, the item's own `item:<id>` subject — a future
/// item could just as well require mastery of an unrelated subject, e.g.
/// a martial style, purely by agreeing on the same subject string).
class ItemRequirement {
  const ItemRequirement({
    required this.masterySubject,
    required this.minimumLevel,
  });

  final String masterySubject;
  final int minimumLevel;
}
```

- [ ] **Step 2: Write `item_definition.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'item_requirement.dart';

/// A piece of physical equipment's immutable, content-derived shape —
/// mirrors `MartialItemDefinition`/`ElementalItemDefinition`'s exact
/// shape (the third occurrence of an already-proven pattern, not a new
/// one). Instances are built from loaded content via
/// `itemDefinitionFromContent`/`itemDefinition` (`item_content.dart`),
/// never hand-written here. [category] is `ContentDefinition.type`
/// verbatim (`'weapon'`/`'armor'`/...) — no redundant second field.
/// [properties] are raw named values (`{'attack': 3}`) describing the
/// item; nothing here activates them as `Modifier`s automatically —
/// [modifiersFor] exposes that capability for a future pass (equip/
/// active-build interpretation) to call, per the milestone's "expose
/// enough information for ActiveBuild interpretation later, don't
/// implement full combat action conversion yet."
class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.category,
    required this.tags,
    required this.properties,
    this.requirement,
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final String category;
  final Set<String> tags;
  final Map<String, num> properties;
  final ItemRequirement? requirement;
  final List<Modifier> Function(EntityId owner) modifiersFor;

  static List<Modifier> _noModifiers(EntityId owner) => const [];
}
```

- [ ] **Step 3: Write `item_instance.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// One physical copy of an item an owner possesses — pure runtime state,
/// attached via `ComponentStore` to a freshly created entity per copy
/// (see `ownItem`), exactly like `TomeInstance`'s "two fields, no
/// methods" pattern. Deliberately does NOT store discovered/usable state
/// or a mastery level — `DiscoveryTracker`/`MasteryTracker` (keyed by
/// [owner] + the subject `itemSubject(definitionId)` derives) are the
/// single source of truth for those; duplicating them here would let the
/// copy silently desync from the tracker it's supposed to mirror.
class ItemInstance {
  const ItemInstance({required this.definitionId, required this.owner});

  final String definitionId;
  final EntityId owner;
}
```

- [ ] **Step 4: Write the failing tests**

`test/plugins/item/item_definition_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_definition.dart';
import 'package:build_engine/src/plugins/item/item_requirement.dart';
import 'package:test/test.dart';

void main() {
  test('ItemDefinition carries id/category/tags/properties/requirement', () {
    const definition = ItemDefinition(
      id: 'iron_sword',
      category: 'weapon',
      tags: {'item', 'weapon', 'blade'},
      properties: {'attack': 3},
      requirement: ItemRequirement(masterySubject: 'item:iron_sword', minimumLevel: 2),
    );

    expect(definition.id, equals('iron_sword'));
    expect(definition.category, equals('weapon'));
    expect(definition.properties['attack'], equals(3));
    expect(definition.requirement!.minimumLevel, equals(2));
  });

  test('modifiersFor defaults to no modifiers when unset', () {
    const definition = ItemDefinition(
      id: 'knife',
      category: 'weapon',
      tags: {'item'},
      properties: {'attack': 2},
    );

    expect(definition.modifiersFor(const EntityId(1)), isEmpty);
  });
}
```

`test/plugins/item/item_instance_test.dart`:

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_instance.dart';
import 'package:test/test.dart';

void main() {
  test('ItemInstance references its definition and owner', () {
    const owner = EntityId(1);
    const instance = ItemInstance(definitionId: 'iron_sword', owner: owner);

    expect(instance.definitionId, equals('iron_sword'));
    expect(instance.owner, equals(owner));
  });

  test('ItemInstance can be stored and retrieved as an ordinary component', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    const owner = EntityId(1);

    final itemEntity = entities.create();
    components.add(itemEntity, ItemInstance(definitionId: 'gloves', owner: owner));

    expect(components.get<ItemInstance>(itemEntity)!.definitionId, equals('gloves'));
  });
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `dart test test/plugins/item/item_definition_test.dart test/plugins/item/item_instance_test.dart`
Expected: FAIL — files under `lib/src/plugins/item/` don't exist yet.

- [ ] **Step 6: Confirm the Step 1–3 files above make these tests pass**

Run: `dart test test/plugins/item/item_definition_test.dart test/plugins/item/item_instance_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit is deferred — do not commit per milestone instructions.**

---

### Task 2: Item vocabulary + content data + content parsing

**Files:**
- Create: `lib/src/plugins/item/item_vocabulary.dart`
- Create: `lib/src/plugins/item/item_content.dart`
- Test: `test/plugins/item/item_content_test.dart`

**Interfaces:**
- Consumes: `ItemDefinition`, `ItemRequirement` (Task 1).
- Produces: `ItemIds` (id constants), `ItemCategories` (category constants), `String itemSubject(String definitionId)`, `const itemReferenceType`.
- Produces: `const itemContentDefinitions` (`List<Map<String, dynamic>>`), `ItemDefinition itemDefinitionFromContent(ContentDefinition definition)`, `ItemDefinition itemDefinition(String id, PluginContext context)`.

- [ ] **Step 1: Write `item_vocabulary.dart`**

```dart
/// Stable content ids for the Item plugin's starter set
/// (`item_content.dart`) — same rationale as `MartialItemIds`/
/// `ElementalItemIds`: a typo here is a compile error, not a silent
/// runtime string mismatch.
abstract final class ItemIds {
  static const knife = 'knife';
  static const ironSword = 'iron_sword';
  static const gloves = 'gloves';
  static const trainingStaff = 'training_staff';
  static const clothArmor = 'cloth_armor';
  static const trainingShoes = 'training_shoes';
}

/// `ContentDefinition.type` values this plugin's content uses — plain
/// category labels Core never interprets.
abstract final class ItemCategories {
  static const weapon = 'weapon';
  static const armor = 'armor';
  static const footwear = 'footwear';
}

/// The canonical `Discovery`/`Mastery` subject for item [definitionId] —
/// `'item:<id>'`, matching the exact naming convention `MasteryComponent`/
/// `DiscoveryComponent`'s own doc comments already use as their
/// worked example. Centralized here so every call site (discovery,
/// mastery gating, the usability rule) agrees on the same string by
/// construction instead of by convention.
String itemSubject(String definitionId) => 'item:$definitionId';

/// The `BuildComponentRef.referenceType` every item occupies a Tome slot
/// under — the canonical replacement for the bare `'item'` string
/// literal previously scattered ad hoc across test fixtures
/// (`test/tome/tome_service_test.dart`, `test/reward/reward_resolver_test.dart`,
/// `test/integration/support/vertical_slice_runner.dart`) with no shared
/// source of truth.
const itemReferenceType = 'item';
```

- [ ] **Step 2: Write `item_content.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_requirement.dart';
import 'item_vocabulary.dart';

/// The 6 starter items this plugin implements, as data — loaded into
/// `PluginContext.content` via `PluginSdk.registerContentBatch` in
/// `ItemPlugin.initialize`, mirroring every other content plugin's
/// `*ContentDefinitions` constant. Stats are deliberately simple, not
/// balanced. `requirements.mastery.thresholds` (present only for items
/// with `minimum > 0`) is `ItemPlugin.initialize`'s own input to
/// `MasteryTracker.define` — it is plumbing for reaching the required
/// level, not part of `ItemDefinition`'s own shape (which only needs the
/// subject + minimum to check usability).
const itemContentDefinitions = <Map<String, dynamic>>[
  {
    'id': ItemIds.knife,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade'],
    'properties': {'attack': 2},
    'requirements': {
      'mastery': {'subject': 'item:knife', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.ironSword,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'blade'],
    'properties': {'attack': 3},
    'requirements': {
      'mastery': {
        'subject': 'item:iron_sword',
        'minimum': 2,
        'thresholds': [10, 25],
      },
    },
  },
  {
    'id': ItemIds.gloves,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'fist'],
    'properties': {'attack': 1},
    'requirements': {
      'mastery': {'subject': 'item:gloves', 'minimum': 0},
    },
  },
  {
    'id': ItemIds.trainingStaff,
    'type': ItemCategories.weapon,
    'tags': ['item', 'weapon', 'staff'],
    'properties': {'attack': 2},
    'requirements': {
      'mastery': {
        'subject': 'item:training_staff',
        'minimum': 1,
        'thresholds': [10],
      },
    },
  },
  {
    'id': ItemIds.clothArmor,
    'type': ItemCategories.armor,
    'tags': ['item', 'armor'],
    'properties': {'defense': 2},
    'requirements': {
      'mastery': {
        'subject': 'item:cloth_armor',
        'minimum': 1,
        'thresholds': [8],
      },
    },
  },
  {
    'id': ItemIds.trainingShoes,
    'type': ItemCategories.footwear,
    'tags': ['item', 'footwear'],
    'properties': {'speed': 1},
    'requirements': {
      'mastery': {'subject': 'item:training_shoes', 'minimum': 0},
    },
  },
];

/// Builds an [ItemDefinition] from a loaded [ContentDefinition].
/// `extra['properties']` supplies [ItemDefinition.properties] and
/// [ItemDefinition.modifiersFor] (one unconditional `add` `Modifier` per
/// property); `extra['requirements']['mastery']` supplies
/// [ItemDefinition.requirement], if present.
ItemDefinition itemDefinitionFromContent(ContentDefinition definition) {
  final rawProperties =
      (definition.extra['properties'] as Map?) ?? const <String, dynamic>{};
  final properties = <String, num>{
    for (final entry in rawProperties.entries)
      entry.key as String: entry.value as num,
  };

  final masteryRaw =
      (definition.extra['requirements'] as Map?)?['mastery'] as Map?;
  final requirement = masteryRaw == null
      ? null
      : ItemRequirement(
          masterySubject: masteryRaw['subject'] as String,
          minimumLevel: masteryRaw['minimum'] as int,
        );

  List<Modifier> modifiersFor(EntityId owner) => [
        for (final entry in properties.entries)
          Modifier(
            source: ModifierSource(
                'item:${definition.id}:${entry.key}:${owner.value}'),
            target: owner,
            stat: entry.key,
            operation: ModifierOperation.add,
            value: entry.value,
          ),
      ];

  return ItemDefinition(
    id: definition.id,
    category: definition.type,
    tags: definition.tags,
    properties: properties,
    requirement: requirement,
    modifiersFor: modifiersFor,
  );
}

/// Resolves and parses item [id] from [context]'s loaded content in one
/// call — the same convenience `martialItem`/`elementalItem` already
/// provide for their own plugins. Stateless: re-resolves from
/// `context.content` on every call, no caching.
ItemDefinition itemDefinition(String id, PluginContext context) =>
    itemDefinitionFromContent(context.content.get(id));
```

- [ ] **Step 3: Write the failing test** — `test/plugins/item/item_content_test.dart`

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/item/item_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('all 6 starter items load through ContentRegistry', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    for (final id in [
      ItemIds.knife,
      ItemIds.ironSword,
      ItemIds.gloves,
      ItemIds.trainingStaff,
      ItemIds.clothArmor,
      ItemIds.trainingShoes,
    ]) {
      expect(registry.find(id), isNotNull, reason: '$id should be loaded');
    }
  });

  test('itemDefinitionFromContent parses properties and requirement', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    final ironSword = itemDefinitionFromContent(registry.get(ItemIds.ironSword));

    expect(ironSword.category, equals('weapon'));
    expect(ironSword.properties['attack'], equals(3));
    expect(ironSword.requirement!.masterySubject, equals('item:iron_sword'));
    expect(ironSword.requirement!.minimumLevel, equals(2));
  });

  test('an item with minimum 0 has a requirement but no thresholds needed', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);

    final knife = itemDefinitionFromContent(registry.get(ItemIds.knife));

    expect(knife.requirement!.minimumLevel, equals(0));
  });

  test('modifiersFor turns properties into unconditional add Modifiers', () {
    final registry = ContentRegistry();
    registry.loadAll(itemContentDefinitions);
    final ironSword = itemDefinitionFromContent(registry.get(ItemIds.ironSword));

    final modifiers = ironSword.modifiersFor(const EntityId(1));

    expect(modifiers, hasLength(1));
    expect(modifiers.single.stat, equals('attack'));
    expect(modifiers.single.value, equals(3));
    expect(modifiers.single.operation, equals(ModifierOperation.add));
  });
}
```

- [ ] **Step 4: Run tests to verify they fail, then pass**

Run: `dart test test/plugins/item/item_content_test.dart`
Expected: FAIL first (files missing), then PASS once Steps 1–2 above exist.

---

### Task 3: `ItemAddedToTome` event

**Files:**
- Create: `lib/src/plugins/item/item_events.dart`

**Interfaces:**
- Produces: `ItemAddedToTome(EntityId owner, String definitionId, SlotId slot)`.

**Rationale (no test file — a 3-field data class with no behavior; covered
indirectly by Task 4's `addItemToTome` test):** `ItemDiscovered`/
`ItemMasteryChanged`/`ItemBecameUsable` from the milestone brief are
deliberately **not** created as new events — they already exist, generically,
as `SubjectDiscovered`/`MasteryChanged`/`SubjectUnlocked` fired with an
`item:<id>` subject once `discoverItem`/mastery training run (Task 4).
`ItemAddedToTome` is the one genuinely new event: `TomeService` has no
`EventBus` at all, so nothing else can observe a successful Tome insertion —
and publishing it from `addItemToTome` (which already holds `context.events`)
needs no change to `TomeService` itself.

- [ ] **Step 1: Write `item_events.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// Published by [addItemToTome] once an item has actually been inserted
/// into [owner]'s Tome. The one new event this plugin adds — everything
/// else ("discovered", "mastery changed", "became usable") already has a
/// generic equivalent (`SubjectDiscovered`/`MasteryChanged`/
/// `SubjectUnlocked`) fired with an `item:<id>` subject, and `TomeService`
/// has no `EventBus` of its own to hook a "was inserted" event onto
/// otherwise.
class ItemAddedToTome {
  const ItemAddedToTome(this.owner, this.definitionId, this.slot);

  final EntityId owner;
  final String definitionId;
  final SlotId slot;
}
```

- [ ] **Step 2:** No standalone test — verified via Task 4's `addItemToTome` test, which asserts this event is published.

---

### Task 4: Item lifecycle functions + usability rule

**Files:**
- Create: `lib/src/plugins/item/item_lifecycle.dart`
- Create: `lib/src/plugins/item/item_rules.dart`
- Test: `test/plugins/item/item_lifecycle_test.dart`

**Interfaces:**
- Consumes: `ItemDefinition`, `ItemRequirement` (Task 1), `itemSubject`, `itemReferenceType` (Task 2), `ItemAddedToTome` (Task 3).
- Produces:
  - `EntityId ownItem(EntityId owner, String definitionId, PluginContext context)`
  - `void discoverItem(EntityId owner, ItemDefinition item, PluginContext context)`
  - `List<Condition> usabilityConditionsFor(ItemDefinition item)`
  - `bool isItemUsable(EntityId owner, ItemDefinition item, PluginContext context)`
  - `bool isItemOwned(EntityId owner, String definitionId, PluginContext context)`
  - `bool isItemActive(EntityId owner, String definitionId, PluginContext context)`
  - `void addItemToTome(EntityId owner, SlotId slot, ItemDefinition item, PluginContext context)`
  - `class ItemNotUsableException implements Exception { final String definitionId; }`
  - `List<Rule> buildItemUsabilityRules(List<ItemDefinition> definitions)`

- [ ] **Step 1: Write `item_lifecycle.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_events.dart';
import 'item_instance.dart';
import 'item_vocabulary.dart';

/// Thrown by [addItemToTome] when [ItemDefinition] fails
/// [isItemUsable] for the given owner — the Item plugin's own rejection
/// at its call boundary into the Tome, since `PlacementRule.isSatisfied`
/// has no owner parameter to check owner-scoped Discovery/Mastery state
/// against (see `item_plugin.dart`'s doc comment for the full reasoning).
class ItemNotUsableException implements Exception {
  const ItemNotUsableException(this.definitionId);

  final String definitionId;

  @override
  String toString() => 'Item not usable: $definitionId';
}

/// Creates a fresh entity representing one physical copy of [definitionId]
/// owned by [owner], attaches an [ItemInstance] to it, and returns the new
/// entity — the OWNED state. Independent of DISCOVERED: an owner can hold
/// an [ItemInstance] for an item it hasn't discovered yet (e.g. an unread
/// magic item), and can discover an item's existence before ever owning a
/// copy — see `item_plugin.dart`'s doc comment for why these two states
/// are deliberately never collapsed into one boolean.
EntityId ownItem(EntityId owner, String definitionId, PluginContext context) {
  final instance = context.entities.create();
  context.components.add(
    instance,
    ItemInstance(definitionId: definitionId, owner: owner),
  );
  return instance;
}

/// Whether [owner] holds at least one [ItemInstance] of [definitionId] —
/// queries live ECS state rather than storing a second "owned" flag
/// anywhere.
bool isItemOwned(EntityId owner, String definitionId, PluginContext context) {
  for (final entity in context.components.entitiesWith<ItemInstance>()) {
    final instance = context.components.get<ItemInstance>(entity)!;
    if (instance.owner == owner && instance.definitionId == definitionId) {
      return true;
    }
  }
  return false;
}

/// Moves [owner]'s discovery state for [item] forward — the DISCOVERED
/// state. An item with no mastery requirement (or `minimumLevel <= 0`,
/// i.e. nothing to train) is promoted straight to `unlocked` (USABLE) in
/// the same call, via `DiscoveryTracker.unlock`'s auto-promotion through
/// `discovered` — there is no mastery threshold left to cross later for
/// `buildItemUsabilityRules` to react to. An item with a real requirement
/// only reaches `discovered` (LOCKED) here; [buildItemUsabilityRules]'s
/// rule promotes it to `unlocked` once mastery training crosses the
/// threshold.
void discoverItem(EntityId owner, ItemDefinition item, PluginContext context) {
  final subject = itemSubject(item.id);
  final requirement = item.requirement;
  if (requirement == null || requirement.minimumLevel <= 0) {
    context.discovery.unlock(owner, subject);
  } else {
    context.discovery.discover(owner, subject);
  }
}

/// The generic eligibility check `ItemUsable(item, character)` from the
/// milestone brief, built entirely from existing `Condition`s: discovered
/// (or better) AND, if [item] has a requirement, mastery at least its
/// minimum level. No `if item == sword` special-casing anywhere.
List<Condition> usabilityConditionsFor(ItemDefinition item) => [
      IsDiscovered(itemSubject(item.id)),
      if (item.requirement != null)
        MasteryAtLeast(
          item.requirement!.masterySubject,
          item.requirement!.minimumLevel,
        ),
    ];

/// Evaluates [usabilityConditionsFor] against [owner] right now — the
/// USABLE state. Never stored; always recomputed from the live
/// Discovery/Mastery trackers via `PluginContext.ruleContextFor`.
bool isItemUsable(EntityId owner, ItemDefinition item, PluginContext context) {
  final ruleContext = context.ruleContextFor(owner);
  return usabilityConditionsFor(item).every((c) => c.evaluate(ruleContext));
}

/// Whether [owner]'s Tome currently contains [definitionId] as an
/// `'item'`-typed placement — the ACTIVE state. Delegates entirely to
/// `TomeService.inspect`; no separate "active" flag is stored anywhere.
bool isItemActive(EntityId owner, String definitionId, PluginContext context) {
  return context.tome.inspect(owner).any((placement) =>
      placement.buildComponentRef.referenceType == itemReferenceType &&
      placement.buildComponentRef.contentId == definitionId);
}

/// Inserts [item] into [owner]'s Tome at [slot] — but only if
/// [isItemUsable] first. Throws [ItemNotUsableException] (leaving the
/// Tome untouched) rather than calling `TomeService.insert` for an
/// unusable item; on success, publishes [ItemAddedToTome] and returns
/// normally exactly like `TomeService.insert` would (including
/// propagating its own `InvalidPlacementException`/`StateError` for a
/// bad slot/missing Tome).
void addItemToTome(
  EntityId owner,
  SlotId slot,
  ItemDefinition item,
  PluginContext context,
) {
  if (!isItemUsable(owner, item, context)) {
    throw ItemNotUsableException(item.id);
  }
  context.tome.insert(
    owner,
    slot,
    BuildComponentRef(referenceType: itemReferenceType, contentId: item.id),
  );
  context.events.publish(ItemAddedToTome(owner, item.id, slot));
}
```

- [ ] **Step 2: Write `item_rules.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'item_definition.dart';
import 'item_vocabulary.dart';

/// One `Rule` per item with a real mastery requirement
/// (`minimumLevel > 0`): `WHEN MasteryLevelReached IF mastery(item) >=
/// minimum THEN unlock the item's discovery subject` — the generic
/// mirror of the milestone brief's `ItemBecameUsable` event, reusing
/// `SubjectUnlocked` (fired by `UnlockSubject`) rather than adding a new
/// event type. Items with no requirement (or `minimumLevel <= 0`) need
/// no rule — `discoverItem` already unlocks them immediately, since
/// there's no threshold left to cross.
List<Rule> buildItemUsabilityRules(List<ItemDefinition> definitions) => [
      for (final item in definitions)
        if (item.requirement != null && item.requirement!.minimumLevel > 0)
          Rule(
            trigger: MasteryLevelReached,
            subjectOf: (event) => (event as MasteryLevelReached).owner,
            conditions: [
              MasteryAtLeast(
                item.requirement!.masterySubject,
                item.requirement!.minimumLevel,
              ),
            ],
            effects: [UnlockSubject(itemSubject(item.id))],
          ),
    ];
```

- [ ] **Step 3: Write the failing test** — `test/plugins/item/item_lifecycle_test.dart`

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_content.dart';
import 'package:build_engine/src/plugins/item/item_lifecycle.dart';
import 'package:build_engine/src/plugins/item/item_rules.dart';
import 'package:build_engine/src/plugins/item/item_vocabulary.dart';
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
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  late PluginContext context;

  setUp(() {
    context = _newContext();
    context.content.loadAll(itemContentDefinitions);
    for (final rule in buildItemUsabilityRules([
      itemDefinition(ItemIds.ironSword, context),
    ])) {
      context.rules.register(rule);
    }
    context.mastery.define(
      const MasteryDefinition(subject: 'item:iron_sword', thresholds: [10, 25]),
    );
  });

  test('ownItem creates an ItemInstance referencing the definition', () {
    final owner = context.entities.create();

    final itemEntity = ownItem(owner, ItemIds.ironSword, context);

    expect(context.components.get<ItemInstance>(itemEntity)!.definitionId,
        equals(ItemIds.ironSword));
    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
  });

  test('an item can be discovered', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);

    discoverItem(owner, ironSword, context);

    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.discovered));
  });

  test('a discovered item stays LOCKED (not usable) with insufficient mastery', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);

    expect(isItemUsable(owner, ironSword, context), isFalse);
  });

  test('mastery increases through the generic Mastery system', () {
    final owner = context.entities.create();

    context.mastery.increase(owner, 'item:iron_sword', 10);

    expect(context.mastery.levelOf(owner, 'item:iron_sword'), equals(1));
  });

  test('item becomes USABLE once mastery reaches the required level', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);

    context.mastery.increase(owner, 'item:iron_sword', 25);

    expect(isItemUsable(owner, ironSword, context), isTrue);
    // the usability rule also promoted Discovery to unlocked:
    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.unlocked));
  });

  test('an unusable item cannot enter the Tome', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    expect(
      () => addItemToTome(owner, const SlotId('weapon'), ironSword, context),
      throwsA(isA<ItemNotUsableException>()),
    );
    expect(context.tome.inspect(owner), isEmpty);
  });

  test('a usable item can enter the Tome and becomes ACTIVE', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');

    ItemAddedToTome? published;
    context.events.subscribe<ItemAddedToTome>((e) => published = e);

    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);
    expect(published, isNotNull);
    expect(published!.definitionId, equals(ItemIds.ironSword));
  });

  test('OWNED/DISCOVERED/USABLE/ACTIVE are independently queryable, not one boolean', () {
    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');
    ownItem(owner, ItemIds.ironSword, context);

    // Owned, but not discovered/usable/active yet.
    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
    expect(isItemUsable(owner, ironSword, context), isFalse);
    expect(isItemActive(owner, ItemIds.ironSword, context), isFalse);

    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    addItemToTome(owner, const SlotId('weapon'), ironSword, context);

    expect(isItemOwned(owner, ItemIds.ironSword, context), isTrue);
    expect(isItemUsable(owner, ironSword, context), isTrue);
    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);
  });

  test('an item with no requirement is usable immediately once discovered', () {
    final owner = context.entities.create();
    final knife = itemDefinition(ItemIds.knife, context);

    discoverItem(owner, knife, context);

    expect(isItemUsable(owner, knife, context), isTrue);
  });
}
```

- [ ] **Step 4: Run tests to verify they fail, then pass**

Run: `dart test test/plugins/item/item_lifecycle_test.dart`
Expected: FAIL first, then PASS once Steps 1–2 exist.

---

### Task 5: `ItemPlugin` + barrel

**Files:**
- Create: `lib/src/plugins/item/item_plugin.dart`
- Create: `lib/item_plugin.dart`
- Test: `test/plugins/item/item_plugin_test.dart`

**Interfaces:**
- Consumes: every file from Tasks 1–4.
- Produces: `class ItemPlugin extends GamePlugin` (`id => 'item'`, `dependencies => const []`).

- [ ] **Step 1: Write `lib/src/plugins/item/item_plugin.dart`**

```dart
import 'package:build_engine/build_engine.dart';

import 'item_content.dart';
import 'item_instance.dart';
import 'item_rules.dart';
import 'item_vocabulary.dart';

/// The Item plugin: generic physical equipment (Knife, Iron Sword,
/// Gloves, Training Staff, Cloth Armor, Training Shoes), built entirely
/// with `PluginSdk`, depending on nothing but Core — not Combat, not
/// MartialArts, not Elemental. A second proof (after `ElementalPlugin`)
/// that "copy Elemental, not MartialArts" produces a fully decoupled
/// content plugin.
///
/// Tome rejection of an unusable item is enforced at `addItemToTome`
/// (`item_lifecycle.dart`), not inside `TomeService`/`Container`:
/// `PlacementRule.isSatisfied(ContainerView, EntityId item, Set<SlotId>)`
/// has no owner parameter, so a placement rule has no way to look up
/// *whose* Discovery/Mastery state to check — `Container` is deliberately
/// content-agnostic and shared by any future container shape (backpack,
/// weapon rack, skill board), not just the Tome. Gating at the plugin's
/// own call boundary into `TomeService.insert` needs no Core/Tome change
/// at all, per the milestone's "do not modify Tome internals
/// unnecessarily."
class ItemPlugin extends GamePlugin {
  @override
  String get id => 'item';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can be
  /// `initialize`d again after `unregister`.
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerComponentCleanup<ItemInstance>();

    sdk.registerTag('item', description: 'Generic physical equipment.');
    sdk.registerTag(ItemCategories.weapon, description: 'A wielded weapon item.');
    sdk.registerTag(ItemCategories.armor, description: 'A worn armor item.');
    sdk.registerTag(ItemCategories.footwear, description: 'A worn footwear item.');

    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find(ItemIds.knife) == null) {
      sdk.registerContentBatch(itemContentDefinitions);
    }

    for (final json in itemContentDefinitions) {
      final masteryRaw =
          (json['requirements'] as Map?)?['mastery'] as Map?;
      final thresholds = masteryRaw?['thresholds'] as List?;
      if (masteryRaw != null && thresholds != null) {
        context.mastery.define(MasteryDefinition(
          subject: masteryRaw['subject'] as String,
          thresholds: thresholds.cast<num>(),
        ));
      }
    }

    final definitions = [
      for (final json in itemContentDefinitions)
        itemDefinition(json['id'] as String, context),
    ];
    for (final rule in buildItemUsabilityRules(definitions)) {
      sdk.registerRule(rule);
    }
  }

  /// Mirrors [initialize]: cancels every subscription taken out there —
  /// component cleanup and every item's usability rule — so an
  /// unregistered `ItemPlugin` stops reacting to events entirely, the
  /// same teardown discipline every other plugin in this engine follows.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
```

- [ ] **Step 2: Write the barrel `lib/item_plugin.dart`**

```dart
/// The Item plugin's public surface — import this, never
/// `package:build_engine/src/plugins/item/...` directly.
library;

export 'src/plugins/item/item_definition.dart';
export 'src/plugins/item/item_events.dart';
export 'src/plugins/item/item_instance.dart';
export 'src/plugins/item/item_lifecycle.dart';
export 'src/plugins/item/item_plugin.dart';
export 'src/plugins/item/item_requirement.dart';
export 'src/plugins/item/item_rules.dart';
export 'src/plugins/item/item_vocabulary.dart';
export 'src/plugins/item/item_content.dart' show itemContentDefinitions, itemDefinition, itemDefinitionFromContent;
```

- [ ] **Step 3: Write the failing test** — `test/plugins/item/item_plugin_test.dart` (mirrors `test/plugins/elemental/elemental_plugin_test.dart`)

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
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
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('declares no dependencies', () {
    expect(ItemPlugin().dependencies, isEmpty);
  });

  test('initialize registers all 6 items and the mastery definitions', () {
    final context = _newContext();
    ItemPlugin().initialize(context);

    for (final id in [
      ItemIds.knife,
      ItemIds.ironSword,
      ItemIds.gloves,
      ItemIds.trainingStaff,
      ItemIds.clothArmor,
      ItemIds.trainingShoes,
    ]) {
      expect(context.content.get(id), isNotNull);
    }
    expect(context.mastery.definitionOf('item:iron_sword'), isNotNull);
  });

  test('unregister stops the usability rule from firing', () {
    final context = _newContext();
    final plugin = ItemPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);

    // Discovery is never auto-promoted without the rule.
    expect(context.discovery.stateOf(owner, 'item:iron_sword'),
        equals(DiscoveryState.discovered));
  });

  test('re-initializing on the same context does not throw ContentDuplicateIdException', () {
    final context = _newContext();
    final plugin = ItemPlugin();
    plugin.initialize(context);
    plugin.unregister(context);

    expect(() => plugin.initialize(context), returnsNormally);
    expect(context.content.get(ItemIds.knife).type, equals('weapon'));
  });

  test('ItemPlugin runs standalone (no Combat, no MartialArts) and is fully removable', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(ItemPlugin());
    manager.initialize(context);
    manager.start(context);

    final owner = context.entities.create();
    final ironSword = itemDefinition(ItemIds.ironSword, context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );
    context.tome.createTome(owner, 'basic_tome');
    discoverItem(owner, ironSword, context);
    context.mastery.increase(owner, 'item:iron_sword', 25);
    addItemToTome(owner, const SlotId('weapon'), ironSword, context);
    expect(isItemActive(owner, ItemIds.ironSword, context), isTrue);

    manager.stop(context);
    manager.unregister(context);

    final ownedEntity = ownItem(owner, ItemIds.ironSword, context);
    context.entities.destroy(ownedEntity);
    // cleanup subscription was cancelled; nothing throws either way —
    // this only proves teardown ran without leaving a dangling handler.
  });
}
```

- [ ] **Step 4: Run tests to verify they fail, then pass**

Run: `dart test test/plugins/item/item_plugin_test.dart`
Expected: FAIL first, then PASS.

---

### Task 6: Architecture dependency checks + end-to-end integration test

**Files:**
- Modify: `test/integration/architecture_dependency_test.dart`
- Create: `test/integration/item_end_to_end_test.dart`

**Interfaces:**
- Consumes: `ItemPlugin` and everything under `lib/item_plugin.dart` (Task 5).

- [ ] **Step 1: Add the Item barrel and symmetric groups to `architecture_dependency_test.dart`**

Add to the existing barrel constant list:

```dart
const _itemBarrel = 'item_plugin.dart';
const _pluginBarrels = [
  _combatBarrel,
  _martialArtsBarrel,
  _elementalBarrel,
  _physiqueBarrel,
  _autoCombatBarrel,
  _itemBarrel,
];
```

Add a new group (placed after the existing `'Combat remains unaware of both content plugins'` group, before group H — group H automatically picks up `_itemBarrel` via the updated `_pluginBarrels` list with no further change needed):

```dart
group('Item plugin is fully decoupled from every other plugin', () {
  test('Item does not reference MartialArts', () {
    _assertNoPluginImport(
        'martial_arts', _martialArtsBarrel, 'lib/src/plugins/item');
  });

  test('Item does not reference Elemental', () {
    _assertNoPluginImport(
        'elemental', _elementalBarrel, 'lib/src/plugins/item');
  });

  test('Item does not reference Physique', () {
    _assertNoPluginImport(
        'physique', _physiqueBarrel, 'lib/src/plugins/item');
  });

  test('Item does not reference Combat', () {
    _assertNoPluginImport('combat', _combatBarrel, 'lib/src/plugins/item');
  });

  test('Item does not reference AutoCombat', () {
    _assertNoPluginImport(
        'auto_combat', _autoCombatBarrel, 'lib/src/plugins/item');
  });
});
```

- [ ] **Step 2: Run the modified file to verify it fails until Task 5 exists, then passes**

Run: `dart test test/integration/architecture_dependency_test.dart`
Expected: FAIL before Task 5's files exist (`lib/src/plugins/item` missing);
PASS after.

- [ ] **Step 3: Write `test/integration/item_end_to_end_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
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
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test(
      'full item lifecycle: discover -> locked -> mastery training -> '
      'usable -> Tome', () {
    final context = _newContext();
    ItemPlugin().initialize(context);
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
    );

    final character = context.characters.create();
    context.tome.createTome(character, 'basic_tome');
    final ironSword = itemDefinition(ItemIds.ironSword, context);

    // discover -> LOCKED
    discoverItem(character, ironSword, context);
    expect(context.discovery.stateOf(character, 'item:iron_sword'),
        equals(DiscoveryState.discovered));
    expect(isItemUsable(character, ironSword, context), isFalse);
    expect(
      () => addItemToTome(character, const SlotId('weapon'), ironSword, context),
      throwsA(isA<ItemNotUsableException>()),
    );

    // train mastery (below requirement) -> still LOCKED
    context.mastery.increase(character, 'item:iron_sword', 10);
    expect(context.mastery.levelOf(character, 'item:iron_sword'), equals(1));
    expect(isItemUsable(character, ironSword, context), isFalse);

    // train mastery to the requirement -> USABLE
    context.mastery.increase(character, 'item:iron_sword', 15);
    expect(context.mastery.levelOf(character, 'item:iron_sword'), equals(2));
    expect(isItemUsable(character, ironSword, context), isTrue);

    // -> Tome
    addItemToTome(character, const SlotId('weapon'), ironSword, context);
    final build = context.tome.resolve(character);
    expect(
      build.components.any((c) =>
          c.referenceType == itemReferenceType && c.contentId == ItemIds.ironSword),
      isTrue,
    );
    expect(isItemActive(character, ItemIds.ironSword, context), isTrue);
  });

  test('deterministic: two identically-seeded runs reach the same ActiveBuild', () {
    List<(String, String)> runOnce() {
      final context = _newContext();
      ItemPlugin().initialize(context);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon']),
      );
      final character = context.characters.create();
      context.tome.createTome(character, 'basic_tome');
      final ironSword = itemDefinition(ItemIds.ironSword, context);

      discoverItem(character, ironSword, context);
      context.mastery.increase(character, 'item:iron_sword', 25);
      addItemToTome(character, const SlotId('weapon'), ironSword, context);

      return context.tome
          .resolve(character)
          .components
          .map((c) => (c.referenceType, c.contentId))
          .toList();
    }

    expect(runOnce(), equals(runOnce()));
  });
}
```

- [ ] **Step 4: Run all Item tests together**

Run: `dart test test/plugins/item/ test/integration/item_end_to_end_test.dart test/integration/architecture_dependency_test.dart`
Expected: PASS.

---

### Task 7: Full quality gate

**Files:** none (verification only).

- [ ] **Step 1: Run the full suite**

Run: `dart test`
Expected: PASS — baseline 714 + this plan's new tests, zero regressions.

- [ ] **Step 2: Run analyzer**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 3: Do not commit** (per the milestone's explicit instruction). Leave the working tree as-is for the requester to review and commit themselves.

---

## Self-Review Notes

- **Spec coverage:** lifecycle states (UNKNOWN/DISCOVERED/LOCKED/USABLE via
  `DiscoveryState`; OWNED via `ItemInstance`; ACTIVE via `TomeService.inspect`)
  — Task 1/4. Content set of 6 — Task 2. Generic eligibility via
  Condition/Query/Rule — Task 4. Tome rejection without modifying Tome —
  Task 4/5's `addItemToTome`. Events — Task 3 (`ItemAddedToTome`) + reused
  generic events (documented, not re-implemented). All 13 named test
  scenarios — Tasks 1, 2, 4, 6. Dependency isolation (#10/#11) — Task 6.
  Determinism (#12) — Task 6. Regression safety (#13) — Task 7.
- **Not implemented, by design, per "DO NOT IMPLEMENT":** UI, shops,
  crafting, loot tables, combat action interpretation (the `ItemDefinition
  .modifiersFor`/properties capability is exposed but never auto-applied),
  new combat mechanics, magic/cultivation/meta progression.
