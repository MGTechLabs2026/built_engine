# Item Content Migration — Design Spec

**Date:** 2026-08-24
**Origin:** `ARCHITECTURE_AUDIT.md` (2026-08-24), Finding #7 — MartialArts'
8 items/trinkets (`lib/src/plugins/martial_arts/martial_item.dart`) and
Elemental's 1 item (`lib/src/plugins/elemental/elemental_item.dart`) are
hand-written Dart `const` object literals rather than `ContentRegistry`-
loaded data, unlike every other content shape in the engine (Elemental's
spells, MartialArts' techniques, Physique's physiques — all already
migrated in prior passes).
**Goal:** Migrate exactly these 9 item/trinket definitions to
`ContentRegistry`-loaded data, following the exact data/runtime-split
pattern already proven twice (`martialTechniqueFromDefinition`,
`physiqueDefinitionFromContent`), with zero change to `equipItem`/
`equipElementalItem`'s public signatures or behavior.

## Non-goals

- `MartialTechniqueAction`, `MartialStyles`, `Elements`, `PhysiqueTypes`,
  or any other structural/vocabulary class — untouched. Only item/trinket
  *content* migrates.
- No new physique/element/style. No Cultivation, no Magic.
- No change to `PluginSdk`, `ContentRegistry`, or `Modifier`/
  `ModifierResolver` themselves.
- No change to any Combat file.

## Why this is more than a mechanical find-and-replace

`ContentRegistry.get(id)` requires a `PluginContext` to resolve. Today,
`brassKnuckles`/`emberCharm`/etc. are bare top-level `const` identifiers
usable with zero arguments at any call site
(`equipItem(brassKnuckles, wearer, context)`). Once their data lives in
`ContentRegistry`, there is no compile-time object left to reference —
every call site needs a `PluginContext` in scope to resolve the item
first. This affects `martial_arts_rules.dart` (reads `momentumTrinket.id`/
`qiPendant.id`) and 4 test files (`martial_item_test.dart`,
`martial_arts_plugin_test.dart`, `martial_arts_end_to_end_test.dart`,
`elemental_item_test.dart`, `cross_plugin_synergy_test.dart` — 5 files,
not 4; corrected count below) that construct/read these items directly by
their old Dart symbol. Approved by the user with this cost understood.

## Design

### 1. Stable id constants (replaces the old `.id` read pattern)

New `abstract final class MartialItemIds` in
`lib/src/plugins/martial_arts/martial_vocabulary.dart` (alongside the
existing `MartialResources`/`MartialStances`), one `static const String`
per item/trinket:

