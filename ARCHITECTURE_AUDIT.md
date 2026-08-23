# Build Engine — Architecture Audit

**Date:** 2026-08-24
**Scope:** entire repository — Core (20 `lib/src/` service directories) and
six plugins (Combat, MartialArts, Elemental, Physique, AutoCombat; 124
`.dart` files, ~6,980 lines total).
**Commit audited:** `227bf69` (main, post-AutoCombat merge).
**This is a from-scratch audit**, not a diff against the prior one
(`7852ac7`) — every category was re-verified against the current code,
including everything added since: Character, Resource Engine, Progression
layer, Mastery system, Discovery system, Tome/Build system, Training
Framework, Evolution System, Reward/Loot system, and AutoCombat.
**Method:** full read of `CLAUDE.md`; a complete file inventory of `lib/`;
import-graph inspection of every Core directory and every plugin
directory; targeted greps for domain vocabulary in Core, `dart:math`/
`Random` usage outside `RngService`, mutable `static` state, hardcoded
`id ==` combination checks, direct cross-plugin private-path imports,
and duplicated algorithm logic; a file-size survey to catch god-class/
god-file growth since the prior audit; line-by-line reading of every
component-shaped file and every `toJson`/`fromJson` pair.
**No changes have been made.** Refactoring requires separate approval,
per the audit request.
**Baseline at time of audit:** `dart analyze` clean, 711 tests passing.

**Update (2026-08-24, same day):** approved via "fix all." The Medium
finding (§12), the new Low god-file finding (§11), and carried-over
Additional Observation A were all fixed — see each section below and the
Resolution Log for specifics. Additional Observations B and C were left
alone, as both were explicitly framed as "not recommended now"/
"informational, not a finding" rather than actionable items. `dart
analyze` clean and all 711 tests still passing after every fix, verified
individually per change.

## Summary

