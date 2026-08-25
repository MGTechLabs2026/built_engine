# Build Engine — Architecture Audit

**Date:** 2026-08-25
**Commit audited:** `042aa7e` (main) — 185 `.dart` files under `lib/`,
11,602 lines. Covers everything present since the prior audit (`7d271a6`)
plus the **Item Combine** feature (`lib/src/combine/`, the Item plugin's
class/grade/scaling data model, `BuildComponentRef.instanceEntityId`,
`combineItems`, 24 new grade-chain item definitions) and the **game**
composition layer (`lib/src/plugins/game/`, `runGame`/`RunResult`/
`DecisionLog`/etc.) — the latter was never covered by any prior audit at
all despite being ~1,780 lines across 11 files, the single largest
untouched surface this pass found.
**This is a from-scratch audit**, not a diff — every category was
re-verified against the current code, not assumed carried-forward.
**Method:** full read of `CLAUDE.md`; full read of the prior audit as
context (to avoid re-flagging already-fixed findings); a file inventory
and line-count survey of `lib/`; per-directory import-graph extraction
(both Core-dir-level for category 1, and plugin-barrel-level for
categories 2-5/13) to check for plugin knowledge leaking into Core and to
verify the dependency DAG; targeted greps for `dart:math`/`Random(`
outside `rng_service.dart`, mutable `static`/top-level state,
`plugins/`-path imports inside Core directories, cross-plugin
`package:build_engine/src/plugins/` private-path imports, `id ==`-shaped
combination checks, and `toJson`/`fromJson`/serialization code; a full
read of every file in `lib/src/components/`, `lib/src/combine/`, and
`lib/src/plugins/game/`.
**No changes have been made.** Per this audit's own instructions, this is
a report only — refactoring requires separate approval.
**Baseline at time of audit:** `dart analyze` clean, 1,105 tests passing.

## Fix pass (2026-08-25, same day) — all 6 findings + the addendum addressed

Per the user's "fix all," every finding below (and Additional Observation
A above) was fixed immediately after this audit, verified with
`dart analyze lib test` (clean) and `dart test` (1,105 tests passing
throughout — the count is unchanged since this pass only moved/renamed
code, added zero net new tests). Kept as a fixed record of what each
finding said and how it was resolved, rather than deleted, matching this
file's own convention for prior-audit findings above.

- **Category 7 — `RunEnemies`'s 5 enemies were hand-written `const`
  objects.** Fixed: moved into `lib/src/plugins/game/enemy_content.dart`
  as `enemyContentDefinitions` (`ContentRegistry`-loaded, mirroring
  `itemContentDefinitions`), with `enemyDefinitionFromContent`/
  `enemyDefinition` parsers. `RunEnemies` now holds plain id strings, not
  `Enemy` objects. Loaded via `context.content.loadAll(enemyContentDefinitions)`
  directly in `runGame` (no dedicated "Enemy plugin" — enemies exist only
  for this composition layer). `game_run.dart`'s three enemy-selection
  sites and `test/game/game_run_test.dart`'s `scaledEnemy` test updated
  accordingly.
- **Category 7 — `run_content.dart`'s `stylesFor` duplicated MartialArts'
  own tradition↔style mapping, inverted.** Fixed: added a public
  `stylesForTradition(String tradition)` to
  `lib/src/plugins/martial_arts/martial_styles.dart` (the natural,
  non-private counterpart to the existing `_traditionTagFor`), and
  deleted `run_content.dart`'s `stylesFor` entirely — `game_run.dart`
  now calls `stylesForTradition` directly. One source of truth.
