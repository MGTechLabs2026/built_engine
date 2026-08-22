# MartialArts Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement MartialArts as the first content plugin on `build_engine`: 3 styles, 2 resources, 11 tags, 6 techniques, 3 stances, 5 items, 3 trinkets, and the three named interactions (Boxing momentum generation, Shaolin defensive synergy, Tai Chi counter/redirect) — built entirely on Combat's and Core's already-public APIs, with zero changes to either.

**Architecture:** Styles are marker tags, not components. One `MartialTechniqueAction extends CombatAction` class (mirroring `AttackAction`) covers all 6 techniques and 3 stances via data. One `MartialItemDefinition` class covers all 5 items and 3 trinkets — items grant static `Modifier`s at equip time, trinkets are Rule-driven passives. Cross-entity mechanics (Shaolin mitigation, Tai Chi counter) react to Combat's existing `EntityDamaged`/`ActionCompleted` events via `Rule`s registered through `context.rules` — never by intercepting `AttackAction`/`Damage` (which would require editing Combat). `MartialArtsPlugin.unregister` cancels every rule subscription it took out, mirroring `CombatPlugin`'s own teardown discipline.

**Tech Stack:** Dart (SDK `^3.7.0`), `package:test`, existing `build_engine` core services, and Combat's public API (`CombatAction`, `CombatSystem`, `CombatPlugin`, Combat's events, `CombatantComponent`).

**Spec:** `docs/superpowers/specs/2026-08-23-martial-arts-plugin-design.md`

All paths below are relative to the repo root: `/Users/m4maxpro/Projects/Tome:RougelikeGame`.

## Global Constraints

- No file under `lib/src/` outside `lib/src/plugins/martial_arts/` is created or modified by this plan. Combat and Core are read-only dependencies.
- MartialArts imports Combat/Core exclusively via `package:build_engine/build_engine.dart` and `package:build_engine/combat_plugin.dart` — never `lib/src/...` internals.
- `MartialArtsPlugin` never holds a reference to `CombatPlugin`/`CombatSystem` — only to Combat's public event types, reached via `context.rules`/`context.events`.
- Cross-entity mechanics (Shaolin mitigation, Tai Chi counter) are implemented as `Rule`s reacting to Combat's existing events (`EntityDamaged`, `ActionCompleted`) — never by adding a hook to `AttackAction`/`Damage`.
- `MartialArtsPlugin.dependencies => const ['combat']`. Every `EventSubscription` `context.rules.register(...)` returns during `initialize` is captured and cancelled in `unregister`.
- Resource thresholds always leave the resource at exactly 0 at the minimum qualifying value (condition threshold = cost − 1) — never allow a technique to leave a resource negative.
- No spatial/`Container` usage, no unequip/un-learn support, no AI — out of scope per the spec.
- Every task ends with `dart analyze` reporting zero issues and `dart test` passing, before commit.

---

### Task 1: Styles (`martial_styles.dart`)

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_styles.dart`
- Create: `lib/martial_arts_plugin.dart` (new public export barrel for this plugin)
- Test: `test/plugins/martial_arts/martial_styles_test.dart`

**Interfaces:**
- Consumes: `EntityId`, `PluginContext`, `AddTag`, `RuleContext`, `EventCounter`, `Modifier`, `ModifierSource`, `ModifierOperation`, `HasTagQuery` (all core, via `build_engine.dart`).
- Produces: `abstract final class MartialStyles { static const boxing = 'boxing'; static const shaolin = 'shaolin'; static const taiChi = 'taiChi'; }` and `void learnStyle(EntityId entity, String styleId, PluginContext context)`. Every later task's content (techniques, tests) references `MartialStyles.boxing`/`.shaolin`/`.taiChi` and calls `learnStyle`.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/martial_arts/martial_styles_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  );
}

void main() {
  group('learnStyle', () {
    test('grants the martial tag and a style:<id> tag', () {
      final context = _newContext();
      final entity = context.entities.create();

      learnStyle(entity, MartialStyles.boxing, context);

      final tags = context.components.get<TagSet>(entity)!.tags;
      expect(tags, containsAll({'martial', 'style:boxing'}));
    });

    test('learning shaolin additionally registers the offense/defense '
        'synergy modifier', () {
      final context = _newContext();
      final entity = context.entities.create();

      learnStyle(entity, MartialStyles.shaolin, context);

      final inactive = context.modifiers
          .activeModifiersFor(entity, 'palm', context.components);
      expect(inactive, isEmpty);

      context.components.add(entity, TagSet({'stance:iron_body'}));
      final active = context.modifiers
          .activeModifiersFor(entity, 'palm', context.components);
      expect(active, hasLength(1));
      expect(active.single.value, equals(4));
      expect(active.single.operation, equals(ModifierOperation.add));
    });

    test('learning boxing or taiChi registers no modifier', () {
      final context = _newContext();
      final boxer = context.entities.create();
      final taiChiPractitioner = context.entities.create();
      context.components.add(boxer, TagSet({'stance:iron_body'}));
      context.components.add(taiChiPractitioner, TagSet({'stance:iron_body'}));

      learnStyle(boxer, MartialStyles.boxing, context);
      learnStyle(taiChiPractitioner, MartialStyles.taiChi, context);

      expect(
        context.modifiers.activeModifiersFor(boxer, 'palm', context.components),
        isEmpty,
      );
      expect(
        context.modifiers
            .activeModifiersFor(taiChiPractitioner, 'palm', context.components),
        isEmpty,
      );
    });

    test('style id constants have the expected values', () {
      expect(MartialStyles.boxing, equals('boxing'));
      expect(MartialStyles.shaolin, equals('shaolin'));
      expect(MartialStyles.taiChi, equals('taiChi'));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/martial_arts/martial_styles_test.dart`
Expected: FAIL — `Error: Not found: 'package:build_engine/martial_arts_plugin.dart'`.

- [ ] **Step 3: Implement `MartialStyles`/`learnStyle` and the barrel file**

Create `lib/src/plugins/martial_arts/martial_styles.dart`:
```dart
import 'package:build_engine/build_engine.dart';

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

RuleContext _standaloneContext(EntityId subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

/// Grants [entity] the `martial` and `style:$styleId` tags. Learning
/// [MartialStyles.shaolin] additionally registers a permanent conditional
/// `Modifier` — `+4 add` to `palm`, active only while `stance:iron_body`
/// is present — implementing Shaolin's defensive-synergy-into-offense
/// mechanic entirely through the Modifier Engine. This content-specific
/// branch belongs here, in the content plugin, not in Core or Combat.
void learnStyle(EntityId entity, String styleId, PluginContext context) {
  final ctx = _standaloneContext(entity, context);
  const AddTag('martial').apply(ctx);
  AddTag('style:$styleId').apply(ctx);
  if (styleId == MartialStyles.shaolin) {
    context.modifiers.add(Modifier(
      source: ModifierSource('style:shaolin:synergy:${entity.value}'),
      target: entity,
      stat: 'palm',
      operation: ModifierOperation.add,
      value: 4,
      condition: HasTagQuery('stance:iron_body'),
    ));
  }
}
```

Create `lib/martial_arts_plugin.dart`:
```dart
/// MartialArts — the first content plugin built on Combat. Boxing,
/// Shaolin, and Tai Chi styles, techniques, stances, items, and trinkets,
/// expressed entirely through Combat's and Core's public APIs. Depends on
/// `package:build_engine/combat_plugin.dart` (`claude.md`'s DEPENDENCY
/// RULE: `MartialArts -> Combat -> Core`) — never the reverse, and never
/// modifies either.
library;

export 'src/plugins/martial_arts/martial_styles.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/martial_arts/martial_styles_test.dart
dart analyze
```
Expected: all 4 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/martial_arts/martial_styles.dart lib/martial_arts_plugin.dart test/plugins/martial_arts/martial_styles_test.dart
git commit -m "feat: add MartialArts styles (learnStyle, Shaolin synergy modifier)"
```

---

### Task 2: `MartialLoadoutComponent`

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_loadout_component.dart`
- Modify: `lib/martial_arts_plugin.dart`
- Test: `test/plugins/martial_arts/martial_loadout_component_test.dart`

