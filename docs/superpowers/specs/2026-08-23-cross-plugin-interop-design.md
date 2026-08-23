# Cross-Plugin Interoperability Proof — Design

## Purpose

Prove — with tests, not just documentation — that two independent
*content* plugins (`MartialArtsPlugin`, `ExampleElementalPlugin`) can
coexist and interact through Core/Combat's generic primitives (tags,
queries, rules, conditions, effects, modifiers, events) without either
importing or depending on the other, and without Combat becoming aware
of either. This is an architecture proof, not a feature: no rebuild of
`PluginSdk`/`ContentRegistry`/Combat/MartialArts/ExampleElemental, no
speculative abstractions, no new plugin, no `FireBoxing`/`MagicBoxing`/
`MartialMagicSynergy`/`HybridAttack` class.

## Adapting `ExampleElementalPlugin` into a Magic-shaped plugin

Purely additive — every existing file/test/behavior from the prior pass
stays intact.

### Tags

`ExampleElementalPlugin.initialize` registers 4 more tags via
`sdk.registerTag`, alongside the existing `element:fire`/`element:water`/
`element:lightning`: `magic`, `fire`, `elemental`, `spell`. `fireball`'s
tag set grows from `['element:fire', 'attack']` to `['element:fire',
'attack', 'magic', 'fire', 'elemental', 'spell']` — it's simultaneously
a fire-elemental spell and a magic attack, the same way MartialArts'
`blazingPalm` already carries both `'martial'` and `'fire'`.

### A fire modifier/trinket

New file `lib/src/plugins/example_elemental/elemental_item.dart`,
mirroring `MartialItemDefinition`/`equipItem`'s exact shape (not a new
pattern — the second occurrence of an already-proven one):

```dart
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

const emberCharm = ElementalItemDefinition(
  id: 'ember_charm',
  tags: {'magic', 'fire', 'elemental', 'trinket'},
  modifiersFor: _emberCharmModifiers,
);
```