- **Category 7 (Minor) — `RunStartingKit`/reward-pool id lists.** No
  action taken. Re-confirmed the audit's own conclusion: for a single
  fixed run definition, a plain Dart list of real, already-content-loaded
  ids is a defensible, low-risk choice; migrating it to its own content
  type would be premature abstraction (`CLAUDE.md`'s YAGNI guidance)
  with no concrete need driving it yet.
- **Category 11 — `runGame` was a 627-line, 19-closure god-function.**
  Fixed: extracted into four small, independently-constructable classes
  — `TomeManager` (placement/upgrade-spend, `tome_manager.dart`),
  `RewardStage` (the reward pool, `reward_stage.dart`), `TrainingStage`
  (training resolution, `training_stage.dart`), `CombatStage` (fights,
  `combat_stage.dart`) — each taking its dependencies explicitly via
  constructor rather than closing over `runGame`'s shared mutable scope.
  `runGame` is now the composition root that wires the four together and
  drives the cycle loop, calling `rng`/`recordingPolicy` in the exact
  same order as before, so a given seed still reproduces the exact same
  run — verified via `test/game/game_run_test.dart`'s two
  `'deterministic given seed + decisions'` tests and
  `test/game/decision_log_replay_test.dart`'s full replay suite, all
  passing unchanged.
- **Category 11 (Minor) — `item_lifecycle.dart` covered two
  responsibilities in one file.** Fixed: `combineItems`/
  `_reflectCombineInTome`/`CombineNotAvailableException` moved to a new
  sibling `lib/src/plugins/item/item_combine.dart`, mirroring
  `lib/src/combine/`'s own one-concern-per-file split.
  `test/plugins/item/item_lifecycle_test.dart`'s `combineItems` test
  group moved to a new sibling `test/plugins/item/item_combine_test.dart`
  to match.
- **Category 14 — `lib/src/combine/`'s public API still carried
  Item-flavored vocabulary.** Fixed: renamed `CombineOutcome.classUpgrade`
  → `.tierUpgrade`, `.gradeUpgrade` → `.branchUpgrade`;
  `CombineResolver.resolve`'s `atMaxTierForGrade`/`gradeContext`/
  `gradeEvolution`/`gradeProfile` → `atMaxTierForBranch`/`branchContext`/
  `branchDefinition`/`branchProfile`; `CombineResult.chosenGradeTargetId`
  → `chosenBranchTargetId`. Every call site updated (`item_combine.dart`,
  `item_events.dart`'s doc comments, `test/combine/combine_resolver_test.dart`,
  `test/plugins/item/item_combine_test.dart`,
  `test/integration/item_combine_end_to_end_test.dart`). Deliberately
  did NOT rename `ItemDefinition.gradeEvolutionCandidates`/
  `.toGradeEvolutionDefinition()`/`.classScalingPercent` — those are the
  Item plugin's own legitimate domain vocabulary, not Core's; only
  `lib/src/combine/`'s own public API was in scope.
- **Addendum A — `game_run.dart` hardcoded `'upgrade_points'` as a raw
  string in 4 places.** Fixed: all 4 replaced with
  `ItemResources.upgradePoints`; `TomeManager`/`RewardStage` (which
  inherited this code during the god-function extraction) also use the
  constant, not the literal.

---

## Previously-resolved findings (not re-flagged)

Everything the prior audit (`7d271a6`, same-day "fix all" update) found
was fixed and re-verified as still-fixed during this pass:

- Category 7 — technique/item training-weight maps migrated into
  `technique_content.dart`/`item_content.dart`'s own `'training'` field.
  Confirmed unchanged and still content-driven; this session's own
  `item_content.dart` additions follow the exact same pattern.
- Category 12 (Medium) — the five-times-duplicated `modifiersFor`
  properties→Modifier loop, extracted to
  `lib/src/modifier/{modifier_operation_parsing,modifiers_from_raw_list,
  modifiers_from_properties}.dart`. Confirmed still shared; this
  session's Item Combine work reuses `modifiersFromProperties` rather
  than reinventing it.
- Category 12 (Low) — `_weaponStatTags` duplication in Build
  Interpretation, extracted to `weapon_stat_tags.dart`. Confirmed still
  shared; `game_run.dart` itself also calls `WeaponStatTags.matchOrFallback`
  rather than re-deriving the mapping (see category 12 below for the one
  place this pass found it *wasn't* reused).
- Additional Observation A — the `PluginContext`/`RuleEngine`
  shared-instance footgun, fixed via `CoreServices`. Confirmed every new
  bootstrap this session (all six Item Combine SDD tasks' test files,
  `game_run.dart`'s own `runGame`) correctly passes `shared: CoreServices(...)`.
- Category 11's `CombatSystem` Low finding and Additional Observation B
  (`reward/` importing `tome/`) — both unchanged, still exactly as
  before, no new action triggered.

---

## 1. Core importing game-specific modules

**Result: No violations found.**

Every one of the 19 current Core directories
(`lib/src/{character,component,components,content,discovery,entity,event,
evolution,mastery,modifier,plugin,progression,query,resource,reward,rng,
rule,spatial,tome,training,combine}/`) was grepped for any `plugins/`
path reference — zero hits, including the newest addition,
`lib/src/combine/` (the Item Combine feature's Core module). Its own
prose was independently re-checked word-by-word: the only vocabulary
hits are the generic English word "item" in phrases like "the items
being combined" (describing an abstract Combine input, not a plugin
type) and a doc-comment path reference to the design spec file — neither
is a code dependency. This is notable because `lib/src/combine/` shipped
with exactly this defect early in its own development (doc comments
naming `ItemInstance`/`combineItems`/"the Item plugin") and was
explicitly fixed during code review before merge — re-verified here as
still fixed, not regressed.

## 2. Combat importing MartialArts

**Result: No violations found.**

`lib/src/plugins/combat/` imports only `package:build_engine/build_engine.dart`
and its own sibling files. Grepped for `martial_arts`/`MartialArts` — zero
hits.

## 3. Combat importing Magic

**Result: N/A — no Magic plugin exists in this repository.** (Elemental
is this repo's closest analog; see category 2's sibling check — Combat
does not import it either.)

## 4. Plugins accessing private implementation of other plugins

**Result: No violations found.**

Grepped every plugin directory for a `package:build_engine/src/plugins/<other>/`
import path — zero hits anywhere, including `lib/src/plugins/game/`
(the newest and widest-composing plugin-adjacent layer). Every
cross-plugin reference goes through a public barrel:

- `lib/src/plugins/game/*.dart` → `auto_combat_plugin.dart`,
  `build_engine.dart`, `build_interpretation.dart`, `combat_plugin.dart`,
  `item_plugin.dart`, `martial_arts_plugin.dart`, `physique_plugin.dart`,
  `technique_plugin.dart` — all public barrels.
- `lib/src/plugins/build_interpretation/*.dart` → `item_plugin.dart`,
  `technique_plugin.dart` — barrels only.
- `lib/src/plugins/martial_arts/martial_conditions.dart` → `combat_plugin.dart`
  — barrel only.
- `lib/src/plugins/{combat,elemental,physique,item,technique,combine}/` —
  no plugin-barrel imports at all.

(Test files under `test/plugins/<name>/` importing that *same* plugin's
own `src/` files — e.g. `test/plugins/item/item_lifecycle_test.dart`
importing `package:build_engine/src/plugins/item/item_lifecycle.dart` —
are a plugin's own tests reaching its own implementation, not a
cross-plugin violation, and were excluded from this finding.)

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
Core + Item + Technique <- BuildInterpretation
Core + Combat + Item + MartialArts + Physique + Technique + AutoCombat
     + BuildInterpretation <- Game
```

A strict DAG. `Game` (`lib/src/plugins/game/`, `lib/game.dart`) is the
new widest node — it composes nearly everything — but nothing imports it
back (confirmed: no file under `lib/` outside `lib/src/plugins/game/`
and `lib/game.dart` itself references `plugins/game/` or `game.dart` at
all), so it sits at the top of the graph as a pure composition root, the
same position `BuildInterpretation` already occupied in the prior audit.

## 6. Hardcoded item combinations

**Result: No violations found.**

Grepped the whole `lib/src/plugins/` tree (including the new `game`
directory) for an `id ==`-shaped conditional on content ids — zero hits.
`game_run.dart`'s `applyUpgrade`/reward/training logic branches only on
generic string *prefixes* (`'stat:'`, `'item:'`, `'technique:'`) applied
uniformly to whichever id is passed in, never on a specific item or
technique id. The Item Combine feature's own grade-branch resolution
(`CombineResolver`, `combineItems`) is entirely tag/condition-driven via
the reused `EvolutionResolver`, with zero `if (item.id == ...)` anywhere
— confirmed by reading `combine_resolver.dart` and `item_lifecycle.dart`
in full.

## 7. Hardcoded content

**Finding (Important, new): `RunEnemies`' 5 enemies are hand-written
Dart `const` objects, not `ContentRegistry`-loaded content — despite
"Enemies" being explicitly named as a first-class Content plugin type in
`CLAUDE.md`'s own Plugin Types list.**

- **File:** `lib/src/plugins/game/run_content.dart:12-28`
- **Problem:** `CLAUDE.md`'s Plugin Types section explicitly lists
  `Enemies` alongside `MartialArts`/`Magic`/`Cultivation`/`Weapons`/
  `Potions`/`Trinicts` as a **Content plugin** — i.e. the architecture
  anticipates enemy stat blocks being data-driven content, exactly like
  items/techniques/physiques already are. Instead, `RunEnemies` is a
  hand-written `abstract final class` of five `const Enemy(...)` object
  literals (`trainingDummy`, `bandit`, `martialAdept`, `eliteWarrior`,
  `boss`), the same shape the item/technique/physique/spell content used
  to be in before each was migrated to `ContentRegistry`-loaded
  JSON-shaped maps (per this repo's own established, repeatedly-applied
  pattern — see `itemContentDefinitions`/`techniqueContentDefinitions`/
  `physiqueContentDefinitions`/`elementalContentDefinitions`). A designer
  changing an enemy's stats has to edit and recompile Dart, unlike every
  other content type in this codebase.
- **Severity:** Important — not Critical (this is application-layer
  "game" content, not Core, so it doesn't break Core's zero-plugin-knowledge
  guarantee), but more than cosmetic: it's a concrete, direct violation
  of a pattern this codebase has now applied to every other content type
  at least twice (per the prior two audits' own resolution logs), and
  `CLAUDE.md` names Enemies specifically as content, not configuration.
- **Recommended fix:** Add an `Enemy`-typed `ContentDefinition` parser
  (`enemyDefinitionFromContent`, mirroring `itemDefinitionFromContent`)
  and move the 5 enemy definitions into a `const enemyContentDefinitions`
  list, loaded via `ContentRegistry.loadAll` the same way
  `itemContentDefinitions` is in `ItemPlugin.initialize`. `game_run.dart`
  would then resolve `RunEnemies.weakPool`/`.eliteBossPool` by id lookup
  instead of holding live `Enemy` objects.

**Finding (Important, new): `run_content.dart`'s `stylesFor` hardcodes a
tradition→styles mapping that already exists, inverted, inside the
MartialArts plugin — the same data represented in two places with no
shared source of truth.**

- **Files:**
  - `lib/src/plugins/game/run_content.dart:86-90` (`stylesFor`)
  - `lib/src/plugins/martial_arts/martial_styles.dart:66-72`
    (`_traditionTagFor`, the *existing*, canonical styles→tradition
    mapping)
- **Problem:** `martial_styles.dart`'s `_traditionTagFor` already encodes
  "boxing/wrestling/fencing = western, shaolin/taiChi/wingChun = eastern"
  as the single source of truth MartialArts itself uses (via `learnStyle`).
  `run_content.dart`'s `stylesFor` re-derives the *same* mapping,
  inverted (tradition → list of styles), as an independent hardcoded
  `switch`, in a completely different plugin, with nothing tying the two
  together. If MartialArts ever adds, removes, or renames a style,
  `run_content.dart`'s list silently goes stale — the exact "content
  values that appear in two places that could drift" risk this
  category's own brief asks about, and simultaneously a category-12
  duplicate-functionality case (the same classification logic
  reimplemented instead of queried).
- **Severity:** Important — same reasoning as the finding above: not a
  Core violation, but a genuine, evidenced drift risk between two real
  modules, not a hypothetical one, and it's the second finding this pass
  identified in the exact same 91-line file.
- **Recommended fix:** Either (a) have MartialArts expose a public
  `stylesForTradition(String tradition) -> List<String>` function
  (the natural counterpart to `_traditionTagFor`, made non-private) that
  `run_content.dart` calls instead of re-deriving the mapping, or (b) if
  style content is ever migrated to `ContentRegistry` (it currently
  isn't — `MartialStyles` is a bare string-constant class, not
  content-registry data), query it by a `'tradition:<id>'` tag instead of
  hardcoding either direction of the mapping anywhere.

**Finding (Minor, new): `RunStartingKit`/`rewardPoolItemIds`/
`rewardPoolTechniqueIds` are hardcoded Dart lists of existing content
ids.**

- **File:** `lib/src/plugins/game/run_content.dart:50-64`
- **Problem:** Unlike the two findings above, these don't invent new
  stat blocks — they curate *which already-defined* item/technique ids
  this particular run offers, which is closer to level/scenario
  configuration than to "content" in the `CLAUDE.md` sense (the item ids
  referenced, e.g. `ItemIds.ironSword`, are real `ContentRegistry`-loaded
  content; only the *selection* of which ids to include is a bare Dart
  list).
- **Severity:** Minor — genuinely borderline; flagged for completeness
  per this audit's "don't just omit" instruction, not because it clearly
  crosses the line the way the enemy roster and tradition mapping do.
- **Recommended fix:** Low priority. If this "game" layer is ever
  expected to support multiple distinct run configurations (different
  starting kits, different reward pools per game mode), migrating this
  to its own small content type (e.g. a `'run_config'` `ContentDefinition`)
  would make sense; for a single fixed run definition, a plain Dart list
  is a defensible, low-risk choice.

## 8. Global mutable state

**Result: No violations found.**

Grepped for every `static` declaration across `lib/`, including the new
`lib/src/combine/` and `lib/src/plugins/game/` directories. Every hit is
a pure static *function* (`CombineOdds.forAttempt`,
`ConsoleDecisionPolicy._defaultPrint`/`._defaultReadLine`,
`ElementalEffects._statusFor`, `WeaponStatTags.matchOrFallback`,
`TrainingStatistics.average`/`.standardDeviation`, `JsonHelpers.*`,
`Container._slotFromJson`) or already-excluded `static const`/`static
final` (the latter only for genuinely-immutable derived collections like
`RunTomeSlots.all`, a `List.unmodifiable` built once from `const` inputs
— re-verified it is never reassigned or mutated in place). No mutable
`static` field, no singleton, no top-level mutable variable anywhere.
The `late` instance fields found (`CombatPlugin.system`/`.sdk`, five
other plugins' `.sdk`, `CombatSystem._killedSubscription`) are all
per-instance plugin state set once in `initialize()`, the same
already-audited pattern from the prior two passes — not global state.

## 9. Gameplay randomness bypassing RNGService

**Result: No violations found.**

Grepped all of `lib/` for `dart:math`/`Random(`. Real `dart:math` imports
remain exactly the three already-audited non-random uses
(`modifier_resolver.dart`'s `math.min`/`math.max`,
`precision_exercise.dart` and `training_statistics.dart`'s `math.sqrt`)
— nothing new. `lib/src/plugins/game/` was specifically checked: every
`dart:math` mention in `training_simulation.dart` is prose *negating*
direct use ("never calls `dart:math` directly"), confirmed by the file
having no actual `dart:math` import. `game_run.dart`'s own randomness
(`rng.nextInt(RunEnemies.weakPool.length)` for enemy selection,
`seededShuffle(..., rng)` for the reward pool) draws exclusively from the
injected `RngService` instance threaded through `PluginContext`, never a
bare `Random()`. The Item Combine feature's RNG use
(`CombineResolver.resolve`'s `rng.nextDouble()`/`rng.nextInt()`) is the
same injected-service pattern, already independently verified multiple
times during that feature's own code review.

## 10. Components containing excessive gameplay logic

**Result: No violations found.**

Every `class ...Component`-named type was re-enumerated: the 7 Core
components under `lib/src/components/` (all 7-14 lines, all pure data —
unchanged since the prior audit) plus the 6 plugin-owned components
(`CombatantComponent`, `CombatStateComponent`, `ElementalAffinityComponent`,
`MartialLoadoutComponent`, `PhysiqueComponent`, `CharacterComponent`) —
none of these six were touched this session and were already cleared by
the prior audit. The one component-shaped type that *did* change this
session, `ItemInstance` (`lib/src/plugins/item/item_instance.dart`),
gained one new field (`itemClass`, mutable — the only mutable field in
the type, and the only field `combineItems` ever writes after
construction) but zero new methods; it remains three fields, no logic,
exactly the "two fields, no methods" shape its own doc comment commits
to. `Enemy` (`lib/src/plugins/game/enemy.dart`, new this session) is
also plain data — 5 fields, no methods — though note it is explicitly
*not* an ECS component (it's a value object turned into an `AttackAction`
by `game_run.dart`, never attached via `ComponentStore`), so it's outside
this category's literal scope, mentioned here only for completeness.

## 11. God classes

**Finding (Important, new): `runGame` is a single ~630-line function
containing 19 nested closures spanning entity setup, Tome management,
reward resolution, training resolution, and combat resolution.**

- **File:** `lib/src/plugins/game/game_run.dart:69-696`
- **Problem:** `CLAUDE.md`'s Entity Model section says "Do NOT create
  giant classes" and names composition/small-services as the preferred
  style; while `runGame` is a function rather than a class, it exhibits
  the exact failure mode that guidance targets: one unit of code (627
  lines, one top-level function body) responsible for character setup,
  Tome placement (`placeItem`/`placeTechnique`/`replaceWithEvolved`),
  upgrade-point spending (`applyUpgrade`/`manageTome`, ~90 lines),
  reward resolution (`rewardCandidates`/`resolveReward`/`grantReward`),
  training resolution (`trainingCandidates`/`runTraining`, ~85 lines),
  and combat resolution (`fallbackStrikeStat`/`spawnEnemy`/`runFight`,
  ~70 lines) — 19 separate nested closures, each a distinct
  responsibility, all sharing one mutable closure scope
  (`tomeHistory`, `itemsDiscovered`, `cycleIndex`, `rewardIndex`, etc.)
  instead of being independently testable units. No single closure is
  individually unreasonable in isolation, but the whole is a textbook
  god-function: everything reaches into everything else's local state,
  and nothing in this 627-line body can be unit-tested without invoking
  the entire `runGame` call.
- **Severity:** Important — not Critical (it's the game composition
  layer, not Core, and the prior audit's own precedent treats
  `CombatSystem`'s smaller version of this pattern as Low-not-urgent) —
  but this is meaningfully larger and more sprawling than that precedent
  (627 lines and 19 closures vs. `CombatSystem`'s 257 lines as a proper
  class with real methods), and it is the single largest file in the
  entire repository by a wide margin (next largest logic file is under
  half its size).
- **Recommended fix:** Extract logically-cohesive groups of these
  closures into their own small classes/functions taking explicit
  parameters instead of closing over `runGame`'s shared mutable scope —
  e.g. a `TomeManager` (wrapping `placeItem`/`placeTechnique`/
  `replaceWithEvolved`/`manageTome`), a `RewardStage`
  (`rewardCandidates`/`resolveReward`/`grantReward`), and a
  `TrainingStage` (`trainingCandidates`/`runTraining`), each constructed
  with the specific state it needs (character, context, policy) rather
  than reaching into `runGame`'s closure. This is a real, non-trivial
  refactor — not attempted here per this audit's instructions.

**Finding (Minor, new): `item_lifecycle.dart` now covers two distinct
responsibilities — basic item lifecycle and the entire Combine
mechanic — in one 338-line file.**

- **File:** `lib/src/plugins/item/item_lifecycle.dart`
- **Problem:** The file started as a small, single-purpose module
  (own/discover/usable/active/`addItemToTome` — ~125 lines before this
  session). The Item Combine feature added `combineItems` and
  `_reflectCombineInTome` (`item_lifecycle.dart:172-338`, ~165 lines,
  roughly half the file) plus `CombineNotAvailableException`. Both
  responsibilities are legitimately item-plugin-owned, but they're now
  distinct enough (basic possession/placement vs. a whole
  probabilistic-outcome game mechanic) that they read as two modules
  sharing one file.
- **Severity:** Minor — 338 lines is not large by this repo's own
  precedent (`content_registry.dart` is 293 lines, `combat_system.dart`
  257), and every function is independently well-documented and tested;
  this is a naming/organization observation, not a functional problem.
- **Recommended fix:** If this file grows further, split `combineItems`/
  `_reflectCombineInTome`/`CombineNotAvailableException` into a sibling
  `item_combine.dart`, mirroring how `lib/src/combine/` itself is
  already split into one-concern-per-file. Not urgent at current size.

The previously-carried-over `CombatSystem` Low finding remains open,
unchanged — no new action recommended, consistent with both prior
audits.

## 12. Duplicate engine functionality inside plugins

**Result: No new duplicate *engine mechanism* reimplementations found**
beyond the tradition/style mapping already reported under category 7
(cross-referenced here since it is equally a category-12 case: the same
classification logic reimplemented rather than shared — see that
section for the full finding). The Item Combine feature specifically
reuses, rather than reimplements, every relevant Core mechanism:
`EvolutionResolver` for weighted grade-branch selection (not a new
ad-hoc weighted pick), `ResourcePool.consume`/`.canAfford` for the
`upgrade_points` cost (not custom clamping), `modifiersFromProperties`
for `ItemDefinition.modifiersFor` (not a new Modifier-construction loop),
and the existing `RngService` for its one roll. `TomeService.replace` is
reused by both `game_run.dart`'s `replaceWithEvolved` and
`item_lifecycle.dart`'s `_reflectCombineInTome` — two independent call
sites, but both call the same Core primitive rather than reimplementing
Tome-slot replacement.

## 13. Direct cross-plugin calls that should use events/interfaces

**Result: No violations found — one new case explicitly considered and
cleared, following the same reasoning the prior audit applied to
`AutoCombatController`/the Build Interpretation interpreters.**

`game_run.dart` calls `itemDefinition`/`techniqueDefinition`/
`ownItem`/`discoverItem`/`isItemUsable`/`addItemToTome`/`addTechniqueToTome`/
`isTechniqueLearned`/`isTechniqueDiscovered`/`attemptToLearnTechnique`/
`evolveTechnique`/`learnStyle`/`initializePhysique` directly — every one
of these is each plugin's own documented public lifecycle API (the exact
functions each plugin's own tests call), not a reach into private
implementation, and `game_run.dart`'s entire purpose is to *compose*
these plugins into one run — exactly analogous to how
`AutoCombatController` legitimately calls `CombatSystem.executeAction`
directly (the prior audit's own category-13 conclusion, now extended one
layer up to the composition-root layer that calls `AutoCombatController`
itself).

## 14. Domain-specific concepts leaking into Core

**Finding (Minor, carried forward from this session's own code review —
already known, not newly discovered by this audit): `lib/src/combine/`'s
naming still carries Item-plugin-flavored vocabulary in its public API,
despite containing zero plugin imports/coupling.**

- **File:** `lib/src/combine/combine_outcome.dart` (`CombineOutcome
  .classUpgrade`/`.gradeUpgrade`), `combine_resolver.dart`
  (`atMaxTierForGrade`, `gradeEvolution`, `gradeContext`, `gradeProfile`,
  `chosenGradeTargetId` parameter/field names)
- **Problem:** `CLAUDE.md`'s category-1 spirit ("the core must NOT know
  what ... means") is about behavior/imports, which this module already
  satisfies — but the *names themselves* ("class," "grade") are
  Item-plugin concepts (an item's numeric tier and its qualitative
  branch), not truly domain-neutral Core vocabulary the way
  `EvolutionDefinition.tier`/`EvolutionCandidate` are. This was
  identified and explicitly accepted (spec-sanctioned, no functional
  coupling) during this session's own final code review for the Item
  Combine feature, not fixed at the time — recorded here so it isn't
  lost.
- **Severity:** Minor — purely naming, zero functional coupling (a
  second plugin could use `CombineResolver` today without any code
  change, just living with names that read as item-flavored), and
  already reviewed/accepted once.
- **Recommended fix:** Unchanged from the original review's
  recommendation — rename to genuinely generic terms (e.g.
  `CombineOutcome.tierUpgrade`/`.branchUpgrade`, `atMaxTierForBranch`,
  `branchDefinition`/`branchContext`/`branchProfile`,
  `chosenBranchTargetId`) before a second plugin adopts this API, so the
  rename doesn't become a breaking change later. Not urgent today.

No other Core service's API design (parameter names, method names, enum
values) was found to encode domain vocabulary — re-checked
`ItemRequirement.masterySubject`, `TechniqueDefinition.tier` (reuses the
pre-existing generic `EvolutionTiers` constants), `CombatAction.priority`,
and everything in `lib/src/evolution/`/`lib/src/resource/` fresh; all
remain plain, uninterpreted strings/numbers.

## 15. Serialization depending on runtime implementation classes

**Result: No violations found.**

Every `toJson`/`fromJson` pair in the repository is unchanged from the
prior audit's enumeration (`Container`, `CombatStateComponent`/
`CombatantComponent`, `MartialLoadoutComponent`, `ContentRegistry`/
`ContentDefinition`). Neither the Item Combine feature nor the `game`
composition layer adds any serialization code, so there's nothing new to
violate this category — but the save/load coverage gap widens further,
worth noting for completeness: `ItemInstance.itemClass`, every
`CombineResolver`/Item-Combine-feature type, and the entire `game`
layer's `RunResult`/`DecisionLog`/`TomeSnapshot`/telemetry-event types
have no `toJson`/`fromJson` at all. This gap is not itself a category-15
violation (nothing here *incorrectly* serializes a runtime object —
there's simply no serialization yet), and notably `DecisionLog`
(`lib/src/plugins/game/decision_log.dart:1-30`) is a positive example of
this category's actual concern done right *without* formal
`toJson`/`fromJson`: it's built entirely from stable data (`String`,
`int`, `bool`, `SlotId`), holds zero live entity/component references,
and is explicitly designed to reproduce a run exactly via replay — the
architecture this category cares about, just not yet wired to an actual
save format.

---

## Additional observations (outside the 15 requested categories)

**A. `game_run.dart` hardcodes the `'upgrade_points'` resource id as a
raw string in 4 places instead of using `ItemResources.upgradePoints`,
the constant this session's own Item Combine work introduced
specifically to avoid this.**

- **File:** `lib/src/plugins/game/game_run.dart:279,290,458,645`
- **Problem:** `CLAUDE.md`'s Code Quality section explicitly lists
  "magic strings scattered throughout code" as something to avoid.
  `ItemResources.upgradePoints` (`lib/src/plugins/item/item_vocabulary.dart`)
  now exists as the canonical constant for this exact string, created
  this session for exactly this purpose — but `game_run.dart` predates
  it (from an earlier commit) and was never backfilled. Not a functional
  bug today (the literal string matches exactly), but a real drift risk:
  if the resource id constant ever changes, these four call sites won't
  get a compile error, they'll silently stop working.
- **Severity:** Minor — cosmetic/hygiene, zero current behavioral risk,
  trivial fix.
- **Recommended fix:** Import `item_plugin.dart` in `game_run.dart` (already
  imported) and replace all four `'upgrade_points'` literals with
  `ItemResources.upgradePoints`.

**B. `lib/src/reward/` importing `lib/src/tome/` — unchanged, still
informational, not a finding** (carried over verbatim from both prior
audits: `RewardCandidate.ref` reusing `BuildComponentRef` directly; still
a Core-module-to-Core-module value-type dependency, no plugin-boundary
rule implicated, nothing about it changed this session).

---

## Summary

| # | Category | Result at audit time | Status now |
|---|---|---|---|
| 1 | Core importing game-specific modules | ✅ No violations | ✅ still clean |
| 2 | Combat importing MartialArts | ✅ No violations | ✅ still clean |
| 3 | Combat importing Magic | ✅ N/A — no Magic plugin exists | ✅ N/A |
| 4 | Plugins accessing private implementation of other plugins | ✅ No violations | ✅ still clean |
| 5 | Circular dependencies | ✅ No violations | ✅ still clean |
| 6 | Hardcoded item combinations | ✅ No violations | ✅ still clean |
| 7 | Hardcoded content | ⚠️ 3 findings (2 Important, 1 Minor) | ✅ 2 Important fixed; 1 Minor — no action needed, confirmed low-risk |
| 8 | Global mutable state | ✅ No violations | ✅ still clean |
| 9 | Gameplay randomness bypassing RNGService | ✅ No violations | ✅ still clean |
| 10 | Components containing excessive gameplay logic | ✅ No violations | ✅ still clean |
| 11 | God classes | ⚠️ 2 findings (1 Important, 1 Minor) | ✅ both fixed |
| 12 | Duplicate engine functionality inside plugins | ⚠️ Cross-referenced with category 7 | ✅ fixed alongside category 7 |
| 13 | Direct cross-plugin calls that should use events/interfaces | ✅ No violations | ✅ still clean |
| 14 | Domain-specific concepts leaking into Core | ⚠️ 1 finding (Minor, already known) | ✅ fixed |
| 15 | Serialization depending on runtime implementation classes | ✅ No violations | ✅ still clean (coverage gap unchanged, not a violation) |

**At audit time: 6 findings — 3 Important, 3 Minor. Zero Critical.**
**After the same-day fix pass: 5 of 6 fixed; 1 Minor (reward-pool id
lists) deliberately left as-is, confirmed low-risk. `dart analyze lib
test` clean, 1,105 tests passing (unchanged count — this pass moved and
renamed code, it did not add or remove test coverage).**

**Overall assessment:** The engine core and every registered plugin
continue to honor `CLAUDE.md`'s contract cleanly — zero Core-purity
violations, zero circular dependencies, zero cross-plugin private-access
violations, zero unmanaged randomness, across two consecutive
from-scratch audits now. Every finding in this pass sits in the same
place the prior audit's did: the newest, least-reviewed surface. Last
time that was five new plugin-adjacent subsystems; this time it's
`lib/src/plugins/game/` (never audited before this pass) and the Item
Combine feature (audited extensively during its own development, but
re-checked fresh here). The two Important findings that matter most —
`RunEnemies`'/`stylesFor`'s hardcoded content in `run_content.dart`, and
`runGame`'s 627-line god-function — are both confined to the `game`
composition layer, not Core or any reusable plugin, meaning they don't
threaten the "Core Engine + MartialArtsPlugin + MagicPlugin +
CultivationPlugin, without modifying Core Engine" success criterion
`CLAUDE.md` states as the ultimate test — but they are real, and `game`
has now grown large and old enough (1,783 lines, present since before
the prior audit yet never reviewed) that it deserves the same
audit-and-fix discipline every other subsystem in this repository has
already received at least once.