**Interfaces:**
- Consumes: `EntityId` (core).
- Produces: `class MartialLoadoutComponent { const MartialLoadoutComponent({required List<EntityId> equippedItems}); final List<EntityId> equippedItems; Map<String, dynamic> toJson(); factory MartialLoadoutComponent.fromJson(Map<String, dynamic>); }`. Task 4's `equipItem` reads and replaces this component.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/martial_arts/martial_loadout_component_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

void main() {
  group('MartialLoadoutComponent', () {
    test('stores the equipped item ids', () {
      const component = MartialLoadoutComponent(
        equippedItems: [EntityId(1), EntityId(2)],
      );
      expect(
        component.equippedItems,
        equals([const EntityId(1), const EntityId(2)]),
      );
    });

    test('round-trips through toJson/fromJson', () {
      const component = MartialLoadoutComponent(
        equippedItems: [EntityId(3), EntityId(4)],
      );
      final restored = MartialLoadoutComponent.fromJson(component.toJson());
      expect(restored.equippedItems, equals(component.equippedItems));
    });

    test('round-trips an empty loadout', () {
      const component = MartialLoadoutComponent(equippedItems: []);
      final restored = MartialLoadoutComponent.fromJson(component.toJson());
      expect(restored.equippedItems, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/martial_arts/martial_loadout_component_test.dart`
Expected: FAIL — `Error: Undefined class 'MartialLoadoutComponent'`.

- [ ] **Step 3: Implement `MartialLoadoutComponent`**

Create `lib/src/plugins/martial_arts/martial_loadout_component.dart`:
```dart
import 'package:build_engine/build_engine.dart';

/// The item entities currently equipped on a combatant, in equip order.
/// Plugin-local state — this is what a future query or UI would read to
/// answer "what is this combatant wearing."
class MartialLoadoutComponent {
  const MartialLoadoutComponent({required this.equippedItems});

  final List<EntityId> equippedItems;

  /// A plain, stable structure — no engine-wide Serialization
  /// integration, matching `CombatStateComponent`'s module-local
  /// precedent.
  Map<String, dynamic> toJson() =>
      {'equippedItems': [for (final id in equippedItems) id.value]};

  factory MartialLoadoutComponent.fromJson(Map<String, dynamic> json) =>
      MartialLoadoutComponent(
        equippedItems: [
          for (final value in json['equippedItems'] as List<dynamic>)
            EntityId(value as int),
        ],
      );
}
```

Modify `lib/martial_arts_plugin.dart` — `martial_loadout_component.dart` sorts before `martial_styles.dart` (`l` < `s`):
```dart
/// MartialArts — the first content plugin built on Combat. Boxing,
/// Shaolin, and Tai Chi styles, techniques, stances, items, and trinkets,
/// expressed entirely through Combat's and Core's public APIs. Depends on
/// `package:build_engine/combat_plugin.dart` (`claude.md`'s DEPENDENCY
/// RULE: `MartialArts -> Combat -> Core`) — never the reverse, and never
/// modifies either.
library;

export 'src/plugins/martial_arts/martial_loadout_component.dart';
export 'src/plugins/martial_arts/martial_styles.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/martial_arts/martial_loadout_component_test.dart
dart analyze
```
Expected: all 3 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/martial_arts/martial_loadout_component.dart lib/martial_arts_plugin.dart test/plugins/martial_arts/martial_loadout_component_test.dart
git commit -m "feat: add MartialLoadoutComponent"
```

---

### Task 3: `TaiChiCounterCondition`

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_conditions.dart`
- Modify: `lib/martial_arts_plugin.dart`
- Test: `test/plugins/martial_arts/martial_conditions_test.dart`

**Interfaces:**
- Consumes: `Condition`, `RuleContext`, `QueryScope`, `HasTagQuery`, `EntityId`, `ComponentStore`, `TagSet` (core); `ActionCompleted` (Combat, via `combat_plugin.dart`).
- Produces: `class TaiChiCounterCondition implements Condition { const TaiChiCounterCondition(); bool evaluate(RuleContext context); }`. Task 6's Tai Chi counter `Rule` consumes this directly.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/martial_arts/martial_conditions_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

RuleContext _contextFor(Object triggerEvent, {ComponentStore? components}) {
  final events = EventBus();
  return RuleContext(
    subject: null,
    triggerEvent: triggerEvent,
    entities: EntityRegistry(events),
    components: components ?? ComponentStore(),
    events: events,
    rng: RngService(1),
    eventCounts: EventCounter(events),
  );
}

void main() {
  group('TaiChiCounterCondition', () {
    const attacker = EntityId(1);
    const battle = EntityId(99);

    test('matches when a target has the tai chi stance tag', () {
      final components = ComponentStore();
      const defender = EntityId(2);
      components.add(defender, TagSet({'stance:tai_chi'}));
      final action = AttackAction(
        actor: attacker,
        targets: const [defender],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionCompleted(battle, attacker, const [defender], action),
          components: components,
        ),
      );

      expect(matches, isTrue);
    });

    test('does not match when no target has the stance tag', () {
      final components = ComponentStore();
      const defender = EntityId(2);
      final action = AttackAction(
        actor: attacker,
        targets: const [defender],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionCompleted(battle, attacker, const [defender], action),
          components: components,
        ),
      );

      expect(matches, isFalse);
    });

    test('matches if any of several targets has the stance tag', () {
      final components = ComponentStore();
      const defenderA = EntityId(2);
      const defenderB = EntityId(3);
      components.add(defenderB, TagSet({'stance:tai_chi'}));
      final action = AttackAction(
        actor: attacker,
        targets: const [defenderA, defenderB],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionCompleted(battle, attacker, const [defenderA, defenderB], action),
          components: components,
        ),
      );

      expect(matches, isTrue);
    });

    test('does not match a different event type', () {
      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(const Object()),
      );
      expect(matches, isFalse);
    });

    test('does not match ActionStarted (only ActionCompleted)', () {
      final components = ComponentStore();
      const defender = EntityId(2);
      components.add(defender, TagSet({'stance:tai_chi'}));
      final action = AttackAction(
        actor: attacker,
        targets: const [defender],
        baseDamage: 5,
        damageStat: 'attack',
      );

      final matches = const TaiChiCounterCondition().evaluate(
        _contextFor(
          ActionStarted(battle, attacker, const [defender], action),
          components: components,
        ),
      );

      expect(matches, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/martial_arts/martial_conditions_test.dart`
Expected: FAIL — `Error: Undefined class 'TaiChiCounterCondition'`.

- [ ] **Step 3: Implement `TaiChiCounterCondition`**

Create `lib/src/plugins/martial_arts/martial_conditions.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// Matches when the rule's triggering event is an `ActionCompleted` whose
/// `targets` include at least one entity tagged `stance:tai_chi` —
/// regardless of who the attacker is, including a plain core
/// `AttackAction` from an entity with zero martial-arts awareness. Used
/// by the Tai Chi counter/redirect `Rule` (see `martial_arts_rules.dart`).
///
/// Known simplification: `ActionCompleted` publishes whether or not the
/// triggering action's own conditions passed (Combat exposes no "did it
/// land" flag on the event, and adding one would require modifying
/// Combat) — so this matches on any completed action targeting a Tai Chi
/// stance, landed or not.
class TaiChiCounterCondition implements Condition {
  const TaiChiCounterCondition();

  @override
  bool evaluate(RuleContext context) {
    final event = context.triggerEvent;
    if (event is! ActionCompleted) return false;
    final scope = QueryScope(components: context.components);
    return event.targets
        .any((target) => HasTagQuery('stance:tai_chi').matches(target, scope));
  }
}
```

Modify `lib/martial_arts_plugin.dart` — `martial_conditions.dart` sorts before `martial_loadout_component.dart` (`c` < `l`):
```dart
/// MartialArts — the first content plugin built on Combat. Boxing,
/// Shaolin, and Tai Chi styles, techniques, stances, items, and trinkets,
/// expressed entirely through Combat's and Core's public APIs. Depends on
/// `package:build_engine/combat_plugin.dart` (`claude.md`'s DEPENDENCY
/// RULE: `MartialArts -> Combat -> Core`) — never the reverse, and never
/// modifies either.
library;

export 'src/plugins/martial_arts/martial_conditions.dart';
export 'src/plugins/martial_arts/martial_loadout_component.dart';
export 'src/plugins/martial_arts/martial_styles.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/martial_arts/martial_conditions_test.dart
dart analyze
```
Expected: all 5 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/martial_arts/martial_conditions.dart lib/martial_arts_plugin.dart test/plugins/martial_arts/martial_conditions_test.dart
git commit -m "feat: add TaiChiCounterCondition"
```

---

### Task 4: Items and trinkets (`martial_item.dart`)

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_item.dart`
- Modify: `lib/martial_arts_plugin.dart`
- Test: `test/plugins/martial_arts/martial_item_test.dart`

**Interfaces:**
- Consumes: `EntityId`, `PluginContext`, `TagSet`, `Modifier`, `ModifierSource`, `ModifierOperation`, `ModifierResolver`, `AddTag`, `RuleContext` (core); `MartialLoadoutComponent` (Task 2).
- Produces: `class MartialItemDefinition { const MartialItemDefinition({required String id, required Set<String> tags, List<Modifier> Function(EntityId) modifiersFor}); }`; `EntityId equipItem(MartialItemDefinition item, EntityId wearer, PluginContext context)`; `const martialItems` (5), `const martialTrinkets` (3), and the 8 named item constants (`brassKnuckles`, `ironPalmWraps`, `taiChiSilkSash`, `sparringGloves`, `weightedVest`, `momentumTrinket`, `qiPendant`, `counterstrikeRing`). Task 5's techniques and Task 8's integration tests reference these constants and `equipItem` directly; Task 6's trinket-regen rules reference the string ids `'momentum_trinket'`/`'qi_pendant'` that `equipItem`'s `equipped:<id>` tag produces.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/martial_arts/martial_item_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  );
}

void main() {
  group('content lists', () {
    test('martialItems has 5 entries and martialTrinkets has 3', () {
      expect(martialItems, hasLength(5));
      expect(martialTrinkets, hasLength(3));
    });

    test('every item/trinket id is unique', () {
      final ids = [...martialItems, ...martialTrinkets].map((i) => i.id);
      expect(ids.toSet(), hasLength(8));
    });
  });

  group('equipItem', () {
    test('creates an item entity carrying the item\'s tags', () {
      final context = _newContext();
      final wearer = context.entities.create();

      final itemEntity = equipItem(brassKnuckles, wearer, context);

      expect(
        context.components.get<TagSet>(itemEntity)!.tags,
        equals(brassKnuckles.tags),
      );
    });

    test('registers the item\'s modifiers against the wearer', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(brassKnuckles, wearer, context);

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

      equipItem(brassKnuckles, wearer, context); // +6 add to punch
      equipItem(weightedVest, wearer, context); // x1.1 multiply on punch

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

      equipItem(brassKnuckles, wearer, context);

      final tags = context.components.get<TagSet>(wearer)!.tags;
      expect(tags, containsAll({'martial', 'style:boxing', 'equipped:brass_knuckles'}));
    });

    test('records the equipped item on MartialLoadoutComponent, '
        'accumulating across multiple equips', () {
      final context = _newContext();
      final wearer = context.entities.create();

      final first = equipItem(brassKnuckles, wearer, context);
      final second = equipItem(momentumTrinket, wearer, context);

      final loadout = context.components.get<MartialLoadoutComponent>(wearer)!;
      expect(loadout.equippedItems, equals([first, second]));
    });

    test('trinkets with no static modifiers register none', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipItem(momentumTrinket, wearer, context);

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

      equipItem(counterstrikeRing, wearer, context);

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

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/martial_arts/martial_item_test.dart`
Expected: FAIL — `Error: Undefined name 'martialItems'`.

- [ ] **Step 3: Implement `MartialItemDefinition`, `equipItem`, and content**

Create `lib/src/plugins/martial_arts/martial_item.dart`:
```dart
import 'package:build_engine/build_engine.dart';

import 'martial_loadout_component.dart';

/// A wearable item or trinket. Trinkets are simply items whose behavior
/// comes from a `Rule` reacting to their `equipped:<id>` tag (see
/// `martial_arts_rules.dart`) rather than from [modifiersFor] — one class
/// covers both, matching CLAUDE.md's "don't create a new source-code
/// class for every individual item" guidance.
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

RuleContext _standaloneContext(EntityId subject, PluginContext context) =>
    RuleContext(
      subject: subject,
      triggerEvent: const Object(),
      entities: context.entities,
      components: context.components,
      events: context.events,
      rng: context.rng,
      eventCounts: context.rules.eventCounts,
    );

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
  final ctx = _standaloneContext(wearer, context);
  AddTag('equipped:${item.id}').apply(ctx);
  final loadout = context.components.get<MartialLoadoutComponent>(wearer);
  context.components.add(
    wearer,
    MartialLoadoutComponent(
      equippedItems: [...?loadout?.equippedItems, itemEntity],
    ),
  );
  return itemEntity;
}

List<Modifier> _brassKnucklesModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:brass_knuckles:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 6,
      ),
    ];

const brassKnuckles = MartialItemDefinition(
  id: 'brass_knuckles',
  tags: {'martial', 'fist', 'western'},
  modifiersFor: _brassKnucklesModifiers,
);

List<Modifier> _ironPalmWrapsModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:iron_palm_wraps:${wearer.value}'),
        target: wearer,
        stat: 'palm',
        operation: ModifierOperation.add,
        value: 6,
      ),
    ];

const ironPalmWraps = MartialItemDefinition(
  id: 'iron_palm_wraps',
  tags: {'martial', 'palm', 'eastern'},
  modifiersFor: _ironPalmWrapsModifiers,
);

List<Modifier> _taiChiSilkSashModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:tai_chi_silk_sash:${wearer.value}'),
        target: wearer,
        stat: 'internal',
        operation: ModifierOperation.add,
        value: 5,
      ),
    ];