Of the 15 categories requested, **13 have no violations**. **2 have real
findings.** The Medium finding (§12) and the actionable half of the Low
god-class finding (§11's file-size growth) are **now fixed** — see the
2026-08-24 update above and each section's Status note. `CombatSystem`
(the other half of §11) remains open by design: both this and the prior
audit judged it Low severity with no action recommended.

| # | Category | Result |
|---|---|---|
| 1 | Core importing game-specific modules | ✅ No violations |
| 2 | Combat importing MartialArts | ✅ No violations |
| 3 | Combat importing Magic | ✅ N/A — no Magic plugin exists |
| 4 | Plugins accessing private implementation of other plugins | ✅ No violations |
| 5 | Circular dependencies | ✅ No violations |
| 6 | Hardcoded item combinations | ✅ No violations |
| 7 | Hardcoded content | ✅ No violations (fixed in the prior audit, confirmed still fixed) |
| 8 | Global mutable state | ✅ No violations |
| 9 | Gameplay randomness bypassing RNGService | ✅ No violations |
| 10 | Components containing excessive gameplay logic | ✅ No violations |
| 11 | God classes | ⚠️ 2 findings (both Low) — the file-size one → ✅ Fixed; `CombatSystem` stays open, no action recommended |
| 12 | Duplicate engine functionality inside plugins | ⚠️ 1 finding (Medium) → ✅ Fixed |
| 13 | Direct cross-plugin calls that should use events/interfaces | ✅ No violations |
| 14 | Domain-specific concepts leaking into Core | ✅ No violations |
| 15 | Serialization depending on runtime implementation classes | ✅ No violations |

Three items outside the 15 requested categories are recorded under
**Additional Observations**: one carried-over, still-unaddressed magic-
string duplication between MartialArts and Physique; one new, low-risk
correctness footgun in how five Core services now share defaulted
instances across `PluginContext`/`RuleEngine`; and one informational note
about a new Core-module-to-Core-module value-type reuse.

---

## 1. Core importing game-specific modules

**Result: No violations found.**

Every file under the 20 current Core directories (`lib/src/{character,
component,components,content,discovery,entity,event,evolution,mastery,
modifier,plugin,progression,query,resource,reward,rng,rule,spatial,tome,
training}/`) was grepped for `plugins/` imports — zero hits. A second
grep across the same directories for domain vocabulary
(`sword|spell|fireball|qi|boxing|shaolin|martial|cultivat|potion|dragon|
mana|physique|sturdy|punch|jab|elemental|iron_sword|brass_knuckles`)
returns only doc-comment prose — illustrative examples (`"technique:jab"`,
`"item:iron_sword"`) and explicit anti-pattern citations (`no
SwordMastery, no TechniqueMastery`), never executable code. This holds
across every subsystem added this session, not just the original five
Core directories the prior audit covered.

## 2. Combat importing MartialArts

**Result: No violations found.**

`lib/src/plugins/combat/` imports only `package:build_engine/
build_engine.dart` and its own sibling files — confirmed by grepping the
directory for every plugin barrel filename and for `plugins/`-shaped
relative imports; zero hits. The one plugin that imports Combat now has
two members instead of one: `MartialArtsPlugin.dependencies => const
['combat']` (unchanged from the prior audit) and the new
`lib/src/plugins/auto_combat/` — both import
`package:build_engine/combat_plugin.dart` exclusively, never a private
`lib/src/plugins/combat/...` path.

## 3. Combat importing Magic

**Result: N/A — no Magic plugin exists in this repository.**

## 4. Plugins accessing private implementation of other plugins

**Result: No violations found.**

Grepped every plugin directory (`combat`, `martial_arts`, `elemental`,
`physique`, `auto_combat`) for a direct `lib/src/plugins/<other>/` import
path or a `package:build_engine/src/plugins/...` import — zero hits
anywhere. Every cross-plugin reference goes through a public barrel
(`combat_plugin.dart`), confirmed by listing each plugin directory's
barrel imports directly:

- `lib/src/plugins/martial_arts/*.dart` → `combat_plugin.dart` only.
- `lib/src/plugins/auto_combat/*.dart` → `combat_plugin.dart` only.
- `lib/src/plugins/{combat,elemental,physique}/` → no plugin barrel
  imports at all.

## 5. Circular dependencies

**Result: No violations found.**

The import graph is a strict DAG: `Core <- Combat <- {MartialArts,
AutoCombat}`, `Core <- Elemental`, `Core <- Physique`. No file under
`lib/src/` (outside `lib/src/plugins/`) imports anything under
`lib/src/plugins/`, so a cycle back into Core is structurally impossible.
`PluginManager.resolveLoadOrder()` additionally detects and throws
`CyclicPluginDependencyException` on any *declared* plugin dependency
cycle at runtime. `test/integration/architecture_dependency_test.dart`
now also enumerates Core directories dynamically (group H) rather than
hardcoding them, so every subsystem added this session (Resource,
Mastery, Progression, Discovery, Tome, Training, Evolution, Reward) was
automatically covered by the "Core never imports a plugin" check the
moment its directory was created — verified by re-running the suite and
confirming each new directory appears in the test output.

## 6. Hardcoded item combinations

**Result: No violations found.**

Grepped the whole `lib/src/plugins/` tree for an `id ==` /
combination-shaped conditional — zero hits (down from the prior audit's
same zero-hit result). Every cross-entity interaction remains gated by a
single generic tag/status/mastery-level check
(`HasTagQuery`/`StatusActive`/`MasteryAtLeast`/`ProgressionTierAbove`),
never a hardcoded pairing of two specific named items or techniques.

## 7. Hardcoded content

**Result: No violations found — confirmed still fixed.**

The prior audit's Finding #7 (MartialArts' and Elemental's item/trinket
definitions were hand-written Dart `const` literals rather than
`ContentRegistry`-loaded data) was marked fixed as of that same audit
pass. Re-verified directly: `lib/src/plugins/martial_arts/
martial_item.dart` and `lib/src/plugins/elemental/elemental_item.dart`
now contain only the runtime `MartialItemDefinition`/
`ElementalItemDefinition` *shape* and `equipItem`/`equipElementalItem`
helpers — every actual item instance lives in `martial_item_content.dart`
/`elemental_item_content.dart`, loaded through `ContentRegistry` in each
plugin's `initialize`. No new plugin added this session introduces any
hand-written content instance either — Evolution/Reward/Training all
model *content-shaped data* (`EvolutionDefinition`, `RewardDefinition`,
`TrainingProfile`, ...) as types a caller instantiates, never as
hardcoded singletons inside the engine itself.

