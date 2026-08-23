# Build Engine — Architecture Audit

**Date:** 2026-08-24
**Scope:** entire repository (`lib/` — Core and all four plugins: Combat,
MartialArts, Elemental, Physique) against the architecture contract in
`CLAUDE.md`.
**Commit audited:** `7852ac7` (main, post-Physique-plugin-merge).
**Method:** full read of `CLAUDE.md`; a complete file inventory of `lib/`
(70 files); import-graph inspection of every directory under `lib/src/`
and every top-level barrel (`lib/*.dart`); targeted greps for domain
vocabulary in Core, `dart:math`/`Random` usage outside `RngService`,
mutable `static` state, hardcoded item-combination checks, and duplicated
`RuleContext`-construction helpers; line-by-line reading of every
component class and every barrel's exports; a fresh line-count survey of
every file to catch god-class growth since the prior audit
(2026-08-23, `ARCHITECTURE_AUDIT.md` at that time — its 5 findings +
2 observations were all fixed; see the previous log preserved below).
**This is a from-scratch audit**, not a diff against the prior one — every
category was re-verified against the current code, including the new
Physique plugin, which did not exist at the time of the last audit.
**No changes have been made.** Refactoring requires separate approval.

## Summary

Of the 15 categories requested, **13 have no violations**. **2 have real
findings**, both Low severity — no correctness or dependency-boundary
risk in either case.

| # | Category | Result |
|---|---|---|
| 1 | Core importing game-specific modules | ✅ No violations |
| 2 | Combat importing MartialArts | ✅ No violations |
| 3 | Combat importing Magic | ✅ N/A — no Magic plugin exists |
| 4 | Plugins accessing private implementation of other plugins | ✅ No violations |
| 5 | Circular dependencies | ✅ No violations |
| 6 | Hardcoded item combinations | ✅ No violations |
| 7 | Hardcoded content | ⚠️ 1 finding (Low) |
| 8 | Global mutable state | ✅ No violations |
| 9 | Gameplay randomness bypassing RNGService | ✅ No violations |
| 10 | Components containing excessive gameplay logic | ✅ No violations |
| 11 | God classes | ⚠️ 1 finding (Low, carried over, unchanged) |
| 12 | Duplicate engine functionality inside plugins | ✅ No violations |
| 13 | Direct cross-plugin calls that should use events/interfaces | ✅ No violations |
| 14 | Domain-specific concepts leaking into Core | ✅ No violations |
| 15 | Serialization depending on runtime implementation classes | ✅ No violations |

A third item — not one of the 15, found while auditing tag vocabulary
naming — is recorded under **Additional Observations**: the `'western'`/
`'eastern'` tradition-tag strings that are the entire interoperability
contract between MartialArts and Physique are repeated raw-literal, with
no local constant in either plugin backing them.

---

## 1. Core importing game-specific modules

**Result: No violations found.**