const taiChiSilkSash = MartialItemDefinition(
  id: 'tai_chi_silk_sash',
  tags: {'martial', 'internal', 'eastern', 'qi'},
  modifiersFor: _taiChiSilkSashModifiers,
);

List<Modifier> _sparringGlovesModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:sparring_gloves:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 3,
      ),
    ];

const sparringGloves = MartialItemDefinition(
  id: 'sparring_gloves',
  tags: {'martial', 'fist', 'western'},
  modifiersFor: _sparringGlovesModifiers,
);

List<Modifier> _weightedVestModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:weighted_vest:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.multiply,
        value: 1.1,
      ),
    ];

const weightedVest = MartialItemDefinition(
  id: 'weighted_vest',
  tags: {'martial', 'fist', 'western', 'external'},
  modifiersFor: _weightedVestModifiers,
);

const martialItems = [
  brassKnuckles,
  ironPalmWraps,
  taiChiSilkSash,
  sparringGloves,
  weightedVest,
];

const momentumTrinket = MartialItemDefinition(
  id: 'momentum_trinket',
  tags: {'martial', 'western'},
);

const qiPendant = MartialItemDefinition(
  id: 'qi_pendant',
  tags: {'martial', 'qi', 'eastern'},
);

List<Modifier> _counterstrikeRingModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:counterstrike_ring:${wearer.value}'),
        target: wearer,
        stat: 'internal',
        operation: ModifierOperation.add,
        value: 3,
        condition: HasTagQuery('stance:tai_chi'),
      ),
    ];

const counterstrikeRing = MartialItemDefinition(
  id: 'counterstrike_ring',
  tags: {'martial', 'eastern', 'counter'},
  modifiersFor: _counterstrikeRingModifiers,
);

