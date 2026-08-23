# Cross-Plugin Interoperability Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, with tests, that `MartialArtsPlugin` and
`ExampleElementalPlugin` coexist and interact through Core/Combat's
generic primitives without importing each other, by adapting
`ExampleElementalPlugin` into a Magic-shaped plugin and adding the
integration/dependency tests scenarios A–H require.

**Architecture:** `ExampleElementalPlugin` gains 4 tags
(`magic`/`fire`/`elemental`/`spell`) and one new item
(`ElementalItemDefinition emberCharm`, mirroring `MartialItemDefinition`
exactly). The synergy: `emberCharm`'s `Modifier` targets stat `'punch'`
— the exact `damageStat` MartialArts' `jab`/`powerCross` already resolve
through `ModifierResolver`. Since `damageStat` is documented as an
arbitrary, caller-chosen string, an entity that both `learnStyle`s
Boxing and `equipElementalItem(emberCharm, ...)` deals bonus punch
damage through the Modifier Engine alone — zero new Rule/Condition
class, zero cross-plugin import. Scenarios A–C are already covered by
existing tests and are referenced, not duplicated. G/H become an
automated, CI-enforceable test reading source files' import text rather
than a one-time manual audit.

**Tech Stack:** Dart `^3.7.0`, `package:test`, package `build_engine`.

**Spec:** `docs/superpowers/specs/2026-08-23-cross-plugin-interop-design.md`

## Global Constraints

- No changes to `PluginSdk`, `ContentRegistry`, `CombatPlugin`,
  `CombatSystem`, or any existing MartialArts file's *behavior* — every
  existing test must keep passing unmodified.
- `MartialArtsPlugin`'s source must never reference
  `example_elemental`/`ExampleElemental`; `ExampleElementalPlugin`'s
  source must never reference `martial_arts`/`MartialArts`. Neither
  Core service file may reference `plugins/`.
- `ElementalItemDefinition` gets no item-entity-creation or
  loadout-component tracking — that would be a speculative abstraction
  nothing here needs.
- Do not create any class/plugin named `FireBoxing`, `MagicBoxing`,
  `MartialMagicSynergy`, or `HybridAttack`.
- `ContentRegistry`'s lack of an unload/unregister-factory operation is
  an existing, already-documented limitation — reference it in the
  final report; do not attempt to fix it in this pass.
- Run `dart analyze` and the full `dart test` suite after every task;
  both must stay clean/green.

---

### Task 1: Adapt `ExampleElementalPlugin` — tags and `emberCharm`

**Files:**
- Create: `lib/src/plugins/example_elemental/elemental_item.dart`
- Modify: `lib/src/plugins/example_elemental/elemental_content.dart`
- Modify: `lib/src/plugins/example_elemental/example_elemental_plugin.dart`
- Modify: `lib/example_elemental_plugin.dart`
- Test: `test/plugins/example_elemental/elemental_item_test.dart`

**Interfaces:**
- Consumes: `Modifier`, `ModifierSource`, `ModifierOperation`, `EntityId`,
  `PluginContext`, `AddTag`, `PluginContext.ruleContextFor`
  (`package:build_engine/build_engine.dart`) — all pre-existing,
  unchanged.
- Produces: `class ElementalItemDefinition { final String id; final
  Set<String> tags; final List<Modifier> Function(EntityId) modifiersFor;
  }`, `const emberCharm`, `void equipElementalItem(ElementalItemDefinition
  item, EntityId wearer, PluginContext context)`.

- [ ] **Step 1: Write `elemental_item.dart`**

```dart
import 'package:build_engine/build_engine.dart';

/// A wearable item or trinket for ExampleElemental — mirrors
/// `MartialItemDefinition`/`equipItem`'s exact shape (the second
/// occurrence of an already-proven pattern, not a new one). Deliberately
/// has no item-entity-creation or loadout-tracking — nothing here needs
/// inventory bookkeeping.
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

List<Modifier> _emberCharmModifiers(EntityId wearer) => [
      Modifier(
        source: ModifierSource('item:ember_charm:${wearer.value}'),
        target: wearer,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 4,
      ),
    ];

/// A fire trinket whose `Modifier` targets the `'punch'` stat — the
/// same, arbitrary, caller-chosen stat name MartialArts' `jab`/
/// `powerCross` already resolve through the Modifier Engine. This is
/// what lets the cross-plugin synergy (see
/// `test/integration/cross_plugin_synergy_test.dart`) work with zero
/// new Rule/Condition code and zero cross-plugin imports: any plugin's
/// Modifier applies to any action reading the same stat name.
const emberCharm = ElementalItemDefinition(
  id: 'ember_charm',
  tags: {'magic', 'fire', 'elemental', 'trinket'},
  modifiersFor: _emberCharmModifiers,
);

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

- [ ] **Step 2: Add tags to `fireball` in `elemental_content.dart`**

In `lib/src/plugins/example_elemental/elemental_content.dart`, find the
`fireball` definition's `'tags'` entry:

```dart
    'tags': ['element:fire', 'attack'],