## 8. Global mutable state

**Result: No violations found.**

Grepped for `static` members across all of `lib/`; every hit is a pure
static *function* (`ElementalItemDefinition`/`MartialItemDefinition`'s
`_noModifiers`, `ElementalEffects._statusFor`, `ContentField`'s helpers in
`json_helpers.dart`, `Container._slotFromJson`) or a `static const`
identifier constant. No mutable `static` field, no singleton pattern, no
top-level mutable variable anywhere in the repository — confirmed across
every subsystem added this session too. Every stateful service
(`MasteryTracker`, `ProgressionEngine`, `DiscoveryTracker`, `ResourcePool`,
`TomeService`, `CharacterService`, ...) is constructed and held per-
`PluginContext`/per-caller, never reached through a global.

## 9. Gameplay randomness bypassing RNGService

**Result: No violations found.**

Grepped all of `lib/` for `dart:math`/`Random(`; the only real
construction sites remain `rng_service.dart:1` (`Random(seed)`) and
`modifier_resolver.dart:1`'s `math.min`/`math.max` (deterministic math,
not randomness) — unchanged from the prior audit. The two new resolvers
added this session that genuinely need randomness —
`EvolutionResolver.resolve` (weighted branch selection) and
`RewardResolver.resolve` (weighted loot draws) — both take an
`RngService`/`RuleContext.rng` as an explicit parameter and call only
`.nextDouble()` on it; neither imports `dart:math` at all. Both ship
their own explicit determinism tests (same seed + same inputs → same
outcome).

## 10. Components containing excessive gameplay logic

**Result: No violations found.**

Every component-shaped file in the repository was read in full,
including everything added this session: `CharacterComponent` (empty
marker), `MasteryComponent`/`DiscoveryComponent`/`ResourceComponent` (all
plain `Map<String, V>` holders), `DiscoveryState` (a bare enum),
`TomeInstance` (two fields: `definitionId`, `container` — no methods of
its own beyond field access; the logic those fields' *values* are capable
of lives in the separately-audited `Container` class and in
`TomeService`, not in `TomeInstance` itself), `BuildComponentRef`/
`TomePlacement`/`ResourceState`/`ProgressionState`/`MasteryRecord` (all
pure value classes, no behavior). None contain a conditional, a loop over
other entities, or a call into `EventBus`/`RuleEngine`/any service.

## 11. God classes

**Finding (Low, carried over, unchanged): `CombatSystem`.**

- **File:** `lib/src/plugins/combat/combat_system.dart` (257 lines)
- **Problem:** unchanged from the prior audit — one class owns battle
  creation, action execution, turn advancement, and battle-end detection.
  Confirmed byte-for-byte unaffected by this session's work: AutoCombat
  was built specifically *not* to touch this file (see category 13 and
  the AutoCombat section of `ARCHITECTURE.md`), so this finding is purely
  a re-confirmation, not a regression.
- **Severity:** Low — same reasoning as before (narrow public surface,
  heavily commented, every branch tested). Flagging only because it
  remains one of the largest single classes in the engine.
- **Recommended fix:** Unchanged: no urgent action; consider extracting
  battle-end detection into its own collaborator if this class grows
  further.