const martialTrinkets = [momentumTrinket, qiPendant, counterstrikeRing];
```

Modify `lib/martial_arts_plugin.dart` — `martial_item.dart` sorts before `martial_loadout_component.dart` (`i` < `l`), and needs `learnStyle`/`MartialStyles` importable for the test file above, already exported:
```dart
/// MartialArts — the first content plugin built on Combat. Boxing,
/// Shaolin, and Tai Chi styles, techniques, stances, items, and trinkets,
/// expressed entirely through Combat's and Core's public APIs. Depends on
/// `package:build_engine/combat_plugin.dart` (`claude.md`'s DEPENDENCY
/// RULE: `MartialArts -> Combat -> Core`) — never the reverse, and never
/// modifies either.
library;

export 'src/plugins/martial_arts/martial_conditions.dart';
export 'src/plugins/martial_arts/martial_item.dart';
export 'src/plugins/martial_arts/martial_loadout_component.dart';
export 'src/plugins/martial_arts/martial_styles.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/martial_arts/martial_item_test.dart
dart analyze
```
Expected: all 9 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/martial_arts/martial_item.dart lib/martial_arts_plugin.dart test/plugins/martial_arts/martial_item_test.dart
git commit -m "feat: add MartialItemDefinition, equipItem, and 5 items + 3 trinkets"
```

---

### Task 5: `MartialTechniqueAction` and content (`martial_technique_action.dart`)

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_technique_action.dart`
- Modify: `lib/martial_arts_plugin.dart`
- Test: `test/plugins/martial_arts/martial_technique_action_test.dart`

**Interfaces:**
- Consumes: `EntityId`, `CombatAction`, `Condition`, `Effect`, `Damage`, `ModifyResource`, `ResourceAbove`, `AddTag`, `PluginContext`, `ModifierResolver` (core/Combat); `HasTag` — via `MartialStyles` string values (Task 1).
- Produces: `class MartialTechniqueAction extends CombatAction { ... }` and 9 factory functions: `jab`, `powerCross`, `guardStance` (Boxing); `palmStrike`, `blazingPalm`, `ironBodyStance` (Shaolin); `pushHands`, `whirlingPalm`, `yieldingStance` (Tai Chi) — each `({required EntityId actor, required List<EntityId> targets})`. Task 8's integration tests call these factories directly.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/martial_arts/martial_technique_action_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  );
}

void main() {
  group('MartialTechniqueAction attack techniques', () {
    test('jab requires style:boxing, costs nothing, grants momentum, and '
        'deals its base damage', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      learnStyle(actor, MartialStyles.boxing, context);

      final action = jab(actor: actor, targets: [target]);

      expect(action.conditions.every((c) => c.evaluate(
            RuleContext(
              subject: actor,
              triggerEvent: action,
              entities: context.entities,
              components: context.components,
              events: context.events,
              rng: context.rng,
              eventCounts: context.rules.eventCounts,
            ),
          )), isTrue);
      expect(action.costEffects, hasLength(1));
      final effects = action.effectsFor(target, context);
      expect(effects.single, isA<Damage>());
      expect((effects.single as Damage).amount, equals(6));
    });

    test('jab fails its condition without style:boxing', () {
      final context = _newContext();
      final actor = context.entities.create();
      final action = jab(actor: actor, targets: [context.entities.create()]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isFalse);
    });

    test('powerCross requires momentum above 19 and deals 18 base damage',
        () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      learnStyle(actor, MartialStyles.boxing, context);
      context.components.add(actor, ResourceComponent({'momentum': 20}));

      final action = powerCross(actor: actor, targets: [target]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isTrue);
      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(18));
      expect(action.costEffects, hasLength(1));
    });

    test('powerCross fails below the momentum threshold', () {
      final context = _newContext();
      final actor = context.entities.create();
      learnStyle(actor, MartialStyles.boxing, context);
      context.components.add(actor, ResourceComponent({'momentum': 19}));
      final action =
          powerCross(actor: actor, targets: [context.entities.create()]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isFalse);
    });

    test('palmStrike deals 8 base damage on the palm stat', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = palmStrike(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(8));
    });

    test('blazingPalm deals 14 base damage and is tagged fire', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = blazingPalm(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(14));
      expect(action.tags, contains('fire'));
    });

    test('pushHands deals 7 base damage on the internal stat', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = pushHands(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(7));
    });

    test('whirlingPalm deals 10 base damage and is tagged yang', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = whirlingPalm(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(10));
      expect(action.tags, contains('yang'));
    });

    test('attack damage resolves through registered modifiers, like '
        'AttackAction', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      context.modifiers.add(Modifier(
        source: const ModifierSource('test'),
        target: actor,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 6,
      ));

      final action = jab(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(12));
    });
  });

  group('MartialTechniqueAction stances', () {
    test('guardStance grants stance:guard and momentum, no damage', () {
      final context = _newContext();
      final actor = context.entities.create();
      final action = guardStance(actor: actor, targets: [actor]);

      final effects = action.effectsFor(actor, context);
      expect(effects, hasLength(2));
      expect(effects.whereType<Damage>(), isEmpty);
    });

    test('ironBodyStance requires qi above 4 and grants stance:iron_body',
        () {
      final context = _newContext();
      final actor = context.entities.create();
      context.components.add(actor, ResourceComponent({'qi': 5}));
      final action = ironBodyStance(actor: actor, targets: [actor]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isTrue);
      final effects = action.effectsFor(actor, context);
      expect(effects.single, isA<AddTag>());
    });

    test('yieldingStance requires qi above 2 and grants stance:tai_chi', () {
      final context = _newContext();
      final actor = context.entities.create();
      context.components.add(actor, ResourceComponent({'qi': 3}));
      final action = yieldingStance(actor: actor, targets: [actor]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isTrue);
      final effects = action.effectsFor(actor, context);
      expect(effects.single, isA<AddTag>());
    });
  });

  group('all 11 tags appear across the 9 techniques/stances', () {
    test('tag coverage', () {
      final actor = const EntityId(1);
      final targets = [actor];
      final allTags = <String>{
        ...jab(actor: actor, targets: targets).tags,
        ...powerCross(actor: actor, targets: targets).tags,
        ...guardStance(actor: actor, targets: targets).tags,
        ...palmStrike(actor: actor, targets: targets).tags,
        ...blazingPalm(actor: actor, targets: targets).tags,
        ...ironBodyStance(actor: actor, targets: targets).tags,
        ...pushHands(actor: actor, targets: targets).tags,
        ...whirlingPalm(actor: actor, targets: targets).tags,
        ...yieldingStance(actor: actor, targets: targets).tags,
      };

      expect(
        allTags,
        containsAll({
          'martial', 'fist', 'palm', 'internal', 'external', 'qi', 'yang',
          'fire', 'counter', 'western', 'eastern',
        }),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/martial_arts/martial_technique_action_test.dart`
Expected: FAIL — `Error: Undefined class 'MartialTechniqueAction'`.

- [ ] **Step 3: Implement `MartialTechniqueAction` and the 9 factories**

Create `lib/src/plugins/martial_arts/martial_technique_action.dart`:
```dart
import 'package:build_engine/build_engine.dart';

import 'martial_styles.dart';

/// One class for every technique and stance — the same "don't create a
/// new source-code class per content item" principle `AttackAction`
/// already demonstrates. Set [baseDamage]/[damageStat] together for an
/// attack technique (damage resolved through the Modifier Engine,
/// identical mechanism to `AttackAction`); leave both null and set
/// [selfEffects] instead for a stance/utility technique (with `targets:
/// [actor]` at the call site) — never set both kinds on one instance.
class MartialTechniqueAction extends CombatAction {
  const MartialTechniqueAction({
    required this.actor,
    required this.targets,
    required this.tags,
    this.conditions = const [],
    this.costEffects = const [],
    this.baseDamage,
    this.damageStat,
    this.selfEffects = const [],
  });

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;

  /// This technique's own tags (fist/palm/internal/etc) — content
  /// metadata, not read by any Condition in this plugin.
  final Set<String> tags;

  @override
  final List<Condition> conditions;
  @override
  final List<Effect> costEffects;