```

Replace it with:

```dart
    'tags': ['element:fire', 'attack', 'magic', 'fire', 'elemental', 'spell'],
```

Leave `tidal_wave`'s and `spark_bolt`'s `'tags'` entries unchanged.

- [ ] **Step 3: Register the 4 new tags in `example_elemental_plugin.dart`**

In `lib/src/plugins/example_elemental/example_elemental_plugin.dart`,
find:

```dart
    sdk.registerTag('element:fire',
        description: 'Fire-aligned entity or content.');
    sdk.registerTag('element:water',
        description: 'Water-aligned entity or content.');
    sdk.registerTag('element:lightning',
        description: 'Lightning-aligned entity or content.');
```

Add these 4 lines immediately after it (still inside `initialize`,
before the `for (final rule in buildElementalRules())` loop):

```dart
    sdk.registerTag('magic', description: 'Magic-sourced entity or content.');
    sdk.registerTag('fire',
        description: 'Fire-flavored entity or content (see also element:fire).');
    sdk.registerTag('elemental',
        description: 'Elemental-sourced entity or content.');
    sdk.registerTag('spell', description: 'A castable magic spell.');
```

- [ ] **Step 4: Add the barrel export**

In `lib/example_elemental_plugin.dart`, add (alphabetically positioned,
between `elemental_effects.dart` and `elemental_rules.dart`):

```dart
export 'src/plugins/example_elemental/elemental_item.dart';
```

- [ ] **Step 5: Write `elemental_item_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
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
  group('emberCharm', () {
    test('has the expected id and tags', () {
      expect(emberCharm.id, equals('ember_charm'));
      expect(emberCharm.tags,
          equals({'magic', 'fire', 'elemental', 'trinket'}));
    });

    test('modifiersFor returns a single +4 add punch modifier', () {
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
    test("registers the item's modifiers against the wearer", () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipElementalItem(emberCharm, wearer, context);

      final active = context.modifiers
          .activeModifiersFor(wearer, 'punch', context.components);
      expect(active, hasLength(1));
    });

    test('tags the wearer equipped:<id>', () {
      final context = _newContext();
      final wearer = context.entities.create();

      equipElementalItem(emberCharm, wearer, context);

      expect(context.components.get<TagSet>(wearer)!.tags,
          contains('equipped:ember_charm'));
    });
  });
}
```

- [ ] **Step 6: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test` (expect: every
test passes, including every pre-existing ExampleElemental test — `dart
test test/plugins/example_elemental/` and `dart test
test/integration/example_elemental_end_to_end_test.dart` specifically,
to confirm the tag/content additions didn't disturb existing assertions).

```bash
git add lib/src/plugins/example_elemental/elemental_item.dart \
  lib/src/plugins/example_elemental/elemental_content.dart \
  lib/src/plugins/example_elemental/example_elemental_plugin.dart \
  lib/example_elemental_plugin.dart \
  test/plugins/example_elemental/elemental_item_test.dart
git commit -m "feat: adapt ExampleElementalPlugin toward Magic-shaped content (magic/fire/elemental/spell tags, emberCharm item)"
```

---

### Task 2: Cross-plugin synergy integration tests (D, E, F)

**Files:**
- Create: `test/integration/cross_plugin_synergy_test.dart`

**Interfaces:**
- Consumes: `CombatPlugin`, `CombatSystem` (via `combat.system`),
  `CombatantComponent` (`package:build_engine/combat_plugin.dart`);
  `MartialArtsPlugin`, `learnStyle`, `MartialStyles`, `jab`
  (`package:build_engine/martial_arts_plugin.dart`);
  `ExampleElementalPlugin`, `attuneToElement`, `Elements`, `emberCharm`,
  `equipElementalItem`
  (`package:build_engine/example_elemental_plugin.dart`); Core services
  (`package:build_engine/build_engine.dart`) — all pre-existing.

- [ ] **Step 1: Write `cross_plugin_synergy_test.dart`**

```dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/example_elemental_plugin.dart';
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
    content: ContentRegistry(),
  );
}

void main() {
  test('D: ExampleElemental + Combat works, MartialArts absent', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(CombatPlugin());
    manager.register(ExampleElementalPlugin());
    manager.initialize(context);
    manager.start(context);

    final caster = context.entities.create();
    attuneToElement(caster, Elements.fire, 1, context);
    context.components.add(caster, ResourceComponent({'mana': 10}));
    final target = context.entities.create();
    context.components
        .add(target, const HealthComponent(current: 100, max: 100));

    final fireball = context.content.get('fireball');
    expect(
      fireball.conditions
          .every((c) => c.evaluate(context.ruleContextFor(caster))),
      isTrue,
    );
    for (final cost in fireball.costEffects) {
      cost.apply(context.ruleContextFor(caster));
    }
    for (final effect in fireball.effects) {
      effect.apply(context.ruleContextFor(target));
    }
    expect(context.components.get<HealthComponent>(target)!.current,
        equals(88));

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test(
      'E: MartialArts + ExampleElemental + Combat works, and a martial '
      'attack gains a generic fire-modifier synergy bonus', () {
    final context = _newContext();
    final manager = PluginManager();
    final combat = CombatPlugin();
    manager.register(combat);
    manager.register(MartialArtsPlugin());
    manager.register(ExampleElementalPlugin());
    manager.initialize(context);
    manager.start(context);

    final baseline = context.entities.create();
    final baselineTarget = context.entities.create();
    context.components
        .add(baseline, const CombatantComponent(team: 'a', initiative: 10));
    context.components.add(
        baselineTarget, const CombatantComponent(team: 'b', initiative: 1));
    context.components
        .add(baseline, const HealthComponent(current: 100, max: 100));
    context.components
        .add(baselineTarget, const HealthComponent(current: 100, max: 100));
    learnStyle(baseline, MartialStyles.boxing, context);
    final battleBaseline = combat.system.startBattle([baseline, baselineTarget]);
    combat.system.executeAction(
        battleBaseline, jab(actor: baseline, targets: [baselineTarget]));
    expect(context.components.get<HealthComponent>(baselineTarget)!.current,
        equals(94));

    final enchanted = context.entities.create();
    final enchantedTarget = context.entities.create();
    context.components
        .add(enchanted, const CombatantComponent(team: 'a', initiative: 10));
    context.components.add(
        enchantedTarget, const CombatantComponent(team: 'b', initiative: 1));
    context.components
        .add(enchanted, const HealthComponent(current: 100, max: 100));
    context.components
        .add(enchantedTarget, const HealthComponent(current: 100, max: 100));
    learnStyle(enchanted, MartialStyles.boxing, context);
    equipElementalItem(emberCharm, enchanted, context);
    final battleEnchanted =
        combat.system.startBattle([enchanted, enchantedTarget]);
    combat.system.executeAction(
        battleEnchanted, jab(actor: enchanted, targets: [enchantedTarget]));

    // The generic synergy: same jab, same baseDamage (6), but the
    // enchanted attacker's ember_charm Modifier (+4 add punch) is
    // resolved by MartialTechniqueAction.effectsFor through the same
    // Modifier Engine mechanism Shaolin's own iron-body synergy uses —
    // 6 + 4 = 10, dealt entirely through generic engine primitives, with
    // neither plugin's source referencing the other.
    expect(context.components.get<HealthComponent>(enchantedTarget)!.current,
        equals(90));

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test('F: removing ExampleElemental does not break MartialArts', () {
    final context = _newContext();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    final exampleElemental = ExampleElementalPlugin();
    combat.initialize(context);
    martialArts.initialize(context);
    exampleElemental.initialize(context);

    exampleElemental.unregister(context);

    final player = context.entities.create();
    final enemy = context.entities.create();
    context.components.add(
        player, const CombatantComponent(team: 'player', initiative: 10));
    context.components
        .add(enemy, const CombatantComponent(team: 'enemy', initiative: 5));
    context.components
        .add(player, const HealthComponent(current: 100, max: 100));
    context.components
        .add(enemy, const HealthComponent(current: 100, max: 100));
    learnStyle(player, MartialStyles.boxing, context);
    final battle = combat.system.startBattle([player, enemy]);
    combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));

    expect(context.components.get<HealthComponent>(enemy)!.current,
        equals(94));
  });

  test('F (mirror): removing MartialArts does not break ExampleElemental',
      () {
    final context = _newContext();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    final exampleElemental = ExampleElementalPlugin();
    combat.initialize(context);
    martialArts.initialize(context);
    exampleElemental.initialize(context);

    martialArts.unregister(context);

    final caster = context.entities.create();
    attuneToElement(caster, Elements.fire, 1, context);
    context.components.add(caster, ResourceComponent({'mana': 10}));
    final target = context.entities.create();
    context.components
        .add(target, const HealthComponent(current: 100, max: 100));

    final fireball = context.content.get('fireball');
    for (final cost in fireball.costEffects) {
      cost.apply(context.ruleContextFor(caster));
    }
    for (final effect in fireball.effects) {
      effect.apply(context.ruleContextFor(target));
    }
    expect(context.components.get<HealthComponent>(target)!.current,
        equals(88));

    // ExampleElemental's own "water conducts" rule must also still fire
    // — proves its rules survive MartialArts' removal, not just its
    // content lookups.
    final soaked = context.entities.create();
    context.components
        .add(soaked, const HealthComponent(current: 50, max: 50));
    context.components.add(soaked, StatusComponent({'status:soaked'}));
    context.events.publish(EntityDamaged(soaked, 5));
    expect(context.components.get<StatusComponent>(soaked)!.activeStatuses,
        contains('status:shocked'));
  });
}
```

- [ ] **Step 2: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test
test/integration/cross_plugin_synergy_test.dart` (expect: all 4 tests
pass), then the full suite `dart test` (expect: every test in the
package passes).

```bash
git add test/integration/cross_plugin_synergy_test.dart
git commit -m "test: prove cross-plugin coexistence and a generic Modifier-based synergy (scenarios D, E, F)"
```

---

### Task 3: Automated dependency-governance test (G, H)

**Files:**
- Create: `test/integration/architecture_dependency_test.dart`

- [ ] **Step 1: Write `architecture_dependency_test.dart`**

```dart
import 'dart:io';

import 'package:test/test.dart';

/// Asserts no `.dart` file under [directoryPath] contains [forbidden]
/// anywhere in its text. Run from the package root (as `dart test`
/// always is in this repo), so these paths are relative to it.
void _assertNoSubstringInDirectory(String forbidden, String directoryPath) {
  final dir = Directory(directoryPath);
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final content = file.readAsStringSync();
    expect(
      content,
      isNot(contains(forbidden)),
      reason: '${file.path} must not reference "$forbidden"',
    );
  }
}