Every file under `lib/src/{component,components,content,entity,event,
modifier,plugin,query,rng,rule,spatial}/` was grep'd for imports; every
import resolves to another file inside `lib/src/` (never `lib/src/
plugins/`) or a `dart:` SDK import. `dart:math` appears in exactly two
places: `lib/src/rng/rng_service.dart:1` (the sanctioned location) and
`lib/src/modifier/modifier_resolver.dart:1` (`math.min`/`math.max` for
the MIN/MAX modifier operations — not randomness). Grepping Core for
`sword|spell|fireball|qi|boxing|shaolin|martial|cultivat|potion|dragon|
mana|physique|sturdy|endurance|elemental` returns only two hits, both
doc-comment prose: `content_definition.dart:6,43` (illustrating the JSON
schema with `CLAUDE.md`'s own `iron_sword`/generic examples) and
`plugin_sdk.dart:16` (a doc comment citing `MartialArtsPlugin` by name as
a design precedent, not a dependency).

## 2. Combat importing MartialArts

**Result: No violations found.**

`lib/src/plugins/combat/*.dart` imports only `package:build_engine/
build_engine.dart` (Core's public barrel) and its own sibling files.
Grep for `martial_arts|MartialArts|magic|physique` inside
`lib/src/plugins/combat/` returns three hits, all doc-comment prose
explicitly *disclaiming* such vocabulary (`combat_plugin.dart:10`,
`combat_action.dart:33`, `combat_system.dart:12` — "No martial-arts/
magic/cultivation/weapon vocabulary"). The dependency runs the sanctioned
direction only: `MartialArts -> Combat -> Core`
(`lib/martial_arts_plugin.dart`'s barrel doc comment and
`MartialArtsPlugin.dependencies => const ['combat']`).

## 3. Combat importing Magic

**Result: N/A — no Magic plugin exists in this repository.** No
violation to find; Combat's only inbound content-plugin dependent today
is MartialArts.

## 4. Plugins accessing private implementation of other plugins

**Result: No violations found.**

Every cross-plugin reference goes through a public barrel
(`package:build_engine/combat_plugin.dart`), never a `lib/src/plugins/
combat/...` path directly — confirmed by reading every `import` line in
`lib/src/plugins/{martial_arts,elemental,physique}/`:

- `lib/src/plugins/martial_arts/martial_conditions.dart:2` and
  `martial_arts_rules.dart:2` and `martial_technique_action.dart:2` each
  import `package:build_engine/combat_plugin.dart` — the only plugin
  that imports another plugin at all, and it does so exclusively through
  the barrel.
- `ElementalPlugin` and `PhysiquePlugin` import nothing from Combat or
  MartialArts, at any path.

No plugin holds a live reference to another plugin's internal class; all
five top-level barrels (`lib/{build_engine,combat_plugin,
martial_arts_plugin,elemental_plugin,physique_plugin}.dart`) export only
files from their own `lib/src/plugins/<name>/` (or, for `build_engine.dart`,
only `lib/src/{component,...}/`) directory.

## 5. Circular dependencies

**Result: No violations found.**

The import graph is a strict DAG: `Core <- Combat <- MartialArts`,
`Core <- Elemental`, `Core <- Physique`. No file under `lib/src/`
imports anything under `lib/src/plugins/`, so a cycle back into Core is
structurally impossible. `PluginManager.resolveLoadOrder()`
(`lib/src/plugin/plugin_manager.dart`) additionally detects and throws
`CyclicPluginDependencyException` on any *declared* plugin dependency
cycle at runtime — a second, independent guard,
`test/integration/architecture_dependency_test.dart` further
CI-enforces the absence of a MartialArts↔Physique import cycle and a
Combat→{MartialArts,Elemental,Physique} import in either direction.

## 6. Hardcoded item combinations

**Result: No violations found.**

Grepped the whole `lib/src/plugins/` tree for an `id ==` /
combination-shaped conditional (`id == 'x' && id2 == 'y'`); zero hits.
Every cross-entity interaction found (Shaolin's `stance:iron_body`
mitigation, Tai Chi's `TaiChiCounterCondition`, both passive-regen
trinket rules, Elemental's "water conducts" rule, Physique's tradition-
tag synergy modifiers) is gated by a single generic tag/status check via
`HasTagQuery`/`StatusActive`, never a hardcoded pairing of two specific
named items, techniques, or physiques.

## 7. Hardcoded content

**Finding (Low).**

- **Files:**
  - `lib/src/plugins/martial_arts/martial_item.dart:61-166`
    (`brassKnuckles` through `martialTrinkets`)
  - `lib/src/plugins/elemental/elemental_item.dart` (`emberCharm` and its
    `ElementalItemDefinition`)
- **Problem:** Wearable-item/trinket definitions in both plugins that
  have them are Dart `const` object literals compiled directly into
  source, not data loaded through `ContentRegistry`
  (`lib/src/content/content_registry.dart`), which `CLAUDE.md`'s DATA
  DRIVEN CONTENT section prefers ("Content should preferably be
  represented as data"). This is *not* a violation of the harder rule
  immediately below it in `CLAUDE.md` — "do not create a new
  source-code class for every individual item" — both plugins already
  follow that correctly: one `MartialItemDefinition` class covers all 8
  MartialArts items/trinkets, one `ElementalItemDefinition` class covers
  Elemental's item. Every other kind of content in the engine — Elemental's
  spells (`elemental_content.dart`), MartialArts' techniques/stances
  (`martial_technique_content.dart`, migrated to `ContentRegistry` since
  the prior audit), and Physique's four physiques
  (`physique_content.dart`) — is fully `ContentRegistry`-loaded. Items
  are the one content shape that has never been migrated, in either
  plugin that has them, and the omission is now internally consistent
  across the whole engine rather than a stray inconsistency in one
  plugin (as the prior audit found it).
- **Severity:** Low (downgraded from the prior audit's Medium finding on
  this same category, which covered MartialArts only). The pattern is no
  longer an odd-one-out inconsistency — it is now the engine's uniform,
  deliberate treatment of "equip-time item" content specifically, distinct
  from "spell/technique/physique" content, which one could reasonably
  read as the equip case genuinely not needing `ContentRegistry`'s
  `Effect`/`Condition`/`Rule` envelope (an item's `modifiersFor(wearer)`
  is applied directly via `ModifierCollection.add` inside `equipItem`/
  `equipElementalItem`, never through a `Rule` firing). Still non-zero
  risk: the code is data-*shaped* but not data-*loaded*, so a third-party
  mod cannot add a new item without a source change.
- **Recommended fix:** No urgent action required — this is now a
  considered, consistent design choice rather than an oversight. If item
  content is ever wanted to be moddable without a source change, convert
  both plugins' item definitions to `List<Map<String, dynamic>>` loaded
  via `PluginSdk.registerContentBatch`, mirroring the exact
  data/runtime-split pattern `physiqueDefinitionFromContent`
  (`lib/src/plugins/physique/physique_content.dart`) already established
  for `Modifier`-producing content — that pattern is now proven twice
  (MartialArts' techniques, Physique's physiques) and would transfer
  directly to items. This is genuine design work, not a mechanical
  find-and-replace, so it should get its own brainstorm/spec before
  implementation, same as the prior audit's recommendation.

## 8. Global mutable state

**Result: No violations found.**

Grepped for `static` members across all of `lib/`; every hit is a pure
static *function* (`ElementalItemDefinition`/`MartialItemDefinition`'s
`_noModifiers`, `ApplyElementalStatus._statusFor`, `ContentField`'s
helpers in `json_helpers.dart`, `Container._slotFromJson`) or a `static
const` identifier constant (`MartialStyles.boxing`/`shaolin`/`taiChi`,
`Elements.fire`/`water`/`lightning`, `PhysiqueTypes.sturdy`/`power`/
`burst`/`endurance`) — no mutable `static` field, no singleton
(`static final instance = ...`), no top-level mutable variable anywhere
in the repository, including the new Physique plugin. Every stateful
service (`EntityRegistry`, `ComponentStore`, `EventBus`,
`ModifierCollection`, `ContentRegistry`, `RngService`, ...) is
constructed and held per-`PluginContext`, never reached through a
global.

## 9. Gameplay randomness bypassing RNGService

**Result: No violations found.**

Grepped all of `lib/` for `dart:math`/`Random(`; the only real import
sites are `rng_service.dart:1` (`Random(seed)` — the one sanctioned
construction site) and `modifier_resolver.dart:1`'s `math.min`/`math.max`
(deterministic math, not randomness). The two other grep hits
(`physique_initialization.dart:13`, `condition.dart:151`) are doc
comments *naming* `dart:math` only to say it must never be called
directly — not actual imports. `RandomChance`
(`lib/src/rule/condition.dart`) and `initializePhysique`
(`lib/src/plugins/physique/physique_initialization.dart`) — the two
gameplay code paths that need randomness — route through
`context.rng.chance(...)`/`context.rng.nextInt(...)` respectively, never
`dart:math` directly. Physique's own test suite additionally proves
determinism (same seed ⇒ same physique) and variation (different seeds ⇒
can differ) end to end.

## 10. Components containing excessive gameplay logic

**Result: No violations found.**

Every component class in the repository was read in full:
`HealthComponent`, `ResourceComponent`, `StatComponent`,
`StatusComponent`, `TagSet` (`lib/src/components/`),
`CombatStateComponent`, `CombatantComponent`
(`lib/src/plugins/combat/`), `MartialLoadoutComponent`
(`lib/src/plugins/martial_arts/`), `ElementalAffinityComponent`
(`lib/src/plugins/elemental/`), and `PhysiqueComponent`
(`lib/src/plugins/physique/physique_component.dart` — 10 lines, a single
`physiqueId` field and nothing else). Every one is a plain data holder —
constructor plus fields, at most a `toJson`/`fromJson` pair for
marshaling (data transformation, not gameplay logic). No component
contains a conditional, a loop over other entities, or a call into
`EventBus`/`RuleEngine`.

## 11. God classes

**Finding (Low): `CombatSystem`. Carried over from the prior audit,
unchanged.**

- **File:** `lib/src/plugins/combat/combat_system.dart`
- **Lines:** 1–257 (whole class; 257 lines today, was 267 at the last
  audit — effectively unchanged)
- **Problem:** One class owns battle creation, action execution, turn
  advancement, and battle-end detection (with two separate code paths
  needed to handle a single action killing participants of multiple
  concurrent battles correctly).
- **Severity:** Low — narrow public surface (`startBattle`,
  `executeAction`), heavily commented, every branch covered by tests.
  Flagging only because it remains the second-largest file in the
  engine (behind `content_registry.dart`, which was already split once
  — see the Resolution Log below) and touches the most Combat concerns
  in one place.
- **Recommended fix:** Unchanged from the prior audit: no urgent action.
  If this grows further, consider extracting battle-end detection into
  its own collaborator that `CombatSystem` delegates to.

`ContentRegistry` (`lib/src/content/content_registry.dart`), the prior
audit's Medium god-class finding, is confirmed still fixed: 293 lines
today (down from 354), with built-in effect/condition/trigger vocabulary
registration living in its own file
(`lib/src/content/built_in_content_factories.dart`) as that fix
specified. No new god-class candidate was found elsewhere — `Container`
(`lib/src/spatial/container.dart`, 277 lines) is the only other file over
250 lines, but its length is one cohesive responsibility (spatial
placement query/mutate/serialize for a single abstraction), not several
unrelated ones, so it is not flagged.

## 12. Duplicate engine functionality inside plugins

**Result: No violations found.**

The prior audit's Medium finding here (four independently-reinvented
copies of a standalone `RuleContext`-construction helper) is confirmed
fixed and holding: every plugin that needs a standalone `RuleContext`
now uses the shared `PluginContext.ruleContextFor` extension method —
`lib/src/plugins/elemental/elements.dart:32`,
`lib/src/plugins/combat/combat_system.dart:97,109`,
`lib/src/plugins/martial_arts/martial_item.dart:40`,
`lib/src/plugins/martial_arts/martial_styles.dart:35`,
`lib/src/plugins/elemental/elemental_item.dart:60`. Grepping for a raw
`RuleContext(` construction anywhere under `lib/src/plugins/` returns
zero hits — no plugin has reinvented it since. Physique's
`initializePhysique` doesn't need this helper at all (it manipulates
`ComponentStore`/`ModifierCollection`/`EventBus` directly rather than
applying an `Effect`/`Condition`), so it introduces no new copy of the
pattern. Separately, Physique's `_operationFor` string-to-
`ModifierOperation` switch (`physique_content.dart`) was checked against
every other `ModifierOperation` use in the repo and is genuinely unique
— no other plugin parses modifier operations from a string, since every
other plugin's `Modifier`s are hand-written Dart rather than JSON-loaded.

## 13. Direct cross-plugin calls that should use events/interfaces

**Result: No violations found.**

Grepped every plugin for references to another plugin's system/plugin
classes (`CombatSystem`, `CombatPlugin`, `MartialArtsPlugin`,
`ElementalPlugin`); every hit outside a plugin's own directory is inside
a documentation comment, never executable code
(`martial_arts_plugin.dart:11,47`, `elemental_plugin.dart:22,71`).
`lib/src/plugins/combat/` and `lib/src/plugins/physique/` contain zero
references to `MartialArtsPlugin`/`ElementalPlugin` at all, in prose or
code. Every actual cross-entity interaction (Shaolin's mitigation, Tai
Chi's counter, Elemental's "water conducts", Physique's tradition-tag
synergy) is implemented as either a `Rule` reacting to a published event
through the shared `RuleEngine`, or (Physique's case specifically) a
conditional `Modifier` gated by `HasTagQuery` on a tag another plugin
grants — never a direct call into another plugin's class.

## 14. Domain-specific concepts leaking into Core

**Result: No violations found.**

Same evidence as category 1: zero domain vocabulary (item names, element
names, style names, physique names, resource names like `qi`/`mana`)
appears anywhere under `lib/src/{component,components,content,entity,
event,modifier,plugin,query,rng,rule,spatial}/` outside of doc-comment
examples/citations. `type` fields on `ContentDefinition`/loaded content
remain opaque strings Core stores and indexes but never branches on —
`allOfType`/`withTag` treat `type`/tags as plain equality/set-membership,
confirmed unchanged in the current `content_registry.dart`.

## 15. Serialization depending on runtime implementation classes

**Result: No violations found.**

Every `toJson`/`fromJson` pair in the repository was read:
`Container.toJson`/`fromJson` (`lib/src/spatial/container.dart`),
`CombatStateComponent.toJson`/`fromJson`,
`CombatantComponent.toJson`/`fromJson` (`lib/src/plugins/combat/`),
`MartialLoadoutComponent.toJson`/`fromJson`
(`lib/src/plugins/martial_arts/`), and `ContentRegistry.toJson`
(`lib/src/content/content_registry.dart`). Every one serializes to/from
plain, stable-ID-based primitives (`int`, `String`, `bool`, nested
`Map`/`List` of the same) — none serializes a Dart `Type` object, a
closure, or any other value with meaning only within the current
process. `ContentRegistry.toJson()` still re-exports each definition's
original decoded JSON (`ContentDefinition.raw`) rather than attempting to
serialize the live `Effect`/`Condition` objects parsed from it.
`PhysiqueComponent`, `ElementalAffinityComponent`, and Core's own base
components (`Health`/`Resource`/`Stat`/`Status`/`TagSet`) have no
`toJson`/`fromJson` at all — a save/load *coverage* gap, not a category-15
violation (there is nothing there that could depend on a runtime
implementation class, since there is no serialization code at all yet).
Noted for completeness, not raised as a finding, since coverage
completeness is outside what this category asks for.

---

## Additional observations (outside the 15 requested categories)

**C. `'western'`/`'eastern'` tradition-tag literals — the entire
interoperability contract between MartialArts and Physique — are raw
string literals with no backing constant in either plugin.**

- **Files:**
  - `lib/src/plugins/martial_arts/martial_styles.dart:60-61`
  - `lib/src/plugins/martial_arts/martial_technique_content.dart:27,44,66,82,96,110,123,137,151`
  - `lib/src/plugins/martial_arts/martial_item.dart:63,79,95,111,127,141,146,162`
  - `lib/src/plugins/physique/physique_content.dart:33,39,53,59,73,79,93,99`
- **Problem:** `CLAUDE.md`'s CODE QUALITY section lists "magic strings
  scattered throughout code" under "Avoid," and its own resolution log
  already fixed this exact shape of issue once (Observation B, prior
  audit — `MartialResources`/`MartialStances`/`ElementalResources`/
  `ElementalStatuses` constant classes). `'western'`/`'eastern'` were not
  covered by that fix (they didn't exist yet) and are a stricter case
  than an ordinary in-plugin magic string: these two literals are the
  *entire* mechanism binding two independent plugins together with zero
  shared import — Physique's `physique_content.dart` and MartialArts'
  `martial_styles.dart` each independently spell the same two strings,
  and neither can import a shared constants file from the other without
  reintroducing the cross-plugin dependency this design deliberately
  avoids. A typo in either plugin (`'wester'` vs `'western'`) would
  silently break the synergy mechanic at runtime with no compile error
  and no obviously-failing test unless the specific synergy scenario is
  exercised.
- **Severity:** Low — both plugins' own test suites already exercise the
  synergy end-to-end with the current spelling
  (`test/integration/physique_synergy_test.dart`), so a typo introduced
  today would be caught immediately; the risk is only for a *future*
  edit to either plugin that doesn't re-run that specific integration
  test.
- **Recommended fix:** Each plugin should name these two strings locally
  — e.g. a small `abstract final class MartialTraditions { static const
  western = 'western'; static const eastern = 'eastern'; }` (or fold
  into the existing `MartialVocabulary`-style class each plugin already
  has), defined once per plugin and referenced everywhere that plugin
  currently spells the literal. This does **not** create a shared
  dependency — each plugin still independently defines and owns its own
  copy of the same two constant *values*, exactly the same way both
  plugins today independently agree on the string `'martial'` or
  `'physique'` without sharing a definition. Two independent constant
  classes with matching values is consistent with `CLAUDE.md`'s "tags
  are the universal language for content interoperability... the engine
  does not interpret these tags" — the interoperability contract is the
  *string value*, not a shared Dart symbol.

---

## Resolution Log (from the prior audit, 2026-08-23 — preserved for history)

Approved via "fix everything." All items below were already fixed before
this new audit began, and this audit independently re-verified each
still holds (see the relevant category sections above).

1. **Finding #12** (dedupe `RuleContext` construction) —
   `PluginContext.ruleContextFor` added
   (`lib/src/plugin/plugin_context.dart`); all four call sites (plus a
   fifth/sixth added since, in Elemental's and MartialArts' item-equip
   functions, and a seventh in `martial_styles.dart`) now use it. Commit
   `b814da9`.
2. **Finding #11, `ContentRegistry` half** (extract built-in vocabulary)
   — moved to `lib/src/content/built_in_content_factories.dart`;
   `ContentRegistry` shrank 354 → 293 lines. Commit `42f724a`.
3. **Observation A** (missing `EntityDestroyed` cleanup) — `CombatPlugin`
   and `MartialArtsPlugin` both adopted `PluginSdk`. `PhysiquePlugin`,
   built after this fix, used `sdk.registerComponentCleanup<T>()` from
   day one. Commit `ea60cd5`.
4. **Finding #7** (MartialArts techniques predated `ContentRegistry`) —
   the 9 techniques/stances moved to data
   (`lib/src/plugins/martial_arts/martial_technique_content.dart`).
   Commit `04f776d`. (Items/trinkets were deliberately *not* migrated —
   see this audit's own Finding #7 above, now reframed as an engine-wide
   consistent pattern rather than an inconsistency.)
5. **Observation B** (magic strings) — added
   `MartialResources`/`MartialStances`
   (`lib/src/plugins/martial_arts/martial_vocabulary.dart`) and
   `ElementalResources`/`ElementalStatuses`
   (`lib/src/plugins/elemental/elemental_vocabulary.dart`). Commit
   `9350f52`. (Did not — and could not, at the time — cover the
   `'western'`/`'eastern'` tags introduced later by Physique; see
   Additional Observation C above.)

Every commit above kept `dart analyze` clean and the full test suite
green before being made. As of this audit: `dart analyze` clean, 513
tests passing, at commit `7852ac7`.