  final num? baseDamage;
  final String? damageStat;
  final List<Effect> selfEffects;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) {
    if (baseDamage != null) {
      final resolved = const ModifierResolver().resolve(
        baseDamage!,
        context.modifiers.activeModifiersFor(actor, damageStat!, context.components),
      );
      return [Damage(resolved)];
    }
    return selfEffects;
  }
}

// --- Boxing ---

MartialTechniqueAction jab({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'fist', 'western', 'external'},
      conditions: [HasTag(MartialStyles.boxing)],
      costEffects: const [ModifyResource('momentum', 8)],
      baseDamage: 6,
      damageStat: 'punch',
    );

MartialTechniqueAction powerCross({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'fist', 'western', 'external'},
      conditions: [
        HasTag(MartialStyles.boxing),
        const ResourceAbove('momentum', 19),
      ],
      costEffects: const [ModifyResource('momentum', -20)],
      baseDamage: 18,
      damageStat: 'punch',
    );

MartialTechniqueAction guardStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'fist', 'western'},
      conditions: [HasTag(MartialStyles.boxing)],
      selfEffects: const [
        AddTag('stance:guard'),
        ModifyResource('momentum', 5),
      ],
    );

// --- Shaolin ---

MartialTechniqueAction palmStrike({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'palm', 'eastern', 'external'},
      conditions: [
        HasTag(MartialStyles.shaolin),
        const ResourceAbove('qi', 2),
      ],
      costEffects: const [ModifyResource('qi', -3)],
      baseDamage: 8,
      damageStat: 'palm',
    );

MartialTechniqueAction blazingPalm({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'palm', 'eastern', 'fire', 'qi'},
      conditions: [
        HasTag(MartialStyles.shaolin),
        const ResourceAbove('qi', 7),
      ],
      costEffects: const [ModifyResource('qi', -8)],
      baseDamage: 14,
      damageStat: 'palm',
    );

MartialTechniqueAction ironBodyStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'qi', 'internal', 'eastern'},
      conditions: [
        HasTag(MartialStyles.shaolin),
        const ResourceAbove('qi', 4),
      ],
      costEffects: const [ModifyResource('qi', -5)],
      selfEffects: const [AddTag('stance:iron_body')],
    );

// --- Tai Chi ---

MartialTechniqueAction pushHands({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'internal', 'eastern', 'qi'},
      conditions: [
        HasTag(MartialStyles.taiChi),
        const ResourceAbove('qi', 3),
      ],
      costEffects: const [ModifyResource('qi', -4)],
      baseDamage: 7,
      damageStat: 'internal',
    );

MartialTechniqueAction whirlingPalm({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'internal', 'eastern', 'qi', 'yang'},
      conditions: [
        HasTag(MartialStyles.taiChi),
        const ResourceAbove('qi', 5),
      ],
      costEffects: const [ModifyResource('qi', -6)],
      baseDamage: 10,
      damageStat: 'internal',
    );

MartialTechniqueAction yieldingStance({
  required EntityId actor,
  required List<EntityId> targets,
}) =>
    MartialTechniqueAction(
      actor: actor,
      targets: targets,
      tags: const {'martial', 'internal', 'eastern', 'qi', 'counter'},
      conditions: [
        HasTag(MartialStyles.taiChi),
        const ResourceAbove('qi', 2),
      ],
      costEffects: const [ModifyResource('qi', -3)],
      selfEffects: const [AddTag('stance:tai_chi')],
    );
```

Modify `lib/martial_arts_plugin.dart` — `martial_technique_action.dart` sorts after `martial_styles.dart` (`t` > `s`):
```dart
/// MartialArts — the first content plugin built on Combat. Boxing,
/// Shaolin, and Tai Chi styles, techniques, stances, items, and trinkets,
/// expressed entirely through Combat's and Core's public APIs. Depends on
/// `package:build_engine/combat_plugin.dart` (`claude.md`'s DEPENDENCY
/// RULE: `MartialArts -> Combat -> Core`) — never the reverse, and never
/// modifies either.
library;

export 'src/plugins/martial_arts/martial_conditions.dart';
export 'src/plugins/martial_arts/martial_item.dart';
export 'src/plugins/martial_arts/martial_loadout_component.dart';
export 'src/plugins/martial_arts/martial_styles.dart';
export 'src/plugins/martial_arts/martial_technique_action.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/martial_arts/martial_technique_action_test.dart
dart analyze
```
Expected: all 14 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/martial_arts/martial_technique_action.dart lib/martial_arts_plugin.dart test/plugins/martial_arts/martial_technique_action_test.dart
git commit -m "feat: add MartialTechniqueAction and 6 techniques + 3 stances"
```

---

### Task 6: `martial_arts_rules.dart`

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_arts_rules.dart`
- Modify: `lib/martial_arts_plugin.dart`
- Test: `test/plugins/martial_arts/martial_arts_rules_test.dart`

**Interfaces:**
- Consumes: `Rule`, `HasTag`, `Heal`, `Damage`, `ModifyResource`, `EntityDamaged` (core); `ActionCompleted`, `TurnStarted` (Combat, via `combat_plugin.dart`); `TaiChiCounterCondition` (Task 3).
- Produces: `List<Rule> buildMartialArtsRules()` — returns exactly 4 `Rule`s in a fixed order: Shaolin defensive synergy, Tai Chi counter, Momentum Trinket regen, Qi Pendant regen. Task 7's `MartialArtsPlugin.initialize` consumes this directly.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/martial_arts/martial_arts_rules_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  );
}

void main() {
  test('buildMartialArtsRules returns exactly 4 rules', () {
    expect(buildMartialArtsRules(), hasLength(4));
  });

  group('Shaolin defensive synergy rule', () {
    test('heals the damaged entity while it has stance:iron_body', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final entity = context.entities.create();
      context.components.add(entity, TagSet({'stance:iron_body'}));
      context.components.add(entity, const HealthComponent(current: 50, max: 100));

      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(52));
    });

    test('does nothing without the stance tag', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final entity = context.entities.create();
      context.components.add(entity, const HealthComponent(current: 50, max: 100));

      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(50));
    });
  });

  group('Tai Chi counter rule', () {
    test('damages the actor when a target has stance:tai_chi', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final attacker = context.entities.create();
      final defender = context.entities.create();
      context.components.add(attacker, const HealthComponent(current: 100, max: 100));
      context.components.add(defender, TagSet({'stance:tai_chi'}));
      final battle = context.entities.create();
      final action = AttackAction(
        actor: attacker, targets: [defender], baseDamage: 5, damageStat: 'attack',
      );

      context.events.publish(ActionCompleted(battle, attacker, [defender], action));

      expect(context.components.get<HealthComponent>(attacker)!.current, equals(97));
    });

    test('does nothing when no target has the stance tag', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final attacker = context.entities.create();
      final defender = context.entities.create();
      context.components.add(attacker, const HealthComponent(current: 100, max: 100));
      final battle = context.entities.create();
      final action = AttackAction(
        actor: attacker, targets: [defender], baseDamage: 5, damageStat: 'attack',
      );

      context.events.publish(ActionCompleted(battle, attacker, [defender], action));

      expect(context.components.get<HealthComponent>(attacker)!.current, equals(100));
    });
  });

  group('trinket passive regen rules', () {
    test('momentum trinket regenerates momentum on the wearer\'s turn', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final wearer = context.entities.create();
      context.components.add(wearer, TagSet({'equipped:momentum_trinket'}));
      context.components.add(wearer, ResourceComponent({'momentum': 0}));
      final battle = context.entities.create();

      context.events.publish(TurnStarted(battle, wearer, 1));

      expect(
        context.components.get<ResourceComponent>(wearer)!.resources['momentum'],
        equals(3),
      );
    });

    test('qi pendant regenerates qi on the wearer\'s turn', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final wearer = context.entities.create();
      context.components.add(wearer, TagSet({'equipped:qi_pendant'}));
      context.components.add(wearer, ResourceComponent({'qi': 0}));
      final battle = context.entities.create();

      context.events.publish(TurnStarted(battle, wearer, 1));

      expect(
        context.components.get<ResourceComponent>(wearer)!.resources['qi'],
        equals(2),
      );
    });

    test('neither trinket rule fires without the matching tag', () {
      final context = _newContext();
      for (final rule in buildMartialArtsRules()) {
        context.rules.register(rule);
      }
      final entity = context.entities.create();
      context.components.add(entity, ResourceComponent({'momentum': 0, 'qi': 0}));
      final battle = context.entities.create();

      context.events.publish(TurnStarted(battle, entity, 1));

      final resources = context.components.get<ResourceComponent>(entity)!.resources;
      expect(resources['momentum'], equals(0));
      expect(resources['qi'], equals(0));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/martial_arts/martial_arts_rules_test.dart`