void main() {
  group('G: neither content plugin imports the other', () {
    test('MartialArts does not reference ExampleElemental', () {
      _assertNoSubstringInDirectory(
          'example_elemental', 'lib/src/plugins/martial_arts');
    });

    test('ExampleElemental does not reference MartialArts', () {
      _assertNoSubstringInDirectory(
          'martial_arts', 'lib/src/plugins/example_elemental');
    });
  });

  group('H: Core does not import either content plugin', () {
    const coreDirectories = [
      'lib/src/component',
      'lib/src/components',
      'lib/src/content',
      'lib/src/entity',
      'lib/src/event',
      'lib/src/modifier',
      'lib/src/plugin',
      'lib/src/query',
      'lib/src/rng',
      'lib/src/rule',
      'lib/src/spatial',
    ];

    for (final directory in coreDirectories) {
      test('$directory does not reference plugins/', () {
        _assertNoSubstringInDirectory('plugins/', directory);
      });
    }
  });
}
```

- [ ] **Step 2: Run and commit**

Run: `dart analyze` (expect: no issues) then `dart test
test/integration/architecture_dependency_test.dart` (expect: all tests
pass — this should pass immediately given the current source tree; if
it fails, that is itself the finding to report, not something to
suppress).

```bash
git add test/integration/architecture_dependency_test.dart
git commit -m "test: add automated dependency-governance test for scenarios G and H"
```

---

### Task 4: Documentation

**Files:**
- Modify: `ARCHITECTURE.md`

- [ ] **Step 1: Append a short addendum**

Append, at the end of the file:

```markdown
## Cross-plugin interoperability proof (`test/integration/cross_plugin_synergy_test.dart`, `test/integration/architecture_dependency_test.dart`)

`MartialArtsPlugin` and `ExampleElementalPlugin` are two independent
content plugins — neither imports or depends on the other, and neither
is a dependency of the other in `claude.md`'s sense (only MartialArts's
existing `-> combat` edge is real). Their one demonstrated synergy uses
the Modifier Engine alone: `ExampleElementalPlugin`'s `emberCharm`
registers a `Modifier` against stat `'punch'` — the exact,
arbitrary-caller-chosen `damageStat` MartialArts' `jab`/`powerCross`
already resolve through `ModifierResolver`. An entity that both
`learnStyle`s Boxing and `equipElementalItem(emberCharm, ...)` deals
bonus punch damage with zero new `Rule`/`Condition` code and zero
cross-plugin import — the same mechanism Shaolin's own iron-body synergy
already proved, just registered by a different plugin this time.

`architecture_dependency_test.dart` makes the "neither imports the
other, Core imports neither" property an automated, CI-enforceable
check (reading source files' text at test time) rather than a one-time
manual audit that rots the next time a file moves.
```

- [ ] **Step 2: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: document the cross-plugin interoperability proof"
```