**Finding (Low, new): `lib/src/rule/effect.dart` and `lib/src/rule/
condition.dart` are becoming general dumping grounds for every pass's new
verbs.**

- **Files:**
  - `lib/src/rule/effect.dart` — 365 lines, 18 classes (`Damage` through
    `TransformEntity`)
  - `lib/src/rule/condition.dart` — 249 lines, 13 classes (`HasTag`
    through `RandomChance`)
- **Problem:** Not a god *class* in the traditional sense — every
  individual class in both files is small (10–25 lines) and single-
  purpose, exactly matching the "implement directly, no registry"
  convention these files were designed around. But the *files* keep
  growing: six of `effect.dart`'s 18 classes and five of `condition.dart`'s
  13 were added across this session's five resource-shaped passes
  (Resource Engine, Progression, Mastery, Discovery). `effect.dart` at
  365 lines is now larger than `content_registry.dart` was (354 lines)
  when the prior audit flagged *that* file as a Medium god-class finding
  and it was subsequently split into `content_registry.dart` +
  `built_in_content_factories.dart`.
- **Severity:** Low — nothing here is hard to understand or test (every
  class ships its own isolated tests), and Dart tooling handles
  365-line files without difficulty. Flagging because the growth pattern
  is identical to the one the prior audit already treated as
  Medium-worthy once, and every future pass that adds one more generic
  verb will make this slightly worse.
- **Recommended fix:** No urgent action. If either file keeps growing,
  the same split `content_registry.dart` got applies cleanly here too —
  e.g. `effect.dart` could become `effect.dart` (the `Effect` interface +
  Core's original five: `Damage`/`Heal`/`ModifyStat`/`ApplyStatus`/
  `RemoveStatus`/tag effects) plus a second file for the
  resource/progression/mastery/discovery verb families added this
  session. This is a mechanical, low-risk reorganization (move classes,
  fix imports) whenever it's judged worth doing — not needed now.

**Status: ✅ Fixed (2026-08-24, same day).** `effect.dart` (365 → 233
lines) now holds only the `Effect` interface plus `Damage`/`Heal`/
`ModifyStat`/`ModifyResource`/`ApplyStatus`/`RemoveStatus`/`AddTag`/
`RemoveTag`/`CreateEntity`/`DestroyEntity`/`TransformEntity`; the seven
resource/progression/mastery/discovery verbs
(`ConsumeResource`/`RestoreResource`/`GrantProgressionExperience`/
`UnlockProgressionTier`/`IncreaseMastery`/`DiscoverSubject`/
`UnlockSubject`) moved verbatim to new `lib/src/rule/system_effects.dart`
(144 lines). `condition.dart` (249 → 163 lines) similarly kept its
original eight checks; the five newer ones
(`ProgressionTierAbove`/`ProgressionTierBelow`/`MasteryAtLeast`/
`IsDiscovered`/`IsUnlocked`) moved to new `lib/src/rule/
system_conditions.dart` (103 lines). The private `_scopeOf` helper
`IsDiscovered`/`IsUnlocked` needed was made public (`scopeOf`, still in
`condition.dart`) so both new conditions could reach it without
duplicating the one-liner. Zero behavior changed — every moved class is
byte-for-byte identical to its prior version; `dart analyze` clean, all
711 tests passing unchanged both before and after.

## 12. Duplicate engine functionality inside plugins

**Finding (Medium, new): `EvolutionResolver` and `RewardResolver`
independently reimplement the same weighted-cumulative-sum random-pick
algorithm.**

- **Files:**
  - `lib/src/evolution/evolution_resolver.dart:65-84` (the `roll`/
    `cumulative` loop inside `resolve`)
  - `lib/src/reward/reward_resolver.dart:39-51` (`_weightedPick`)