`_emberCharmModifiers(wearer)` registers one `Modifier`: `target: wearer,
stat: 'punch', operation: add, value: 4` (unconditional — see "the
synergy mechanism" below for why `'punch'`). `equipElementalItem(item,
wearer, context)` registers the item's modifiers and tags the wearer
`equipped:<id>` via `context.ruleContextFor` — deliberately *not*
mirroring `equipItem`'s item-entity-creation/loadout-component
bookkeeping, since nothing here needs inventory tracking; that would be
the speculative abstraction this pass is told to avoid.

## The synergy mechanism

`damageStat` on `AttackAction`/`MartialTechniqueAction` is documented as
"an arbitrary, caller-chosen string — Combat never interprets its
value." MartialArts' own `jab`/`powerCross` already resolve their damage
through `ModifierResolver().resolve(baseDamage,
activeModifiersFor(actor, 'punch', components))` — exactly the same
mechanism Shaolin's `learnStyle` already uses to register a conditional
`+4 add palm` modifier for its own techniques. `emberCharm` targeting
stat `'punch'` means: **an entity that has learned Boxing and also
equips `emberCharm` deals bonus punch damage — through the Modifier
Engine alone.** No new `Rule`, no new `Condition` class, no cross-plugin
import. Composing this needs exactly two calls — `learnStyle` (from
`martial_arts_plugin.dart`) and `equipElementalItem` (from
`example_elemental_plugin.dart`) — made only by whoever combines the two
plugins (the integration test), never by either plugin's own source.

This is deliberately not the *only* generic mechanism demonstrated — the
existing `martialTechniqueContentDefinitions` conditions (`hasTag`,
`resourceAbove`) and `elementalRules` (a `Rule` on `EntityDamaged`) are
already-proven examples of the other four (queries, conditions, rules,
events); the Modifier-based synergy is the one genuinely new composition
this pass adds, chosen because it needs zero new glue code — the
strongest possible decoupling proof.

## Test plan

### D & E & F — `test/integration/cross_plugin_synergy_test.dart`

- **D — ExampleElemental + Combat works:** register `CombatPlugin` and
  `ExampleElementalPlugin` together (MartialArts absent); resolve
  `fireball` end to end (cost/conditions/effects) exactly like the
  existing `content_registry_end_to_end_test.dart`/
  `example_elemental_end_to_end_test.dart` do standalone, now alongside
  a live `CombatSystem` to prove no interference.
- **E — MartialArts + ExampleElemental + Combat works, synergy proven:**
  register all three plugins; one entity `learnStyle`s Boxing and
  `equipElementalItem(emberCharm, ...)`; execute `jab` through the real
  `CombatSystem.executeAction` twice — once for a baseline entity without
  `emberCharm`, once with it — asserting the equipped entity's `jab`
  deals exactly 4 more damage (6+4=10). This is the "generic fire
  synergy" proof: a martial attack, bonus-modified by fire-tagged
  content, through a mechanism neither plugin's source references the
  other to use.
- **F — removing either content plugin doesn't break the other:**
  `PluginManager`'s `stop`/`unregister` are whole-manager phase
  transitions (they tear down every registered plugin, not one) — so
  this test initializes all three plugins directly (`plugin.initialize
  (context)`, bypassing `PluginManager`, exactly like the existing
  per-plugin tests in `martial_arts_plugin_test.dart`/
  `combat_plugin_test.dart` already do), then calls
  `exampleElemental.unregister(context)` *alone*, and confirms
  MartialArts' techniques/rules still function normally; then the
  mirror case, calling `martialArts.unregister(context)` alone and
  confirming ExampleElemental's spells/rules still function.

A/B/C are **not duplicated** — `core_boots_without_plugins_test.dart`,
`combat_plugin_end_to_end_test.dart`, and
`martial_arts_end_to_end_test.dart` already are those three proofs. The
report (see below) references them by name rather than re-testing.

### G & H — `test/integration/architecture_dependency_test.dart`

An automated, CI-enforceable dependency-governance test (not a one-time
manual grep) — reads source files at test time and asserts on their
`import` lines:

```dart
void _assertNoImportOf(String pattern, String fromDirectory) {
  final dir = Directory(fromDirectory);
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final content = file.readAsStringSync();
    expect(content, isNot(contains(pattern)),
        reason: '${file.path} must not import $pattern');
  }
}
```

- **G:** every file under `lib/src/plugins/martial_arts/` asserted to
  not contain `example_elemental` anywhere in its text (covers both
  `package:build_engine/example_elemental_plugin.dart` and any relative
  escape); the mirror assertion for every file under
  `lib/src/plugins/example_elemental/` against `martial_arts`.
- **H:** every file under each Core service directory
  (`lib/src/{component,components,content,entity,event,modifier,plugin,
  query,rng,rule,spatial}/`) asserted to not contain the substring
  `plugins/` — Core has no reason to reference anything under
  `lib/src/plugins/` at all, content or infrastructure.

This test uses `dart:io` `File`/`Directory` — acceptable here since it's
test-only tooling verifying the shipped source tree, not production
code, and it's the only way to make G/H genuinely automated rather than
a report claim someone has to re-verify by hand next time a file moves.

## Report deliverable

A message (not a new committed file — this is a status report, not
documentation) covering: files changed, tests added, the dependency
graph (`Core <- Combat <- MartialArts`, `Core <- ExampleElemental`, both
verified by the new architecture-dependency test), an explicit yes/no on
genuine decoupling with the evidence, and remaining architectural
weaknesses — chiefly `ContentRegistry`'s already-documented lack of an
unload/unregister-factory operation (referenced, not re-solved) and
anything the tests themselves surface.

## Non-goals (explicit)

No `MagicPlugin`, no full Magic system, no rewrite of `ContentRegistry`
to support Modifier-shaped content, no item-entity/loadout tracking for
`ElementalItemDefinition`, no change to `PluginSdk`.