Expected: FAIL — `Error: Undefined name 'buildMartialArtsRules'`.

- [ ] **Step 3: Implement `buildMartialArtsRules`**

Create `lib/src/plugins/martial_arts/martial_arts_rules.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'martial_conditions.dart';

/// The 4 rules that give MartialArts its cross-entity behavior — all
/// reacting to Combat's existing public events, never intercepting
/// `AttackAction`/`Damage` directly (which would require modifying
/// Combat). Registered by `MartialArtsPlugin.initialize`.
List<Rule> buildMartialArtsRules() => [
      _shaolinDefensiveSynergyRule(),
      _taiChiCounterRule(),
      _passiveResourceRegenRule(
        requiresTag: 'equipped:momentum_trinket',
        resource: 'momentum',
        amount: 3,
      ),
      _passiveResourceRegenRule(
        requiresTag: 'equipped:qi_pendant',
        resource: 'qi',
        amount: 2,
      ),
    ];

/// WHEN a Shaolin entity in `stance:iron_body` takes damage, heal back a
/// portion of it. A reactive mitigation, not a block — `Damage`/
/// `AttackAction` are never touched.
Rule _shaolinDefensiveSynergyRule() => Rule(
      trigger: EntityDamaged,
      subjectOf: (event) => (event as EntityDamaged).id,
      conditions: const [HasTag('stance:iron_body')],
      effects: const [Heal(2)],
    );

/// WHEN any action completes against a target with `stance:tai_chi`,
/// redirect some damage back onto the attacker — regardless of what kind
/// of action or attacker it was.
Rule _taiChiCounterRule() => Rule(
      trigger: ActionCompleted,
      subjectOf: (event) => (event as ActionCompleted).actor,
      conditions: const [TaiChiCounterCondition()],
      effects: const [Damage(3)],
    );

/// One data-driven factory, called once per passive-regen trinket, rather
/// than two near-duplicate rules.
Rule _passiveResourceRegenRule({
  required String requiresTag,
  required String resource,
  required num amount,
}) =>
    Rule(
      trigger: TurnStarted,
      subjectOf: (event) => (event as TurnStarted).actor,
      conditions: [HasTag(requiresTag)],
      effects: [ModifyResource(resource, amount)],
    );
```

Modify `lib/martial_arts_plugin.dart` — `martial_arts_rules.dart` sorts before `martial_conditions.dart` (`arts_rules` vs `conditions`: common prefix `martial_`, then `a` < `c`):
```dart
/// MartialArts — the first content plugin built on Combat. Boxing,
/// Shaolin, and Tai Chi styles, techniques, stances, items, and trinkets,
/// expressed entirely through Combat's and Core's public APIs. Depends on
/// `package:build_engine/combat_plugin.dart` (`claude.md`'s DEPENDENCY
/// RULE: `MartialArts -> Combat -> Core`) — never the reverse, and never
/// modifies either.
library;

export 'src/plugins/martial_arts/martial_arts_rules.dart';
export 'src/plugins/martial_arts/martial_conditions.dart';
export 'src/plugins/martial_arts/martial_item.dart';
export 'src/plugins/martial_arts/martial_loadout_component.dart';
export 'src/plugins/martial_arts/martial_styles.dart';
export 'src/plugins/martial_arts/martial_technique_action.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/martial_arts/martial_arts_rules_test.dart
dart analyze
```
Expected: all 8 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/martial_arts/martial_arts_rules.dart lib/martial_arts_plugin.dart test/plugins/martial_arts/martial_arts_rules_test.dart
git commit -m "feat: add buildMartialArtsRules (Shaolin, Tai Chi, and trinket rules)"
```

---

### Task 7: `MartialArtsPlugin`

**Files:**
- Create: `lib/src/plugins/martial_arts/martial_arts_plugin.dart`
- Modify: `lib/martial_arts_plugin.dart`
- Test: `test/plugins/martial_arts/martial_arts_plugin_test.dart`

**Interfaces:**
- Consumes: `GamePlugin`, `PluginContext`, `PluginManager`, `EventSubscription` (core); `CombatPlugin` (Combat, via `combat_plugin.dart`); `buildMartialArtsRules` (Task 6).
- Produces: `class MartialArtsPlugin extends GamePlugin { String get id; String get version; List<String> get dependencies; void initialize(PluginContext context); void unregister(PluginContext context); }`. Task 8's integration tests consume `MartialArtsPlugin` directly, registered alongside `CombatPlugin`.

- [ ] **Step 1: Write the failing test**

Create `test/plugins/martial_arts/martial_arts_plugin_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  );
}

