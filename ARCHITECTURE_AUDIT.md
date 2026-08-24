# Build Engine — Architecture Audit

**Date:** 2026-08-24
**Commit audited:** `7d271a6` (main) — 162 `.dart` files under `lib/`, ~8,806
lines. Covers everything present since the prior audit (`227bf69`) plus
five new subsystems added after it: the **Item** plugin, the **Technique**
plugin, the **Training** exercises (Timing/Precision/Reaction/Power/Combo +
`WeightedTrainingExercise`), the **Build Interpretation** layer
(`BuildActionInterpreter`/`TechniqueActionInterpreter`/
`ItemActionInterpreter`/`SelfEffectAction`), and the **AutoCombat scoring
policy** (`ActionScorer`/`DefaultActionScorer`/`ScoredActionSelector`).
**This is a from-scratch audit**, not a diff — every category was
re-verified against the current code.
**Method:** full read of `CLAUDE.md`; a complete file inventory and line-
count survey of `lib/`; per-plugin import-graph extraction (barrel-level)
to check the dependency DAG; targeted greps for domain vocabulary in Core,
`dart:math`/`Random` usage outside `RngService`, mutable `static` fields,
`id ==`-shaped combination checks, cross-plugin private-path imports, and
duplicated algorithm/pattern logic; re-reading every component-shaped
class added since the prior audit.
**No changes have been made.** Per this audit's own instructions, this is
a report only — refactoring requires separate approval.
**Baseline at time of audit:** `dart analyze` clean, 906 tests passing.