```dart
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

New `abstract final class ElementalItemIds` in
`lib/src/plugins/elemental/elemental_vocabulary.dart` (alongside
`ElementalResources`/`ElementalStatuses`):

```dart
abstract final class ElementalItemIds {
  static const emberCharm = 'ember_charm';
}
```

`martial_arts_rules.dart:23,28` changes `momentumTrinket.id` /
`qiPendant.id` to `MartialItemIds.momentumTrinket` /
`MartialItemIds.qiPendant` — same single-source-of-truth property the
current doc comment there cares about (a rename of the constant still
propagates everywhere), just sourced from a plain string constant instead
of a runtime object's field.

### 2. Content definitions + parser (per plugin, no shared code between them)

New `lib/src/plugins/martial_arts/martial_item_content.dart`:

- `const martialItemContentDefinitions` — 8 JSON-shaped maps, one per
  current `const` definition, `'type': 'martial_item'` for the 5 items
  (`martialItems` today), `'type': 'martial_trinket'` for the 3 trinkets
  (`martialTrinkets` today). Each has `'id'` (from `MartialItemIds`),
  `'tags'`, and `'modifiers'` — a list of `{stat, operation, value,
  condition}` maps mirroring `physique_content.dart`'s shape, generalized
  two ways Physique's didn't need:
  - `'condition'` is **optional** — omit the key entirely for an
    unconditional modifier (5 of the 8 items have no condition at all;
    only `counterstrikeRing` does, gated on `MartialStances.taiChi`).
  - `'modifiers'` may be an **empty list** (`momentumTrinket`,
    `qiPendant` have none — their behavior comes entirely from the
    `equipped:<id>` tag `equipItem` already grants, read by
    `martial_arts_rules.dart`'s passive-regen rules).
- `MartialItemDefinition martialItemDefinitionFromContent(ContentDefinition
  definition)` — parses `extra['modifiers']` (defaulting to `[]` if
  absent) into `Modifier`s, `condition:` built via `HasTagQuery(...)`
  only when the raw entry has a `'condition'` key, else left `null`.
  Reuses `MartialItemDefinition` (`martial_item.dart`) as its output
  type — that class itself does not change.
- `MartialItemDefinition martialItem(String id, PluginContext context) =>
  martialItemDefinitionFromContent(context.content.get(id));` — the
  ergonomic resolver every call site uses instead of a bare identifier:
  `equipItem(martialItem(MartialItemIds.brassKnuckles, context), wearer,
  context)`. This does not reintroduce hardcoded content — it is a thin,
  stateless lookup + parse, called fresh every time (no caching, no
  global state), exactly mirroring how `physiqueDefinitionFromContent`
  is called fresh at `initializePhysique` time rather than cached.

New `lib/src/plugins/elemental/elemental_item_content.dart` — the same
shape, one entry (`'type': 'elemental_item'`), plus
`elementalItemDefinitionFromContent` and an `elementalItem(id, context)`
resolver.

### 3. `martial_item.dart` / `elemental_item.dart` after migration

Both files keep their `MartialItemDefinition`/`ElementalItemDefinition`
class (unchanged) and `equipItem`/`equipElementalItem` function
(unchanged, since both operate on an already-resolved definition object,
not on the old const symbols directly). Both lose their hardcoded `const`
instances, their per-item `_xModifiers` functions, and the
`martialItems`/`martialTrinkets` list constants (superseded by
`context.content.allOfType('martial_item')`/`allOfType('martial_trinket')`
for any caller that needs "all items", e.g. tests).

### 4. Plugin registration

`MartialArtsPlugin.initialize` (`martial_arts_plugin.dart`) gains a
second guarded `registerContentBatch` call, mirroring the existing
technique-content guard exactly:

```dart
if (context.content.find(MartialItemIds.brassKnuckles) == null) {
  sdk.registerContentBatch(martialItemContentDefinitions);
}
```

`ElementalPlugin.initialize` (`elemental_plugin.dart`) gains the
equivalent for `elementalItemContentDefinitions`, guarded on
`ElementalItemIds.emberCharm`.

### 5. Barrels

`lib/martial_arts_plugin.dart` adds `export
'src/plugins/martial_arts/martial_item_content.dart';` (alphabetical
position). `lib/elemental_plugin.dart` adds `export
'src/plugins/elemental/elemental_item_content.dart';`.

### 6. Test call-site updates (exact files, verified against current content)

- `test/plugins/martial_arts/martial_item_test.dart` — every bare
  `brassKnuckles`/`weightedVest`/`momentumTrinket`/`counterstrikeRing`
  reference becomes `martialItem(MartialItemIds.x, context)`; every test
  gains `MartialArtsPlugin().initialize(context)` at the top (this file's
  `_newContext()` currently doesn't initialize the plugin, since it never
  needed loaded content before); the `martialItems has 5 entries...`
  test becomes an `allOfType` count/uniqueness check.
- `test/plugins/martial_arts/martial_arts_plugin_test.dart` — already
  calls `plugin.initialize(context)` before using `brassKnuckles`; only
  the two `equipItem(brassKnuckles, ...)` call sites change to
  `equipItem(martialItem(MartialItemIds.brassKnuckles, context), ...)`.
- `test/integration/martial_arts_end_to_end_test.dart` — already calls
  `martialArts.initialize(context)` first; the two `equipItem(...)` call
  sites at the top change the same way.
- `test/plugins/elemental/elemental_item_test.dart` — needs
  `ElementalPlugin().initialize(context)` added to every test (currently
  never initializes the plugin); every `emberCharm` reference becomes
  `elementalItem(ElementalItemIds.emberCharm, context)` (the two
  id/tags/modifiersFor assertions in the `group('emberCharm', ...)` block
  resolve the item once via a context created for that purpose).
- `test/integration/cross_plugin_synergy_test.dart` — `ElementalPlugin`
  is already initialized before the one `equipElementalItem(emberCharm,
  ...)` call site in the relevant test; only that call site changes.

## Dependency/architecture properties preserved

- Neither new content-definition file imports the other plugin — same
  `Core`-only dependency shape as before.
- No new hardcoded content — the previously-hand-written Dart objects are
  now fully data-shaped and `ContentRegistry`-loaded, closing
  `ARCHITECTURE_AUDIT.md`'s Finding #7 for both plugins that had it.
- No global mutable state introduced — `martialItem`/`elementalItem` are
  pure, stateless resolver functions, not a cache.
- `MartialItemIds`/`ElementalItemIds` also close part of Additional
  Observation C's pattern (a per-plugin, locally-owned constants class
  for tag-shaped strings) for item ids specifically, though that
  observation itself was about `'western'`/`'eastern'` and is out of
  scope for this migration.

## Test plan

Every existing test's *intent* is preserved exactly (same assertions,
same expected values) — only how each test obtains a
`MartialItemDefinition`/`ElementalItemDefinition` changes. No new
behavior is being added, so no new test scenarios beyond what already
exists, other than replacing the `martialItems`/`martialTrinkets` list
assertions with `ContentRegistry.allOfType` equivalents.