- **Problem:** Both methods do exactly the same thing — draw
  `rng.nextDouble() * totalWeight`, walk a candidate list accumulating
  weight until the roll is exceeded, fall back to the last candidate on
  the floating-point edge case — implemented as two separate, independent
  code blocks rather than one shared helper. `reward_resolver.dart`'s own
  doc comment even names the duplication explicitly ("the same weighted
  cumulative-sum pick `EvolutionResolver` already uses") without
  extracting it. This is exactly the shape of issue category 12 asks
  about, just found in Core rather than literally "inside a plugin" —
  the same *engine mechanism*, reinvented a second time instead of
  shared.
- **Severity:** Medium — no correctness risk today (both copies are
  independently tested and currently behave identically), but a future
  change to the algorithm (e.g. a different tie-breaking rule, or
  switching to reservoir sampling) would have to remember to update both
  call sites, and nothing would catch a silent divergence between them.
- **Recommended fix:** Extract a single `weightedPick<T>(List<T> items,
  num Function(T) weightOf, RngService rng) -> T?` (or similar) helper —
  a natural home would be alongside `RngService` itself (e.g.
  `lib/src/rng/weighted_pick.dart`), since both callers already inject an
  `RngService`/`RuleContext.rng` and nothing about the algorithm is
  specific to either Evolution or Reward's domain vocabulary. Both
  resolvers would then call the shared helper with their own
  weight-computation closures (`EvolutionResolver`'s Modifier-based
  weight, `RewardResolver`'s plain static weight), preserving each
  system's distinct weighting logic while sharing the actual random-pick
  mechanism. This is new, out-of-scope work per this audit's own
  instructions — recommended for a future approved pass, not implemented
  here.

**Status: ✅ Fixed (2026-08-24, same day).** Extracted exactly the
recommended `weightedPick<T>(List<T> items, num Function(T) weightOf,
RngService rng) -> T?` into new `lib/src/rng/weighted_pick.dart`.
`EvolutionResolver.resolve` now calls it with a closure wrapping its
existing Modifier-based `_weightOf`; `RewardResolver.resolve` calls it
with a closure reading `RewardCandidate.weight` directly — each keeps its
own distinct weighting logic, only the actual cumulative-sum draw is
shared. Confirmed behavior-preserving, not just non-breaking: the
Evolution weighting test (a 50-fixed-seed statistical sweep whose exact
pass/fail depends on the precise sequence of `rng.nextDouble()` draws)
passed unchanged after the refactor, proving the shared helper draws
identically to each resolver's prior standalone implementation. `dart
analyze` clean, all 711 tests passing.

## 13. Direct cross-plugin calls that should use events/interfaces

**Result: No violations found — one case explicitly considered and
cleared.**

The established convention (a *content* plugin like MartialArts reacts to
Combat's events rather than holding a `CombatSystem`/`CombatPlugin`
reference) still holds: grepping `lib/src/plugins/martial_arts/` for
`CombatSystem`/`CombatPlugin` by name returns only doc-comment prose.

`AutoCombatController` is the one new case worth naming explicitly: it
*does* hold a `CombatSystem` field and calls `combatSystem.executeAction`
directly (`lib/src/plugins/auto_combat/auto_combat_controller.dart`).
This is not the same situation category 13 warns about — AutoCombat isn't
a content plugin reacting to combat outcomes that could instead subscribe
to an event; its entire purpose *is* to drive Combat via the public API
`CombatSystem` already exposes for exactly this (a game loop or UI layer
would call `executeAction` the same way). Calling a plugin's own
documented public entry point is the sanctioned integration path, not an
instance of "should have used an event instead."

## 14. Domain-specific concepts leaking into Core

**Result: No violations found.**

Same evidence as category 1: zero domain vocabulary appears anywhere
under the 20 Core directories outside doc-comment examples/citations.
Every new opaque-reference convention introduced this session
(`BuildComponentRef.referenceType`/`.contentId`, `MasteryTracker`/
`ProgressionEngine`/`DiscoveryTracker`'s `subject` strings,
`TrainingProfile.dimensions` keys, `EvolutionCandidate.tags`) is treated
as an uninterpreted string by every piece of Core logic that touches it —
confirmed by reading each resolver/tracker's implementation directly
(none of them branch on a specific string value; they only do map
lookups, membership checks, and generic threshold/weight arithmetic).

## 15. Serialization depending on runtime implementation classes

**Result: No violations found.**

Every `toJson`/`fromJson` pair in the repository was re-enumerated: the
set is *unchanged* from the prior audit —
`Container.toJson`/`.fromJson`, `CombatStateComponent`/
`CombatantComponent`'s pairs, `MartialLoadoutComponent`'s pair, and
`ContentRegistry.toJson`. None of the ten subsystems added this session
(Character, Resource, Progression, Mastery, Discovery, Tome, Training,
Evolution, Reward, AutoCombat) implements any serialization at all, so
there is nothing new here to violate this category — but it does widen
the *coverage gap* the prior audit already noted as "outside what this
category asks for": `CharacterComponent`, `ResourceComponent`,
`MasteryComponent`, `DiscoveryComponent`, `TomeInstance`, and every
resolver's result type (`EvolutionResult`, `RewardResult`,
`TrainingResult`) all have no `toJson`/`fromJson` at all. Noted for
completeness only, per the same reasoning the prior audit used — a
save/load coverage gap is not a category-15 violation on its own.

---

## Additional observations (outside the 15 requested categories)

**A. `'western'`/`'eastern'` tradition-tag literals — still unaddressed,
carried over unchanged from the prior audit's Observation C.**

- **Files:** `lib/src/plugins/martial_arts/martial_styles.dart:60-61`,
  `lib/src/plugins/physique/physique_content.dart:33,39,53,59`.
- **Status: ✅ Fixed (2026-08-24, same day).** The prior audit recommended
  each plugin name these two strings locally (a small
  `MartialTraditions`-style constants class per plugin, not a shared
  import). Added `MartialTraditions` (`lib/src/plugins/martial_arts/
  martial_vocabulary.dart`) and `PhysiqueTraditions` (`lib/src/plugins/
  physique/physique_types.dart`) — two independent classes with matching
  values, exactly as recommended, preserving each plugin's zero-import
  relationship to the other. Every raw `'western'`/`'eastern'` literal in
  both plugins' *code* (`martial_styles.dart`'s `_traditionTagFor`,
  `martial_item_content.dart` and `martial_technique_content.dart`'s tag
  lists — 17 occurrences total, not just the 2 the original finding named,
  since those two files didn't exist as separate content files at the
  time of the original observation — and `physique_content.dart`'s 8
  `'condition'` values) now references the appropriate constant instead.
  Doc-comment prose mentioning the literal values was left as prose.
  `dart analyze` clean; `test/integration/physique_synergy_test.dart` and
  every MartialArts test re-run individually to confirm the tag *values*
  produced at runtime are unchanged — all passing.

**B. Five Core services now share the "construct once, pass the same
instance everywhere" burden — a real but well-documented correctness
footgun.**

- **Files:** `lib/src/plugin/plugin_context.dart:20-63`, `lib/src/rule/
  rule_engine.dart:18-42`, `lib/src/rule/rule_context.dart` (the
  equivalent factory).
- **Problem:** `PluginContext`, `RuleEngine`, and `RuleContext` were each
  converted to a factory constructor across this session's passes so that
  a defaulted `MasteryTracker` can be shared with `ProgressionEngine`'s
  own default (see `ARCHITECTURE.md`'s Progression section). This works
  correctly *within* one factory call, but nothing enforces that a real
  bootstrap's separately-constructed `RuleEngine` and `PluginContext`
  share the *same* `ResourcePool`/`MasteryTracker`/`ProgressionEngine`/
  `DiscoveryTracker` instances — if a caller omits any of the five optional
  parameters from one of the two constructors while supplying it to the
  other, the two objects silently end up with independent stores that
  never see each other's registered definitions or written state. This
  is explicitly documented (`ARCHITECTURE.md`'s bootstrap example and its
  surrounding prose), and every test in the repository either constructs
  a single shared context correctly or doesn't need cross-context
  sharing at all — so there is no current failure, only a footgun for a
  future bootstrap author who doesn't follow the documented pattern.
- **Severity:** Low — no current violation, purely a design risk. Not
  raised as one of the 15 categories' findings because it isn't global
  mutable state, a god class, or any of the other listed shapes; it's a
  constructor-ergonomics risk unique to this engine's "many optional,
  defaulted services" pattern.
- **Possible future mitigation (not recommended now, no approval
  requested):** a single `CoreServices` bundle type constructed once and
  destructured into both `RuleEngine`/`PluginContext`, removing the
  possibility of mismatched defaults entirely — genuine design work, not
  a mechanical fix, and out of scope for this audit.

**C. `lib/src/reward/` importing `lib/src/tome/` (informational, not a
finding).**

- `RewardCandidate.ref` reuses `BuildComponentRef` from the Tome/Build
  system directly (`lib/src/reward/reward_candidate.dart:1`) rather than
  duplicating an equivalent type. This is a Core-module-to-Core-module
  value-type dependency, the same *kind* of coupling `ProgressionEngine`
  already has on `MasteryTracker` (approved earlier this session) — noted
  here only so a future reader doesn't mistake it for an unreviewed
  accident. Both directions remain outside `lib/src/plugins/`, so no
  plugin-boundary rule is implicated.

---

## Resolution Log (from the prior audits — preserved for history)

Everything below was already fixed before this audit began, and this
audit independently re-verified each still holds (see the relevant
category sections above for the re-verification evidence).

1. **Finding #12** (dedupe `RuleContext` construction) —
   `PluginContext.ruleContextFor` added. Confirmed still the only
   construction path across all five plugins, including the new
   `auto_combat`.
2. **Finding #11, `ContentRegistry` half** (extract built-in vocabulary)
   — moved to `lib/src/content/built_in_content_factories.dart`;
   `ContentRegistry` at 293 lines today. (See category 11's *new*
   finding above — `effect.dart`/`condition.dart` are now approaching
   the same size this fix was triggered by.)
3. **Observation A** (missing `EntityDestroyed` cleanup) — `CombatPlugin`
   and `MartialArtsPlugin` both adopted `PluginSdk`; every plugin built
   since (`PhysiquePlugin`, and this session's Core-only subsystems that
   need it) followed the same convention from day one.
4. **Finding #7** (MartialArts techniques predated `ContentRegistry`) —
   confirmed fixed and, per category 7 above, joined this audit by
   Elemental's/MartialArts' item content too.
5. **Observation B** (magic strings) — `MartialResources`/
   `MartialStances`/`ElementalResources`/`ElementalStatuses` constant
   classes added. Did not cover `'western'`/`'eastern'` at the time —
   fixed in this same audit pass, see item 8 below.
6. **This audit's Finding §11** (`effect.dart`/`condition.dart` god-file
   growth) — split into `effect.dart`/`system_effects.dart` and
   `condition.dart`/`system_conditions.dart`. Commit pending (not yet
   committed as of this write-up — see conversation for status).
7. **This audit's Finding §12** (duplicate weighted-pick algorithm) —
   extracted to `lib/src/rng/weighted_pick.dart`, both resolvers
   refactored to call it.
8. **This audit's Additional Observation A** (`'western'`/`'eastern'`
   literals, itself a carry-over of the prior audit's Observation C) —
   `MartialTraditions`/`PhysiqueTraditions` constant classes added.

Every commit reviewed in this audit kept `dart analyze` clean and the
full test suite green. As of the fixes above: `dart analyze` clean, 711
tests passing, still at commit `227bf69` (fixes not yet committed).
