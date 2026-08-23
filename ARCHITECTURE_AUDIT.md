# Build Engine — Architecture Audit

**Date:** 2026-08-23
**Scope:** `lib/` (all Core services and all plugins: Combat, MartialArts,
ExampleElemental) against the architecture contract in `CLAUDE.md`.
**Method:** full read of `CLAUDE.md`; a complete file inventory of `lib/`
(64 files); import-graph inspection of every directory under `lib/src/`;
targeted greps for domain vocabulary in Core, `dart:math`/`Random` usage
outside `RngService`, static/global mutable state, and hardcoded
plugin-id special-casing; line-by-line reading of every component class,
`CombatSystem`, `ContentRegistry`, `PluginSdk`, and every plugin's rule/
condition/effect files.
**Status:** No code changes made. This is a report only, per the request.

## Summary

Of the 15 categories requested, **12 have no violations**. **3 have real
findings** — none rise to Critical: two are moderate design debt (a
duplicated helper, two classes carrying more responsibility than ideal),
and one is a soft inconsistency (MartialArts predates `ContentRegistry`
and hasn't been migrated to it). A short "Additional Observations"
section at the end notes two smaller things outside the 15 requested
categories, found along the way.

| # | Category | Result |
|---|---|---|
| 1 | Core importing game-specific modules | ✅ No violations |
| 2 | Combat importing MartialArts | ✅ No violations |
| 3 | Combat importing Magic | ✅ N/A — no Magic plugin exists |
| 4 | Plugins accessing private implementation of other plugins | ✅ No violations |
| 5 | Circular dependencies | ✅ No violations |
| 6 | Hardcoded item combinations | ✅ No violations |
| 7 | Hardcoded content | ⚠️ 1 finding (Medium) |
| 8 | Global mutable state | ✅ No violations |
| 9 | Gameplay randomness bypassing RNGService | ✅ No violations |
| 10 | Components containing excessive gameplay logic | ✅ No violations |
| 11 | God classes | ⚠️ 2 findings (Medium, Low) |
| 12 | Duplicate engine functionality inside plugins | ⚠️ 1 finding (Medium) |
| 13 | Direct cross-plugin calls that should use events/interfaces | ✅ No violations |
| 14 | Domain-specific concepts leaking into Core | ✅ No violations |
| 15 | Serialization depending on runtime implementation classes | ✅ No violations |

---

## 1. Core importing game-specific modules

**Result: No violations found.**

Every file under `lib/src/{component,components,content,entity,event,
modifier,plugin,query,rng,rule,spatial}/` was grep'd for imports; every
import resolves to another file inside `lib/src/` (never `lib/src/
plugins/`) or a `dart:` SDK import. `dart:math` appears in exactly two
places: `lib/src/rng/rng_service.dart` (the sanctioned location) and
`lib/src/modifier/modifier_resolver.dart:1,46,51` (`math.min`/`math.max`
for the MIN/MAX modifier operations — not randomness). No Core file
contains martial-arts/magic/combat/item vocabulary; confirmed by
grepping Core for `sword|spell|fireball|qi|boxing|shaolin|martial|
cultivat|potion|dragon|mana` — the only hits are documentation
comments in `content_definition.dart` illustrating the JSON schema with
`CLAUDE.md`'s own `iron_sword` example, not actual code.

## 2. Combat importing MartialArts

**Result: No violations found.**

`lib/src/plugins/combat/*.dart` imports only `package:build_engine/
build_engine.dart` (Core's public barrel) and its own sibling files.
Grep for `MartialArts`/`martial_arts` inside `lib/src/plugins/combat/`
returns zero hits. The dependency runs the sanctioned direction only:
`MartialArts -> Combat -> Core` (`lib/martial_arts_plugin.dart`'s doc
comment and `MartialArtsPlugin.dependencies => const ['combat']`).

## 3. Combat importing Magic

**Result: N/A — no Magic plugin exists in this repository.** No
violation to find; noting for completeness that Combat's only inbound
dependent today is MartialArts.

## 4. Plugins accessing private implementation of other plugins

**Result: No violations found.**

Every cross-plugin reference goes through a public barrel
(`package:build_engine/combat_plugin.dart`), never a `lib/src/plugins/
combat/...` path directly:

- `lib/src/plugins/martial_arts/martial_conditions.dart:2`
- `lib/src/plugins/martial_arts/martial_arts_rules.dart:2`
- `lib/src/plugins/martial_arts/martial_technique_action.dart:2`

No plugin holds a live reference to another plugin's internal class.
`MartialArtsPlugin` explicitly documents (and the code confirms) that it
"never holds a reference to `CombatPlugin`/`CombatSystem` — only to
Combat's public event vocabulary" (`lib/src/plugins/martial_arts/
martial_arts_plugin.dart:8-12`). `ExampleElementalPlugin` imports nothing
from either Combat or MartialArts at all.

## 5. Circular dependencies

**Result: No violations found.**

The import graph is a strict DAG: `Core <- Combat <- MartialArts`,
`Core <- ExampleElemental`. No file under `lib/src/` imports anything
under `lib/src/plugins/`, so a cycle back into Core is structurally
impossible. `PluginManager.resolveLoadOrder()`
(`lib/src/plugin/plugin_manager.dart:36-71`) additionally detects and
throws `CyclicPluginDependencyException` on any *declared* plugin
dependency cycle at runtime — a second, independent guard.

## 6. Hardcoded item combinations

**Result: No violations found.**

Every cross-entity interaction found (Shaolin's `stance:iron_body`
mitigation, Tai Chi's `TaiChiCounterCondition`, both passive-regen
trinket rules, ExampleElemental's "water conducts" rule) is gated by a
single generic tag/status check, not a hardcoded pairing of two specific
named items or techniques
(`lib/src/plugins/martial_arts/martial_arts_rules.dart:10-57`,
`lib/src/plugins/example_elemental/elemental_rules.dart:9-16`). No file
contains an `if (id == 'x' && id2 == 'y')`-shaped combination check.

## 7. Hardcoded content

**Finding (Medium).**

- **File:** `lib/src/plugins/martial_arts/martial_item.dart`
- **Lines:** 72–177 (`brassKnuckles` through `martialTrinkets`)
- **File:** `lib/src/plugins/martial_arts/martial_technique_action.dart`
- **Lines:** 56–206 (`jab` through `yieldingStance`)
- **Problem:** All 5 items, 3 trinkets, 6 techniques, and 3 stances are
  Dart `const` object literals / factory functions compiled directly
  into the plugin's source, not data loaded through `ContentRegistry`
  (`lib/src/content/content_registry.dart`), which now exists and is
  exactly the mechanism `claude.md`'s DATA DRIVEN CONTENT section asks
  for ("Content should preferably be represented as data"). This is
  *not* a violation of the harder rule immediately below it in
  `claude.md` — "do not create a new source-code class for every
  individual item" — MartialArts already follows that correctly: one
  `MartialItemDefinition` class covers all 8 items/trinkets, and one
  `MartialTechniqueAction` class covers all 9 techniques/stances. The
  gap is the softer, "preferably data" half of the same guidance, and
  exists because `MartialArtsPlugin` was built in an earlier pass,
  before `ContentRegistry` existed. `ExampleElementalPlugin`
  (`lib/src/plugins/example_elemental/elemental_content.dart`) shows the
  fully-migrated version of the same pattern: three spells as
  `Map<String, dynamic>` definitions loaded via
  `PluginSdk.registerContentBatch`.
- **Severity:** Medium — no correctness or architecture-boundary risk
  (the code is still fully data-*shaped*, just not data-*loaded*), but
  it's an inconsistency between the engine's two content plugins that a
  third-party developer reading both would reasonably find confusing.
- **Recommended fix:** Convert `martial_item.dart`'s 8 definitions and
  `martial_technique_action.dart`'s 9 definitions into
  `List<Map<String, dynamic>>` literals loaded via
  `MartialArtsPlugin.initialize`'s `PluginSdk.registerContentBatch`,
  mirroring `elemental_content.dart` exactly. `MartialTechniqueAction`
  itself can stay as the runtime `CombatAction` implementation (a
  content definition still needs *some* Dart type to become a live
  `CombatAction`); only the *values* (damage numbers, resource costs,
  tag sets, per-technique conditions) need to move to data. Requires
  registering `MartialTechniqueAction`-shaped content as its own
  `ContentRegistry` "kind" (or extending `ContentDefinition` with an
  optional `selfEffects`/`baseDamage`/`damageStat` reading, since
  today's envelope only produces `costEffects`/`conditions`/`effects`,
  not a full `CombatAction`) — this is genuine design work, not a
  mechanical find-and-replace, so it should get its own brainstorm/spec
  before implementation.

## 8. Global mutable state

**Result: No violations found.**

Grepped for `static` members across all of `lib/`; every hit is a pure
static *function* (`ContentField`'s helpers in `json_helpers.dart`,
`Container._slotFromJson`, `MartialItemDefinition._noModifiers`,
`ApplyElementalStatus._statusFor`) or a `static const` identifier
constant (`MartialStyles.boxing`/`shaolin`/`taiChi`,
`Elements.fire`/`water`/`lightning`) — no mutable `static` field, no
singleton (`static final instance = ...`), no top-level mutable
variable anywhere. Every stateful service (`EntityRegistry`,
`ComponentStore`, `EventBus`, `ModifierCollection`, `ContentRegistry`,
`RngService`, ...) is constructed and held per-`PluginContext`, never
reached through a global.

## 9. Gameplay randomness bypassing RNGService

**Result: No violations found.**

Grepped all of `lib/` for `dart:math`/`Random(`; the only two hits are
`rng_service.dart` itself (`Random(seed)` at line 8 — the one sanctioned
construction site) and `modifier_resolver.dart`'s `math.min`/`math.max`
(deterministic math, not randomness). `RandomChance`
(`lib/src/rule/condition.dart:152-158`) — the one gameplay condition
that needs randomness — routes through `context.rng.chance(probability)`,
never `dart:math` directly.

## 10. Components containing excessive gameplay logic

**Result: No violations found.**

Every component class in the repository was read in full:
`HealthComponent`, `ResourceComponent`, `StatComponent`,
`StatusComponent`, `TagSet` (`lib/src/components/`),
`CombatStateComponent`, `CombatantComponent`
(`lib/src/plugins/combat/`), `MartialLoadoutComponent`
(`lib/src/plugins/martial_arts/`), `ElementalAffinityComponent`
(`lib/src/plugins/example_elemental/`). Every one is a plain data holder
— constructor plus fields, at most a `toJson`/`fromJson` pair for
marshaling (which is data transformation, not gameplay logic). No
component contains a conditional, a loop over other entities, or a call
into `EventBus`/`RuleEngine`.

## 11. God classes

**Finding (Medium): `ContentRegistry`.**

- **File:** `lib/src/content/content_registry.dart`
- **Lines:** 26–354 (whole class)
- **Problem:** One class carries five distinct responsibilities: factory
  registration (40–62), definition loading/validation (64–139), lookup
  (141–155), serialization (157–169), and — the largest single chunk —
  registering Core's own built-in effect/condition/trigger vocabulary
  (297–354, ~58 lines). None of these individually is complex, but
  together they make this the largest file in the engine (354 lines,
  vs. the next-largest Core file at 234) and mean a change to "which
  built-in effects exist" and a change to "how batch loading validates
  `requires`" both touch the same class.
- **Severity:** Medium — the class is well-tested and each section is
  independently comprehensible (clearly delimited by `// --- section
  ---` comments), so this is a maintainability risk, not a correctness
  or architecture-boundary one.
- **Recommended fix:** Extract the built-in-vocabulary registration
  (lines 297–354) into a standalone top-level function (e.g.
  `void registerCoreEffectFactories(ContentRegistry registry)` in its
  own file) called from the constructor, and consider extracting the
  parsing/validation internals (171–296) into a package-private
  `_ContentParser` class that `ContentRegistry` delegates to — leaving
  `ContentRegistry` itself as storage + lookup + orchestration only.

**Finding (Low): `CombatSystem`.**

- **File:** `lib/src/plugins/combat/combat_system.dart`
- **Lines:** 17–267 (whole class)
- **Problem:** One class owns battle creation, action execution, turn
  advancement, and battle-end detection (with two separate code paths —
  `_checkBattleEndFor`/`_checkPendingBattlesOtherThan` for the
  in-`executeAction` case, `_onEntityKilled` for the reactive case —
  needed to handle a single action killing participants of multiple
  concurrent battles correctly).
- **Severity:** Low — this is 267 lines behind a single, narrow public
  surface (`startBattle`, `executeAction`), heavily commented to explain
  *why* the split-path battle-end logic exists, and every branch is
  covered by tests. Flagging only because it's the second-largest file
  in the engine and touches the most core Combat concerns in one place.
- **Recommended fix:** No urgent action. If this grows further (e.g. a
  future Scheduler integration), consider extracting battle-end
  detection into its own collaborator (`_BattleEndDetector` or similar)
  that `CombatSystem` delegates to, the same split recommended above for
  `ContentRegistry`.

## 12. Duplicate engine functionality inside plugins

**Finding (Medium).**

- **Files:**
  - `lib/src/plugins/martial_arts/martial_item.dart:24-33`
  - `lib/src/plugins/example_elemental/elements.dart:14-23`
  - `lib/src/plugins/combat/combat_system.dart:128-137` (a third,
    near-identical variant, `_ruleContextFor`)
- **Problem:** `martial_item.dart:24-33` and `elements.dart:14-23` are a
  **byte-for-byte identical** private helper function, independently
  reinvented in two plugins that don't depend on each other:

  ```dart
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
  ```

  `combat_system.dart:128-137`'s `_ruleContextFor` builds the same
  `RuleContext` shape with one real difference (a real `triggerEvent`
  instead of `const Object()`). This is exactly the kind of boilerplate
  `PluginSdk` (`lib/src/plugin/plugin_sdk.dart`) was built to eliminate
  for subscriptions/rules/content, but no equivalent helper exists yet
  for "construct a standalone `RuleContext` to apply a `Condition`/
  `Effect` outside of an event-triggered rule firing" — every plugin
  that needs one (which is any plugin applying a `Effect`/`Condition`
  directly, e.g. to grant a tag at item-equip or attunement time) has to
  reinvent it.
- **Severity:** Medium — no correctness risk today (all three
  constructions are equivalent and correct), but it's unowned,
  copy-pasted Core-adjacent plumbing that will silently drift if
  `RuleContext`'s field list ever changes (a new required field would
  need updating in three unrelated files, and a fourth plugin author
  would likely paste a fourth copy rather than discover the pattern).
- **Recommended fix:** Add one method to `PluginContext` (or a
  `PluginSdk` method, e.g. `sdk.ruleContextFor(subject, {Object?
  triggerEvent})`) that constructs a `RuleContext` from the context's own
  services, defaulting `triggerEvent` to `const Object()`. Replace all
  three call sites. This is a small, mechanical, low-risk fix — a good
  first candidate to implement once this audit is approved.

## 13. Direct cross-plugin calls that should use events/interfaces

**Result: No violations found.**

Grepped every plugin for references to another plugin's system classes
(`CombatSystem`, `CombatPlugin`); every hit outside `lib/src/plugins/
combat/` itself is inside a documentation comment, never executable
code. Every actual cross-entity interaction (Shaolin's mitigation, Tai
Chi's counter, ExampleElemental's "water conducts") is implemented as a
`Rule` reacting to a published event (`EntityDamaged`/`ActionCompleted`)
through the shared `RuleEngine`, exactly the pattern `ARCHITECTURE.md`'s
MartialArts section documents as the deliberate resolution to this
category of risk.

## 14. Domain-specific concepts leaking into Core

**Result: No violations found.**

Same evidence as category 1: zero domain vocabulary (item names,
element names, style names, resource names like `qi`/`mana`) appears
anywhere under `lib/src/{component,components,content,entity,event,
modifier,plugin,query,rng,rule,spatial}/` outside of doc-comment
examples. `type` fields on `ContentDefinition`/loaded content are opaque
strings Core stores and indexes but never branches on
(`lib/src/content/content_registry.dart`'s `allOfType`/`withTag` treat
`type`/tags as plain equality/set-membership, never a `switch` on known
values).

## 15. Serialization depending on runtime implementation classes

**Result: No violations found.**

Every `toJson`/`fromJson` pair in the repository was read:
`Container.toJson`/`fromJson` (`lib/src/spatial/container.dart:170-223`),
`CombatStateComponent.toJson`/`fromJson`
(`lib/src/plugins/combat/combat_state_component.dart`),
`CombatantComponent.toJson`/`fromJson` (same directory),
`MartialLoadoutComponent.toJson`/`fromJson`
(`lib/src/plugins/martial_arts/martial_loadout_component.dart`), and
`ContentRegistry.toJson` (`lib/src/content/content_registry.dart:166-169`).
Every one serializes to/from plain, stable-ID-based primitives (`int`,
`String`, `bool`, nested `Map`/`List` of the same) — none serializes a
Dart `Type` object, a closure, or any other value that only has meaning
within the current process. `ContentRegistry.toJson()` in particular was
deliberately designed to re-export each definition's original decoded
JSON (`ContentDefinition.raw`) rather than attempt to serialize the live
`Effect`/`Condition` objects parsed from it — see `ARCHITECTURE.md`'s
Content Registry section.

---

## Additional observations (outside the 15 requested categories)

These aren't part of the requested checklist but were noticed during
the audit and are worth recording.

**A. `CombatPlugin`/`MartialArtsPlugin` never clean up their own
components on `EntityDestroyed`.** `CombatStateComponent`/
`CombatantComponent` (Combat) and `MartialLoadoutComponent`
(MartialArts) are never removed when an entity carrying them is
destroyed — grep for `EntityDestroyed` inside `lib/src/plugins/combat/`
and `lib/src/plugins/martial_arts/` returns zero hits. This is a latent
component-store leak (harmless at test scale, real in a long-running
game). `PluginSdk.registerComponentCleanup<T>()`
(`lib/src/plugin/plugin_sdk.dart:30-41`) now exists as the sanctioned
fix and is already used by `ExampleElementalPlugin` — Combat and
MartialArts predate it and haven't been retrofitted. Low-to-Medium
severity; straightforward fix (one `sdk.registerComponentCleanup<T>()`
call per owned component type, in each plugin's `initialize`).

**B. Magic strings for tag/resource/status names.** `claude.md`'s CODE
QUALITY section lists "magic strings scattered throughout code" under
"Avoid." Style ids are centralized (`MartialStyles`/`Elements`), but
resource names (`'qi'`, `'momentum'`, `'mana'`) and status/stance tag
strings (`'stance:iron_body'`, `'stance:tai_chi'`,
`'status:soaked'`/`'status:shocked'`/`'status:burning'`) are raw string
literals repeated across several files within each plugin (e.g. `'qi'`
appears as a literal in both `martial_technique_action.dart` and
`martial_arts_rules.dart`; `'status:soaked'` in both
`elemental_effects.dart` and `elemental_rules.dart`). Not cross-plugin
duplication (category 12) — each repetition is within one plugin's own
files — and each individual plugin is internally consistent, but a
typo in one of these literals would be a silent runtime mismatch, not a
compile error. Low severity; recommended fix is a small `abstract final
class`-of-constants per plugin (mirroring `MartialStyles`/`Elements`
for the tag/resource names each plugin already introduces), not a
structural change.

---

## Next steps

No changes have been made. Per the request, this stops at reporting.
Awaiting approval before any refactoring — recommend prioritizing
finding #12 (the `_standaloneContext` duplication) as the lowest-risk,
highest-value fix if a follow-up pass is approved; findings #7 and #11
are larger design changes better handled as their own brainstormed/
planned passes rather than folded into a quick fix-up.