void main() {
  group('MartialArtsPlugin', () {
    test('has id "martial_arts", a version, and depends on "combat"', () {
      final plugin = MartialArtsPlugin();
      expect(plugin.id, equals('martial_arts'));
      expect(plugin.version, isNotEmpty);
      expect(plugin.dependencies, equals(['combat']));
    });

    test('initialize registers all 4 rules', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();

      plugin.initialize(context);

      final entity = context.entities.create();
      context.components.add(entity, TagSet({'stance:iron_body'}));
      context.components.add(entity, const HealthComponent(current: 50, max: 100));
      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(52));
    });

    test('unregister cancels every rule subscription — MartialArts stops '
        'reacting to events entirely', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);
      final entity = context.entities.create();
      context.components.add(entity, TagSet({'stance:iron_body'}));
      context.components.add(entity, const HealthComponent(current: 50, max: 100));

      plugin.unregister(context);
      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(50));
    });

    test('registers, initializes, starts, stops, and unregisters through '
        'PluginManager alongside CombatPlugin with no other plugin present',
        () {
      final context = _newContext();
      final manager = PluginManager();
      final combat = CombatPlugin();
      final martialArts = MartialArtsPlugin();
      manager.register(combat);
      manager.register(martialArts);

      manager.initialize(context);
      manager.start(context);

      final player = context.entities.create();
      final enemy = context.entities.create();
      context.components.add(player, const CombatantComponent(team: 'player', initiative: 10));
      context.components.add(enemy, const CombatantComponent(team: 'enemy', initiative: 5));
      context.components.add(player, const HealthComponent(current: 100, max: 100));
      context.components.add(enemy, const HealthComponent(current: 100, max: 100));
      learnStyle(player, MartialStyles.boxing, context);
      final battle = combat.system.startBattle([player, enemy]);
      combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));

      expect(context.components.get<HealthComponent>(enemy)!.current, equals(94));
      expect(() => manager.stop(context), returnsNormally);
      expect(() => manager.unregister(context), returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/plugins/martial_arts/martial_arts_plugin_test.dart`
Expected: FAIL — `Error: Undefined class 'MartialArtsPlugin'`.

- [ ] **Step 3: Implement `MartialArtsPlugin`**

Create `lib/src/plugins/martial_arts/martial_arts_plugin.dart`:
```dart
import 'package:build_engine/build_engine.dart';

import 'martial_arts_rules.dart';

/// MartialArts as an ordinary plugin: styles, techniques, stances, items,
/// and trinkets, expressed entirely through Combat's and Core's public
/// APIs. `dependencies => ['combat']` orders this plugin's lifecycle
/// after Combat's, but `MartialArtsPlugin` never holds a reference to
/// `CombatPlugin`/`CombatSystem` — only to Combat's public event
/// vocabulary, reached through the shared `RuleEngine` every plugin
/// already gets via `PluginContext`. Nothing in Combat's source
/// references MartialArts.
class MartialArtsPlugin extends GamePlugin {
  @override
  String get id => 'martial_arts';

  @override
  String get version => '0.1.0';

  @override
  List<String> get dependencies => const ['combat'];

  final List<EventSubscription> _subscriptions = [];

  @override
  void initialize(PluginContext context) {
    for (final rule in buildMartialArtsRules()) {
      _subscriptions.add(context.rules.register(rule));
    }
  }

  /// Mirrors [initialize]: cancels every rule subscription taken out
  /// there, so an unregistered `MartialArtsPlugin` stops reacting to
  /// events entirely — the same teardown discipline `CombatPlugin`
  /// established for its own `EntityKilled` subscription.
  @override
  void unregister(PluginContext context) {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

Modify `lib/martial_arts_plugin.dart` — `martial_arts_plugin.dart` sorts before `martial_arts_rules.dart` (`p` < `r` after common `martial_arts_` prefix):
```dart
/// MartialArts — the first content plugin built on Combat. Boxing,
/// Shaolin, and Tai Chi styles, techniques, stances, items, and trinkets,
/// expressed entirely through Combat's and Core's public APIs. Depends on
/// `package:build_engine/combat_plugin.dart` (`claude.md`'s DEPENDENCY
/// RULE: `MartialArts -> Combat -> Core`) — never the reverse, and never
/// modifies either.
library;

export 'src/plugins/martial_arts/martial_arts_plugin.dart';
export 'src/plugins/martial_arts/martial_arts_rules.dart';
export 'src/plugins/martial_arts/martial_conditions.dart';
export 'src/plugins/martial_arts/martial_item.dart';
export 'src/plugins/martial_arts/martial_loadout_component.dart';
export 'src/plugins/martial_arts/martial_styles.dart';
export 'src/plugins/martial_arts/martial_technique_action.dart';
```

- [ ] **Step 4: Run the test to verify it passes, and analyze**

Run:
```bash
dart test test/plugins/martial_arts/martial_arts_plugin_test.dart
dart analyze
```
Expected: all 4 tests PASS; `dart analyze` reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/plugins/martial_arts/martial_arts_plugin.dart lib/martial_arts_plugin.dart test/plugins/martial_arts/martial_arts_plugin_test.dart
git commit -m "feat: add MartialArtsPlugin"
```

---

### Task 8: Integration tests

**Files:**
- Create: `test/integration/martial_arts_end_to_end_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–7, plus `CombatPlugin`/Combat's events (Combat plugin, already merged to `main`).
- Produces: nothing new — verification-only.

- [ ] **Step 1: Write the integration tests**

Create `test/integration/martial_arts_end_to_end_test.dart`:
```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  );
}

void main() {
  test(
      'Player (Boxing, Brass Knuckles, Momentum Trinket) vs. a Generic '
      'Combatant enemy — the complete combat loop', () {
    final context = _newContext();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    combat.initialize(context);
    martialArts.initialize(context);

    final player = context.entities.create();
    final enemy = context.entities.create();
    context.components
        .add(player, const CombatantComponent(team: 'player', initiative: 10));
    context.components
        .add(enemy, const CombatantComponent(team: 'enemy', initiative: 5));
    context.components.add(player, const HealthComponent(current: 100, max: 100));
    context.components.add(enemy, const HealthComponent(current: 200, max: 200));
    context.components.add(player, ResourceComponent({'momentum': 0, 'qi': 0}));

    learnStyle(player, MartialStyles.boxing, context);
    equipItem(brassKnuckles, player, context);
    equipItem(momentumTrinket, player, context);

    final battle = combat.system.startBattle([player, enemy]);

    // Round 1 — player: Jab (6 base + 6 Brass Knuckles = 12), enemy: plain
    // core AttackAction, zero martial-arts awareness.
    //
    // Momentum timing note: the trinket's regen fires on TurnStarted for
    // the PLAYER's *next* turn — which `executeAction` publishes as part
    // of advancing the turn at the end of the *enemy's* preceding call
    // (the turn wraps back to the player there). So by the time each of
    // the two calls below has returned, that round's regen has already
    // landed: momentum after startBattle's initial TurnStarted(player,
    // round 1) is 0 + 3 = 3; Jab's own costEffects then add 8 (-> 11);
    // and by the time the enemy's call returns, advancing back to the
    // player for round 2 has already fired the next regen (+3 -> 14).
    combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));
    combat.system.executeAction(
      battle,
      AttackAction(actor: enemy, targets: [player], baseDamage: 5, damageStat: 'attack'),
    );
    expect(context.components.get<HealthComponent>(enemy)!.current, equals(188));
    expect(context.components.get<HealthComponent>(player)!.current, equals(95));
    // Momentum: 0 + 3 (round-1 regen) + 8 (Jab) + 3 (round-2 regen,
    // fired by the enemy's call above advancing the turn back to the
    // player) = 14.
    expect(
      context.components.get<ResourceComponent>(player)!.resources['momentum'],
      equals(14),
    );

    // Round 2 — another Jab.
    combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));
    combat.system.executeAction(
      battle,
      AttackAction(actor: enemy, targets: [player], baseDamage: 5, damageStat: 'attack'),
    );
    expect(context.components.get<HealthComponent>(enemy)!.current, equals(176));
    // Momentum: 14 + 8 (Jab) + 3 (round-3 regen, same timing as above) = 25.
    expect(
      context.components.get<ResourceComponent>(player)!.resources['momentum'],
      equals(25),
    );

    // Round 3 — momentum is already 25 (see above), clearing Power
    // Cross's threshold (> 19): 18 base + 6 Brass Knuckles = 24 damage,
    // then spends 20 momentum, leaving 5.
    combat.system.executeAction(battle, powerCross(actor: player, targets: [enemy]));
    expect(context.components.get<HealthComponent>(enemy)!.current, equals(152));
    expect(
      context.components.get<ResourceComponent>(player)!.resources['momentum'],
      equals(5),
    );
  });

  test('Shaolin defensive synergy: mitigation heal-back while stance '
      'active, and offense boosted while it is active', () {
    final context = _newContext();
    final martialArts = MartialArtsPlugin();
    martialArts.initialize(context);
    final entity = context.entities.create();
    context.components.add(entity, const HealthComponent(current: 50, max: 100));
    context.components.add(entity, ResourceComponent({'qi': 10}));
    learnStyle(entity, MartialStyles.shaolin, context);
    final target = context.entities.create();

    // No stance yet: palmStrike does its unmodified 8.
    final unboosted = palmStrike(actor: entity, targets: [target])
        .effectsFor(target, context);
    expect((unboosted.single as Damage).amount, equals(8));

    // Activate Iron Body Stance directly (bypassing turn machinery — this
    // test targets the mechanic in isolation).
    ironBodyStance(actor: entity, targets: [entity])
        .effectsFor(entity, context)
        .single
        .apply(RuleContext(
          subject: entity,
          triggerEvent: const Object(),
          entities: context.entities,
          components: context.components,
          events: context.events,
          rng: context.rng,
          eventCounts: context.rules.eventCounts,
        ));

    // Now boosted by the +4 synergy modifier: 8 + 4 = 12.
    final boosted = palmStrike(actor: entity, targets: [target])
        .effectsFor(target, context);
    expect((boosted.single as Damage).amount, equals(12));

    // And the mitigation rule reacts to EntityDamaged with a heal-back:
    // publishing it directly (as `Damage.apply` itself would, after
    // already reducing health) starts health at 50 and Heal(2) applies,
    // landing at 52 — this asserts the rule's reaction in isolation, not
    // the full Damage-then-EntityDamaged sequence (covered elsewhere).
    context.events.publish(EntityDamaged(entity, 10));
    expect(context.components.get<HealthComponent>(entity)!.current, equals(52));
  });

  test('Tai Chi counter redirects damage from a plain, martial-arts-'
      'unaware attacker', () {
    final context = _newContext();
    final martialArts = MartialArtsPlugin();
    martialArts.initialize(context);
    final defender = context.entities.create();
    context.components.add(defender, ResourceComponent({'qi': 10}));
    learnStyle(defender, MartialStyles.taiChi, context);
    yieldingStance(actor: defender, targets: [defender])
        .effectsFor(defender, context)
        .single
        .apply(RuleContext(
          subject: defender,
          triggerEvent: const Object(),
          entities: context.entities,
          components: context.components,
          events: context.events,
          rng: context.rng,
          eventCounts: context.rules.eventCounts,
        ));

    final attacker = context.entities.create();
    context.components.add(attacker, const HealthComponent(current: 100, max: 100));
    final battle = context.entities.create();
    final plainAttack = AttackAction(
      actor: attacker, targets: [defender], baseDamage: 5, damageStat: 'attack',
    );

    context.events.publish(ActionCompleted(battle, attacker, [defender], plainAttack));

    expect(context.components.get<HealthComponent>(attacker)!.current, equals(97));
  });

  test('MartialArts is removable: after unregister, Combat keeps working '
      'and MartialArts rules no longer fire', () {
    final context = _newContext();
    final manager = PluginManager();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    manager.register(combat);
    manager.register(martialArts);
    manager.initialize(context);
    manager.start(context);

    final shaolin = context.entities.create();
    context.components.add(shaolin, const HealthComponent(current: 50, max: 100));
    context.components.add(shaolin, TagSet({'stance:iron_body'}));
    // Publishing EntityDamaged directly (as Damage.apply itself would,
    // after already reducing health) starts health at 50; the mitigation
    // rule's Heal(2) is the only thing that changes it here, landing at 52.
    context.events.publish(EntityDamaged(shaolin, 10));
    expect(context.components.get<HealthComponent>(shaolin)!.current, equals(52));

    manager.stop(context);
    manager.unregister(context);

    // MartialArts' rule no longer fires post-unregister — health is
    // unchanged by this publish (it was 52, stays 52).
    context.events.publish(EntityDamaged(shaolin, 10));
    expect(context.components.get<HealthComponent>(shaolin)!.current, equals(52));

    // Combat itself runs a completely normal battle, unaffected.
    final a = context.entities.create();
    final b = context.entities.create();
    context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
    context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
    context.components.add(a, const HealthComponent(current: 30, max: 30));
    context.components.add(b, const HealthComponent(current: 12, max: 30));
    final battle = combat.system.startBattle([a, b]);
    combat.system.executeAction(
      battle,
      AttackAction(actor: a, targets: [b], baseDamage: 12, damageStat: 'attack'),
    );
    expect(context.components.get<HealthComponent>(b)!.current, equals(0));
    expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify they pass, and analyze**

Run:
```bash
dart test test/integration/martial_arts_end_to_end_test.dart
dart analyze
```
Expected: all 4 tests PASS. If any fails, that's a bug in an earlier task; stop and fix the earlier task's implementation, don't patch around it here.

- [ ] **Step 3: Run the whole suite**

Run:
```bash
dart test
dart analyze
```
Expected: every test across the whole package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add test/integration/martial_arts_end_to_end_test.dart
git commit -m "test: add MartialArts plugin end-to-end integration coverage"
```

---

### Task 9: Documentation

**Files:**
- Modify: `ARCHITECTURE.md`

**Interfaces:**
- Consumes: the finished implementation from Tasks 1–8 (this task only documents it).
- Produces: nothing new in `lib/` — this is the plan's final task.

- [ ] **Step 1: Amend `ARCHITECTURE.md`**

Read the current `ARCHITECTURE.md` first to confirm its exact present content. Add a new top-level section immediately after the existing `## Combat — the first plugin (...)` section, leaving every other line untouched:

```markdown
## MartialArts — the first content plugin (`lib/src/plugins/martial_arts/`, `lib/martial_arts_plugin.dart`)

MartialArts is the first plugin to depend on another plugin
(`dependencies => ['combat']`, per `claude.md`'s `MartialArts -> Combat ->
Core`) rather than sitting directly on Core, and the first proof that a
content plugin can add cross-entity combat behavior without Combat
exposing anything new. Two mechanics needed a genuine design decision:
Shaolin's damage mitigation and Tai Chi's counter both sound like they
need to intercept an incoming attack, but `AttackAction`/`Damage` only
resolve the *attacker's* modifiers and `EntityDamaged` carries no attacker
reference — closing either gap would mean editing Combat. Instead both
react to Combat's already-public events: Shaolin's mitigation is a `Rule`
on `EntityDamaged` (a heal-back, not a block), and Tai Chi's counter is a
`Rule` on `ActionCompleted` (which always carries `actor` *and* `targets`,
letting a custom `Condition` — `TaiChiCounterCondition` — redirect damage
onto whoever the attacker was, even a plain core `AttackAction` from a
martial-arts-unaware entity). Boxing's momentum generation needed neither:
it's a flat `costEffects: [ModifyResource('momentum', +N)]` on the
attacking technique itself.

Styles (`boxing`/`shaolin`/`taiChi`) are marker tags, not components,
granted by `learnStyle` — which also, for Shaolin specifically, registers
a permanent conditional `Modifier` (`condition: HasTagQuery('stance:iron_body')`)
that lets a defensive stance boost offense purely through the Modifier
Engine. One `MartialTechniqueAction extends CombatAction` class (mirroring
`AttackAction`) covers all 6 techniques and 3 stances via data; one
`MartialItemDefinition` class covers all 5 items and 3 trinkets — trinkets
are simply the items whose behavior comes from a `Rule` reacting to their
`equipped:<id>` tag rather than a static `Modifier`.

`MartialArtsPlugin` never holds a reference to `CombatPlugin`/
`CombatSystem` — only to Combat's event *vocabulary*, reached through the
shared `RuleEngine` every plugin gets via `PluginContext`. It captures
every `EventSubscription` its 4 rules return at `initialize` and cancels
them all at `unregister`, mirroring `CombatPlugin`'s own teardown — proven
by an integration test that unregisters `MartialArtsPlugin` mid-session
and confirms Combat keeps running normally and MartialArts' rules stop
firing.
```

- [ ] **Step 2: Final full verification**

Run:
```bash
dart pub get
dart test
dart analyze
```
Expected: `dart pub get` succeeds; every test in the package PASSes; `dart analyze` reports `No issues found!`.

- [ ] **Step 3: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: describe the MartialArts plugin in ARCHITECTURE.md"
```

---

## Self-Review Notes

- **Spec coverage:** every content requirement maps to a task — styles/resources/tags (Tasks 1, 5), 6 techniques + 3 stances (Task 5), 5 items + 3 trinkets (Task 4), the 3 named interactions (Boxing: Task 5's `costEffects`; Shaolin: Task 1's synergy modifier + Task 6's mitigation rule; Tai Chi: Task 3's condition + Task 6's rule), the required test scenario and removability proof (Task 8), and documentation (Task 9). All 11 tags are asserted present across the 9 techniques/stances in Task 5's own test.
- **Type consistency checked:** `MartialTechniqueAction`'s field names (`actor`, `targets`, `tags`, `conditions`, `costEffects`, `baseDamage`, `damageStat`, `selfEffects`) are defined once in Task 5 and used identically by all 9 factory functions in that same task and consumed identically in Task 8. `MartialItemDefinition`'s `modifiersFor` signature (`List<Modifier> Function(EntityId wearer)`) is used identically by every item in Task 4. `buildMartialArtsRules()`'s return type and the 4 rules it contains (Task 6) are consumed without modification by `MartialArtsPlugin.initialize` (Task 7).
- **Dependency direction verified:** every task's Files list stays inside `lib/src/plugins/martial_arts/` (or the new barrel) — no task touches `lib/src/plugins/combat/` or any other core file. Every import is `package:build_engine/build_engine.dart` and/or `package:build_engine/combat_plugin.dart`.
- **Removability is tested, not assumed:** Task 7's third test and Task 8's fourth test both exercise `unregister` and confirm MartialArts' rules stop firing while Combat continues normally — directly satisfying "must be removable without breaking Core."
- **Barrel-file ordering:** seven new files under `lib/src/plugins/martial_arts/`, added incrementally across Tasks 1–7 — each task's Step 3 shows the barrel's exact resulting content.