**Update (2026-08-24, same day): approved via "fix all."** Both category-7
and category-12 findings, and Additional Observation A, were fixed — see
each section below and the Resolution Log for specifics. `dart analyze`
clean and all tests passing after every fix (906 → 908; the 2 new tests
directly demonstrate Additional Observation A's fix). Additional
Observation B was left alone (unchanged, still informational, not a
finding, per its own text).

## Summary

Of the 15 categories requested, **13 have no violations**. **2 have real
findings** (both **new**, introduced by the five subsystems added since
the prior audit — nothing carried over from before regressed). One
previously-known, previously-deferred design risk (Additional Observation
A, below) now has concrete evidence it has bitten real development twice,
and is upgraded from informational to a recommendation.

**Update (2026-08-24, same day): approved via "fix all."** Both category-7
and category-12 findings, and Additional Observation A, are now **fixed**
— see each section's Status note and the Resolution Log. `dart analyze`
clean and all tests passing (906 → 908) after every fix.

| # | Category | Result |
|---|---|---|
| 1 | Core importing game-specific modules | ✅ No violations |
| 2 | Combat importing MartialArts | ✅ No violations |
| 3 | Combat importing Magic | ✅ N/A — no Magic plugin exists |
| 4 | Plugins accessing private implementation of other plugins | ✅ No violations |
| 5 | Circular dependencies | ✅ No violations |
| 6 | Hardcoded item combinations | ✅ No violations |
| 7 | Hardcoded content | ⚠️ 1 finding (Low) → ✅ Fixed |
| 8 | Global mutable state | ✅ No violations |
| 9 | Gameplay randomness bypassing RNGService | ✅ No violations |
| 10 | Components containing excessive gameplay logic | ✅ No violations |
| 11 | God classes | ✅ No new findings — one Low finding carried over unchanged, no action recommended |
| 12 | Duplicate engine functionality inside plugins | ⚠️ 2 findings (1 Medium, 1 Low) → ✅ Fixed |
| 13 | Direct cross-plugin calls that should use events/interfaces | ✅ No violations |
| 14 | Domain-specific concepts leaking into Core | ✅ No violations |
| 15 | Serialization depending on runtime implementation classes | ✅ No violations (coverage gap widens — see category 15) |

---

## 1. Core importing game-specific modules

**Result: No violations found.**

Every file under the 21 current Core directories (`lib/src/{character,
component, components, content, discovery, entity, event, evolution,
mastery, modifier, plugin, progression, query, resource, reward, rng, rule,
spatial, tome, training}/`) was grepped for every plugin barrel filename
(`combat_plugin.dart`, `martial_arts_plugin.dart`, `elemental_plugin.dart`,
`physique_plugin.dart`, `auto_combat_plugin.dart`, `item_plugin.dart`,
`technique_plugin.dart`, `build_interpretation.dart`) — zero hits. A second
grep for domain vocabulary (`sword|fireball|qi|boxing|shaolin|martial|
cultivat|potion|dragon|mana|physique|sturdy|punch|jab|elemental|
iron_sword|brass_knuckles|basic_punch|basic_slash|basic_guard|knife|
gloves`) across the same directories returns only doc-comment prose:
worked examples (`"item:iron_sword"`, `"technique:jab"`, `"Basic Punch"`),
and explicit anti-pattern citations (`no SwordMastery`, `not martial-arts
terminology`) — never executable code. `lib/src/training/` (the newest
Core addition, five exercise implementations) was specifically checked:
every "martial"/"magic"/"alchemy" mention in its doc comments is a
negation or a generic cross-domain example (`"a martial parry window, a
magic incantation window, an alchemy stir-timing window"`), never a
dependency.

## 2. Combat importing MartialArts

**Result: No violations found.**

`lib/src/plugins/combat/` (4 files, including the newly-added `priority`
getter on `CombatAction` — see category 12/other-notes) imports only
`package:build_engine/build_engine.dart` and its own sibling files.
Grepped for `martial_arts`/`MartialArts`/`magic_plugin`/`MagicPlugin` —
zero hits.

## 3. Combat importing Magic

**Result: N/A — no Magic plugin exists in this repository.**

## 4. Plugins accessing private implementation of other plugins

**Result: No violations found.**

Grepped every plugin directory (`combat`, `martial_arts`, `elemental`,
`physique`, `auto_combat`, `item`, `technique`, `build_interpretation`)
for a `lib/src/plugins/<other>/` relative import path — zero hits
anywhere, including the three plugins added since the prior audit. Every
cross-plugin reference goes through a public barrel:

- `lib/src/plugins/martial_arts/*.dart` → `combat_plugin.dart` only.
- `lib/src/plugins/auto_combat/*.dart` → `combat_plugin.dart` only.
- `lib/src/plugins/build_interpretation/*.dart` → `combat_plugin.dart`,
  `item_plugin.dart`, `technique_plugin.dart` — all barrels, confirmed by
  the same grep.
- `lib/src/plugins/{combat, elemental, physique, item, technique}/` — no
  plugin barrel imports at all.

## 5. Circular dependencies

**Result: No violations found.**

Full barrel-level import graph, extracted directly from source:

```
Core <- Combat
Core <- Elemental
Core <- Physique
Core <- Item
Core <- Technique
Core + Combat <- MartialArts
Core + Combat <- AutoCombat
Core + Combat + Item + Technique <- BuildInterpretation
```

A strict DAG — `BuildInterpretation` is the new "widest" node (three
dependencies) but nothing depends on it in turn, and nothing it depends on
depends back on it. `PluginManager.resolveLoadOrder()` additionally
detects any *declared* plugin-dependency cycle at runtime; unaffected by
this session's additions since none of the five new subsystems declare
plugin `dependencies` at all except implicitly via direct barrel imports
in `build_interpretation` (which isn't itself a registered `GamePlugin` —
see category 13's note).

## 6. Hardcoded item combinations

**Result: No violations found.**

Grepped the whole `lib/src/plugins/` tree for an `id ==`-shaped
conditional — zero hits, including the three new plugins. Every
cross-entity interaction remains gated by a generic tag/status/mastery-
level/discovery check. The new `TechniqueActionInterpreter`/
`ItemActionInterpreter` (Build Interpretation) follow the same discipline:
they branch on a technique's/item's *tags* (`'guard'`, `'fist'`, `'blade'`)
and on the *presence* of a `properties['damage']`/`['attack']` entry —
never on a specific content id.

## 7. Hardcoded content

**Finding (Low, new): per-subject Training weight maps are hand-written
Dart `const` data, not `ContentRegistry`-loaded content.**

- **Files:**
  - `lib/src/plugins/technique/technique_training_weights.dart:6-10`
  - `lib/src/plugins/item/item_training_weights.dart:6-10`
- **Problem:** The Training Exercises milestone's own instruction was
  "[weights] belong in content definitions" — read at the time as "not
  hardcoded inside the Training *Engine*" (satisfied: `lib/src/training/`
  has zero knowledge of `'basic_punch'`/`'iron_sword'`), but the weight
  *values themselves* (`{'speed': 0.3, 'power': 0.2, ...}`) are still
  plain Dart `Map` literals baked into the plugin's source, not entries
  loadable/editable through `ContentRegistry` the way
  `techniqueContentDefinitions`/`itemContentDefinitions` are (JSON-shaped
  maps, parsed via `ContentRegistry.loadAll`). A designer changing a
  technique's training profile has to edit and recompile Dart, unlike
  every other numeric tuning value in these two plugins.
- **Severity:** Low — these are two small, self-contained maps (5 lines
  of data each), not gameplay *logic*, and every other piece of category-
  7-relevant content in the repo (item/technique definitions themselves)
  is already correctly `ContentRegistry`-loaded; this is a narrower,
  clearly-scoped exception, not a systemic pattern.
- **Recommended fix:** If these maps are expected to grow or be
  designer-tunable independent of code review, migrate them into
  `techniqueContentDefinitions`/`itemContentDefinitions` themselves as a
  `'trainingWeights'` extra field (parsed the same way
  `'properties'`/`'evolution'` already are), or into their own small
  `ContentRegistry`-loaded `'training_configuration'`-typed entries. Not
  urgent — no correctness impact, purely a content-authoring ergonomics
  question.

**Status: ✅ Fixed (2026-08-24, same day).** Migrated exactly as
recommended: both `technique_content.dart`'s 3 base entries and
`item_content.dart`'s `knife`/`iron_sword`/`gloves` entries now carry a
`'training'` extra field with the same weight values the two removed Dart
constants held; `TechniqueDefinition`/`ItemDefinition` each gained a
`trainingWeights` field parsed from it (mirroring how `properties` is
parsed). `techniqueTrainingExerciseFor`/`itemTrainingExerciseFor` now take
the already-parsed `TechniqueDefinition`/`ItemDefinition` directly instead
of looking a bare id up in a standalone map — a cleaner API aligned with
every other Item/Technique lifecycle function, which already take the
`Definition` object rather than a bare id. `technique_training_weights.dart`/
`item_training_weights.dart` shrank from a 16–18-line const map + lookup
function to a single 4-line wrapper each. `dart analyze` clean, all tests
passing (2 call sites updated: `test/training/weighted_training_exercise_test.dart`,
`test/integration/training_pipeline_integration_test.dart`).

## 8. Global mutable state

**Result: No violations found.**

Grepped for every `static` declaration across `lib/`; every hit is a pure
static *function* (`TechniqueDefinition._noModifiers`,
`ItemDefinition._noModifiers`, `ContentField`'s helpers,
`Container._slotFromJson`, `ElementalEffects._statusFor`) or already
excluded as `static const`. No mutable `static` field, no singleton, no
top-level mutable variable anywhere — confirmed across all five new
subsystems (`ActionScorer`/`ScoredActionSelector`, the five training
exercises, `ItemInstance`, `TechniqueDefinition`, `BuildActionInterpreter`
and its implementations) as well as everything audited previously.

## 9. Gameplay randomness bypassing RNGService

**Result: No violations found.**

Grepped all of `lib/src/` for `dart:math`/`Random(`. Real `dart:math`
imports remain exactly `modifier_resolver.dart` (`math.min`/`math.max`,
previously audited) plus two new, equally non-random uses added by the
Training milestone: `precision_exercise.dart:1` and
`training_statistics.dart:1`, both importing `dart:math` solely for
`math.sqrt` (Euclidean distance and population standard deviation —
deterministic arithmetic, not randomness). Every other match is a doc
comment *negating* direct `dart:math`/`Random` use (`RandomChance`'s own
doc comment, `physique_initialization.dart`, `weighted_pick.dart`). No
`Random(` construction anywhere outside `rng_service.dart`. The two new
resolvers/scorers that could plausibly need randomness —
`ScoredActionSelector` and `DefaultActionScorer` — use none at all
(deterministic tie-breaking by list order, per the AutoCombat milestone's
own requirement).

## 10. Components containing excessive gameplay logic

**Result: No violations found.**

Every `class ...Component`-named type in the repository was re-enumerated
(15 total, one new since the prior audit: `ItemInstance`, which — despite
not being literally named `...Component` — is the Item plugin's own
ECS-attached runtime-state type and was reviewed on the same basis).
`ItemInstance` (`lib/src/plugins/item/item_instance.dart`) is two fields
(`definitionId`, `owner`), no methods — deliberately kept that way per its
own doc comment, precisely to avoid duplicating `DiscoveryTracker`/
`MasteryTracker` state. No new component-shaped class contains a
conditional, a loop over other entities, or a call into
`EventBus`/`RuleEngine`/any service.

## 11. God classes

**Result: no new findings.** The one previously-identified item remains
open, unchanged, by design:

- **File:** `lib/src/plugins/combat/combat_system.dart` (257 lines,
  unchanged since the prior audit — `combat_action.dart` gained one new
  defaulted `priority` getter this session, `combat_system.dart` itself
  was not touched by any of the five new subsystems).
- **Severity:** Low, carried over — same reasoning as both prior audits
  (narrow public surface, heavily commented, every branch tested).
- **Recommended fix:** Unchanged — no urgent action.

A full line-count survey of every file added by the five new subsystems
(41 files, 2,029 lines total) found nothing over 176 lines
(`technique_content.dart`, pure data — 11 content definitions — not
logic-dense); every behavioral file (interpreters, scorers, lifecycle
functions) is under 150 lines with a single clear responsibility.

## 12. Duplicate engine functionality inside plugins

**Finding (Medium, new): the "turn a raw `properties` map into
unconditional `add`-`Modifier`s" pattern is independently reimplemented
in five different content-parsing files.**

- **Files:**
  - `lib/src/plugins/item/item_content.dart:107-117`
    (`itemDefinitionFromContent`'s `modifiersFor`)
  - `lib/src/plugins/technique/technique_content.dart:149-159`
    (`techniqueDefinitionFromContent`'s `modifiersFor`)
  - `lib/src/plugins/martial_arts/martial_item_content.dart:106-119`
    (`martialItemDefinitionFromContent`'s `modifiersFor`)
  - `lib/src/plugins/elemental/elemental_item_content.dart:38-...`
    (equivalent `modifiersFor` construction)
  - `lib/src/plugins/physique/physique_content.dart:151-162`
    (`physiqueDefinitionFromContent`'s `modifiersFor`)
- **Problem:** All five build a closure of the shape `List<Modifier>
  modifiersFor(EntityId target) => [for (final entry in
  <rawEntries>.entries) Modifier(source: ModifierSource('<prefix>:
  ${definition.id}:${entry.key}:${target.value}'), target: target, stat:
  entry.key, operation: <op>, value: entry.value, ...)]` — the same
  "one entry, one unconditional (or tag-conditional) `Modifier`, sourced
  by a `<domain>:<id>:<key>:<entityValue>` string" algorithm, five times,
  with only the domain prefix and the presence/absence of a `condition`
  differing. This is exactly the shape category 12 asks about — not
  literally identical code, but the same *engine mechanism* (Modifier
  construction from a raw properties map) reinvented five times instead
  of shared, mirroring the prior audit's own `EvolutionResolver`/
  `RewardResolver` weighted-pick finding.
- **Severity:** Medium — no correctness risk today (each copy is
  independently tested and behaves identically for its own plugin), but a
  future change to the convention (e.g. adding `duration`/`priority` to
  every content-derived modifier, or changing the `ModifierSource` string
  format) would have to be applied in five places, and nothing would
  catch a silent divergence between them — the same risk profile the
  prior Medium finding was raised for.
- **Recommended fix:** Extract a single generic helper — e.g.
  `List<Modifier> modifiersFromProperties({required String domain,
  required String contentId, required Map<String, num> properties,
  required EntityId target, Query? condition}) -> List<Modifier>` — a
  natural home would be `lib/src/modifier/` (Core) alongside `Modifier`
  itself, since the algorithm has no domain-specific knowledge at all
  (every caller already supplies its own `domain` prefix and optional
  `condition`). Each of the five content-parsing functions would then
  call the shared helper instead of re-deriving the same loop. New,
  out-of-scope work per this audit's own instructions — recommended for a
  future approved pass.

**Finding (Low, new): `'fist'`/`'blade'` tag-matching-with-fallback logic
is duplicated between the two Build Interpretation interpreters.**

- **Files:**
  - `lib/src/plugins/build_interpretation/technique_action_interpreter.dart:28,71-76`
    (`_weaponStatTags` + `_damageStatFor`)
  - `lib/src/plugins/build_interpretation/item_action_interpreter.dart:31,60-65`
    (`_weaponStatTags` + `_statFor`)
- **Problem:** Both files independently declare the identical `static
  const _weaponStatTags = ['fist', 'blade'];` list and near-identical
  "return the first tag from this list the definition has, else fall back
  to a per-id stat string" logic. Both live in the *same* module
  (`lib/src/plugins/build_interpretation/`), so — unlike finding 12a,
  which spans five separately-owned plugins — there is no plugin-boundary
  reason for the duplication here at all.
- **Severity:** Low — a 2-line constant and a 5-line loop; low drift risk
  given both files are reviewed together in practice, but genuinely
  unnecessary given the shared module.
- **Recommended fix:** Move `_weaponStatTags` and the matching-with-
  fallback function into a small shared file in the same module (e.g.
  `lib/src/plugins/build_interpretation/weapon_stat_tags.dart`), called
  by both interpreters. Mechanical, low-risk, ~10-line change.

**Status: ✅ Fixed (2026-08-24, same day).** Both category-12 findings
fixed:

- New `lib/src/modifier/modifier_operation_parsing.dart`
  (`modifierOperationFromString`) replaces the triplicated `_operationFor`
  in `martial_item_content.dart`/`elemental_item_content.dart`/
  `physique_content.dart`.
- New `lib/src/modifier/modifiers_from_raw_list.dart`
  (`modifiersFromRawList`) replaces those same three files' identical
  index-keyed `modifiersFor` loop (the bigger of the two duplications,
  beyond just operation-parsing) — verified behavior-preserving: physique's
  content always supplies `'condition'`, so the shared helper's
  `containsKey`-guarded optional condition produces the exact same
  `HasTagQuery` physique's old unconditional-cast version did.
- New `lib/src/modifier/modifiers_from_properties.dart`
  (`modifiersFromProperties`) replaces `item_content.dart`'s and
  `technique_content.dart`'s identical properties-map-to-add-`Modifier`
  loop — the Medium finding as originally written.
- New `lib/src/plugins/build_interpretation/weapon_stat_tags.dart`
  (`WeaponStatTags.values`/`.matchOrFallback`) replaces the duplicated
  `_weaponStatTags` constant and matching loop in
  `technique_action_interpreter.dart`/`item_action_interpreter.dart` — the
  Low finding.

All four are pure, behavior-preserving extractions (same `Modifier`s/stat
strings produced for every existing input) — `dart analyze` clean, every
existing MartialArts/Elemental/Physique/Item/Technique/Build-Interpretation
test still passes unchanged.

## 13. Direct cross-plugin calls that should use events/interfaces

**Result: No violations found — two new cases explicitly considered and
cleared, following the same reasoning the prior audit applied to
`AutoCombatController`.**

- `TechniqueActionInterpreter`/`ItemActionInterpreter`
  (`lib/src/plugins/build_interpretation/`) call
  `techniqueDefinitionFromContent`/`itemDefinitionFromContent` and read
  `context.content.find(...)` directly — these are each plugin's
  documented *public* content-parsing API (the same functions
  `TechniquePlugin`/`ItemPlugin`'s own tests call), not a reach into
  private implementation, and Build Interpretation's entire purpose is to
  translate that content into `CombatAction`s — exactly analogous to how
  `AutoCombatController` legitimately calls `CombatSystem.executeAction`
  directly rather than through an event (the prior audit's own
  category-13 conclusion).
- `ScoredActionSelector`/`DefaultActionScorer`
  (`lib/src/plugins/auto_combat/`) read `context.modifiers`/
  `context.resources`/`action.conditions` directly — all public
  `PluginContext`-exposed Core services, not another plugin's private
  state. No plugin is contacted directly at all; scoring only reads
  generic Core services and the `CombatAction` interface.

## 14. Domain-specific concepts leaking into Core

**Result: No violations found.**

Same evidence as category 1. Every new opaque-reference convention this
session (`ItemRequirement.masterySubject`, `TechniqueDefinition.tier`
reusing the pre-existing `EvolutionTiers` constants, `CombatAction
.priority`) is treated as an uninterpreted string/number by every piece of
Core logic that touches it. `CombatAction.priority` (the one new field
added to a Combat-plugin type this session) is a plain `num`, read only by
`DefaultActionScorer` via addition — Combat itself (`combat_system.dart`)
never reads it.

## 15. Serialization depending on runtime implementation classes

**Result: No violations found.**

Every `toJson`/`fromJson` pair in the repository is unchanged from the
prior audit's enumeration (`Container`, `CombatStateComponent`/
`CombatantComponent`, `MartialLoadoutComponent`, `ContentRegistry`). None
of the five subsystems added this session (Item, Technique, Training,
Build Interpretation, AutoCombat scoring) implements any serialization at
all, so there is nothing new to violate this category — but the
save/load *coverage gap* the prior two audits already noted as "outside
what this category asks for" widens further: `ItemInstance`,
`TechniqueDefinition`-derived state (Discovery/Progression/Mastery
entries, already covered generically by their own trackers, not by any
new type), and every Training/Build-Interpretation/AutoCombat-scoring
type have no `toJson`/`fromJson` at all. Noted for completeness only, per
the same reasoning both prior audits used — a save/load coverage gap is
not a category-15 violation on its own.

---

## Additional observations (outside the 15 requested categories)

**A. The `PluginContext`/`RuleEngine` shared-instance footgun (prior
audit's Additional Observation B) now has two confirmed real incidents —
upgraded from informational to a recommendation.**

- **Files:** `lib/src/plugin/plugin_context.dart`, `lib/src/rule/
  rule_engine.dart`, `lib/src/rule/rule_context.dart` (unchanged since the
  prior audit — the risk is in how callers *use* these factories, not in
  the factories themselves).
- **Problem:** Both prior audits flagged that a `PluginContext` and a
  `RuleEngine` constructed with their own unsupplied defaults silently end
  up with *independent* `MasteryTracker`/`ProgressionEngine`/
  `DiscoveryTracker` instances unless a caller explicitly passes the same
  ones to both constructors, and judged this "no current failure, only a
  footgun." This session, building the Technique and Item plugins'
  earliest test bootstraps, that exact failure mode was hit twice in
  practice (a `Rule` registered via `RuleEngine.register` silently read
  mastery/discovery state through a *different* tracker than the one
  `PluginContext.mastery`/`.discovery` had just been written through,
  making a mastery-gated unlock rule appear not to fire) — caught only by
  the tests themselves failing, not by any static check.
- **Severity:** Low-Medium — still no violation in shipped engine code
  (every real bootstrap in `lib/` — the vertical slice runner,
  `build_interpretation_end_to_end_test.dart`, etc. — already follows the
  documented shared-instance pattern correctly), but the failure mode is
  no longer hypothetical: it has now cost real debugging time twice in
  this project's own history, and nothing prevents a third recurrence for
  the next plugin that combines `RuleEngine`-dispatched rules with direct
  `PluginContext.mastery`/`.progression`/`.discovery` writes.
- **Recommended fix (still not implemented — recommendation only):** the
  `CoreServices` bundle type both prior audits already proposed
  (constructed once, destructured into both `RuleEngine` and
  `PluginContext`, making mismatched defaults structurally impossible)
  would eliminate the footgun entirely rather than relying on every future
  bootstrap author remembering the documented pattern. Given it has now
  independently caused two incidents, this is worth prioritizing over the
  category-12 findings above if only one refactor is approved.

**Status: ✅ Fixed (2026-08-24, same day).** Implemented exactly the
recommended `CoreServices` bundle — `lib/src/rule/core_services.dart`
(placed under `lib/src/rule/`, not `lib/src/plugin/`, specifically to
avoid introducing a `rule -> plugin -> rule` cycle, since `PluginContext`
already depends on `RuleEngine`). Both `PluginContext` and `RuleEngine`
gained an additive, optional `shared: CoreServices?` parameter — an
explicit individual parameter (`mastery:`/`progression:`/etc.) still
always takes priority, so every existing caller that doesn't pass
`shared:` is unaffected. Migrated the 8 test bootstraps that previously
built the shared instances by hand (`item`/`technique` plugin and
lifecycle tests, `item`/`technique`/`build_interpretation`/`training`
integration tests) to `shared: CoreServices(...)`, each shrinking from ~20
lines of manual wiring to 1. Added `test/rule/core_services_test.dart`,
which demonstrates both halves directly: *with* `shared:`, a `Rule`
dispatched through `RuleEngine` correctly sees mastery written through
`PluginContext.mastery`; *without* it, the same setup reproduces the
historical divergence bug verbatim (kept as a deliberate, documented
contrast — `shared:` is opt-in, not a breaking change). `dart analyze`
clean; full suite 906 → 908 tests, all passing.

**B. `lib/src/reward/` importing `lib/src/tome/` — unchanged, still
informational, not a finding** (carried over from the prior audit's
Observation C: `RewardCandidate.ref` reusing `BuildComponentRef` directly;
still a Core-module-to-Core-module value-type dependency, still outside
`lib/src/plugins/`, no plugin-boundary rule implicated).

---

## Resolution status of prior audits' findings

All findings from both prior audits (`227bf69`'s pass and the same-day
"fix all" update) remain fixed and were re-verified during this pass:
`RuleContext` construction dedup, `effect.dart`/`condition.dart` god-file
split, the `EvolutionResolver`/`RewardResolver` weighted-pick dedup, and
the `'western'`/`'eastern'` tradition-tag constants. None regressed.

## This audit's own findings — resolution log

1. **Category 7** (training weight maps as hand-written Dart constants) —
   migrated into `technique_content.dart`/`item_content.dart`'s own
   `'training'` extra field, parsed into `TechniqueDefinition
   .trainingWeights`/`ItemDefinition.trainingWeights`.
2. **Category 12, Medium** (`modifiersFor`/`_operationFor` duplicated
   across 5 content-parsing files) — extracted to
   `lib/src/modifier/{modifier_operation_parsing,modifiers_from_raw_list,
   modifiers_from_properties}.dart` (Core), all five files migrated.
3. **Category 12, Low** (`_weaponStatTags` duplicated in Build
   Interpretation) — extracted to `lib/src/plugins/build_interpretation/
   weapon_stat_tags.dart`.
4. **Additional Observation A** (`PluginContext`/`RuleEngine` shared-
   instance footgun) — `CoreServices` (`lib/src/rule/core_services.dart`)
   added as an additive `shared:` parameter on both factories; 8 test
   bootstraps migrated to it; a dedicated test
   (`test/rule/core_services_test.dart`) proves the fix.

Not touched, per each finding's own text: category 11's carried-over
`CombatSystem` Low finding (no action recommended, both this and the
prior audit agree) and Additional Observation B (informational only).

Commit not made — per standing instructions, changes are staged in the
working tree for review.
