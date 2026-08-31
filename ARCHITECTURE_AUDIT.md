# Architecture Audit

**Date:** 2026-08-31
**Repo:** `built_engine` @ `main` `7697417` — 192 `.dart` files under `lib/`,
~13,100 lines. Client cross-referenced: `Tome_client_v1` @ `main` `75d8957`.
**Method:** full read of `claude.md` (the architecture contract), `README.md`,
`ARCHITECTURE.md` (§ headings + dependency/ownership/serialization sections),
`PLUGIN_SYSTEM.md`, and the prior audit (`042aa7e`, 2026-08-25) for context.
Per-directory and per-plugin import-graph extraction; targeted greps for
`dart:math`/`Random(`/`dart:io`, `switch (styleId)` / `id ==`-shaped checks,
`package:build_engine/src/plugins/` private-path imports, `toJson`/`fromJson`;
full reads of every file in `lib/src/plugins/game/`, `lib/src/plugins/martial_arts/`,
the public barrels, `test/integration/architecture_dependency_test.dart`, and the
client's `combat_adapter.dart` / `reward_adapter.dart` / `enemy_roster.dart`.
**No source changes made.** This is a report only; refactoring is a separate,
approval-gated step.
**Baseline:** engine `dart analyze` clean, `dart test` 1139 passing. Client
`flutter analyze` clean, `flutter test` 147 passing.

This is a **from-scratch audit**, not a diff against the prior one. The prior
audit (2026-08-25) is superseded: all six of its findings were fixed the same
day (`runGame` god-function split into four stages, `enemy_content.dart` /
`stylesForTradition` extraction, combine-API rename, `upgrade_points` constant).
Those fixes are re-verified as still in place and are **not** re-listed here.
Since then the repo gained: per-technique mastery axes, `TechniqueEvolved`
moved onto the Technique barrel, `ConsoleDecisionPolicy` split behind
`console_policy.dart`, and **Content Expansion V1** — +30 technique forms,
palm/finger/kick families, `hand_wraps` + starter combine chains, 9
style-gated martial techniques, style specialties (`spec:*` tags +
`styleAlignedFamilies`/`MartialSpecs` exports), and a content audit test +
`tool/validate_content.dart`. V1 is the primary new surface this pass examines.

---

## Executive Summary

**Overall architecture health: good, and improving at the Core boundary — but
the "game" is no longer where the architecture says it is.**

The engine core continues to honour `claude.md`'s contract cleanly. Across
three consecutive from-scratch audits there are still **zero** Core-purity
violations, **zero** circular dependencies, **zero** cross-plugin private-path
imports inside `lib/src/plugins/`, and **zero** unmanaged gameplay randomness
in the engine. The plugin graph is a strict DAG
(`Core ← Combat ← {AutoCombat, MartialArts}`, `Core ← {Item, Technique,
Physique, Elemental}`, `… ← BuildInterpretation ← Game`). This is enforced in
CI by `test/integration/architecture_dependency_test.dart`, which is a genuine
architectural guardrail, not a smoke test. The prior audit's god-function
(`runGame`) is gone, split into four independently-constructable stages. Core
mechanisms (`EvolutionResolver`, `modifiersFromProperties`, `ResourcePool`,
`RngService`) are reused rather than reimplemented inside plugins.

**The largest risk is not in the engine — it is that the shipped game now
lives in two places.** `built_engine/lib/src/plugins/game/` (`runGame` + the
four stages + `enemy_content.dart` + `run_content.dart`) is presented by its
own barrel as *"the first real headless game run — composes every existing
plugin"*. But the client (`Tome_client_v1`) does **not** consume it. The client
has its own parallel composition: `CombatAdapter`, `RewardAdapter`,
`TrainingAdapter`, `TomeAdapter`, `RunBloc`. Content Expansion V1 widened the
gap decisively — **enemy archetypes, the off-specialty damage penalty, the
Conditioning / Burst Chain style specialties, contextual reward weighting, and
adaptive training pacing all exist only in the client.** The engine's `game`
layer still runs 5 flat stat-block enemies, a uniform-ish reward pool of 8
ids, and no style specialties at all. The engine exports the *data* for the
new rules (`styleAlignedFamilies`, `MartialSpecs`) but provides no *contract*
that applies it, so the client had to write its own combat resolver on top of
`CombatSystem` rather than on top of `AutoCombatController`.

**Strongest architectural decisions:** the Core-verbs / plugin-nouns split is
real and CI-enforced; `EvolutionResolver` is genuinely generic (reused by both
Technique evolution and Item Combine with zero `if (id == …)`); the
tag+modifier system carries almost all cross-domain interaction (Physique ↔
MartialArts share only tag *strings*, never imports); `RngService` is threaded
through `PluginContext` and honoured everywhere in `lib/`.

**Biggest scaling risks:**
1. Martial styles are the one content type that is *not* `ContentRegistry`
   data — they are 6 hand-maintained id-keyed structures that must be edited
   in lockstep to add a style.
2. No serialization of gameplay state exists; a run cannot be saved or resumed
   mid-run, and the client papers over this by rebuilding the entire engine
   session from a seed on every launch.
3. Style-specialty and off-specialty combat rules have no engine home, so they
   cannot be tested by the engine, reused by a future client, or applied by
   the headless balance sim.

**Is the repository safe for continued content expansion?** **Yes, for
adding techniques, items, enemies and physiques** — those all flow through
`ContentRegistry` and validated content data, and V1 proved a 3× technique
expansion lands without touching a single mechanic. **With caution for adding
styles or style-scoped rules** — that path currently means editing engine
source in 6 places *and* the client's `CombatAdapter`, with only a partial
validator to catch drift.

---

## Severity Summary

```
Critical: 0
High:     2   (A1, A2 — RESOLVED 2026-09-01, see below)
Medium:   4   (A4 — RESOLVED 2026-09-01)
Low:      3
Info:     3
```

### Resolved (2026-09-01, laser-targeted A1/A2/A4 refactor)

- **[A4]** `resolveTechniqueEvolutionAfterTraining` on
  `technique_plugin.dart` is now the single evolution decision and the
  single `TechniqueEvolved` publisher; `TrainingStage` and the client's
  `TrainingAdapter` call it and only do their own follow-up. Locked by
  `technique_evolution_flow_test` + an architecture test asserting one
  class definition / one publisher.
- **[A2]** `StyleCombatRules` + `BurstChainState` on
  `martial_arts_plugin.dart` own the off-specialty penalty, Shaolin
  Conditioning and Kunlun Burst Chain (pure, deterministic, no
  RNG/context/Flutter). The client's `CombatAdapter` consumes them and no
  longer restates any of the numbers. Locked by `style_combat_test` +
  client/engine architecture tests.
- **[A1]** The two named divergent rule sets (style combat, evolution
  trigger) now have one engine implementation each. `lib/game.dart` /
  `game_run.dart` / `combat_stage.dart` are documented as a headless
  reference / balance-simulation harness — the client owns run
  composition/sequencing/presentation, the engine owns the domain rules
  both consume. Locked by an architecture test asserting nothing outside
  `plugins/game/` imports the harness. *Not* addressed: unifying the
  combat *loop* itself or moving enemy-roster / reward-pool *selection*
  (those are UI-facing client orchestration by the target architecture).

The findings below are the audit as written on 2026-08-31 and are kept
verbatim for the record.

---

## Architecture Map

### Module dependency graph (as built, verified from imports)

```
                         ┌─────────────────────────── CORE ───────────────────────────┐
                         │ entity · component(s) · event · query · rule · modifier     │
                         │ resource · rng · spatial · tome · reward · evolution        │
                         │ mastery · progression · discovery · content · combine       │
                         │ character · plugin(SDK/context/manager)                     │
                         └────────────────────────────────────────────────────────────┘
                            ▲        ▲        ▲        ▲        ▲            ▲
                            │        │        │        │        │          │
                         Combat   Item   Technique  Physique  Elemental    │
                            ▲                                              │
                            │                                              │
                   ┌────────┴────────┐                                     │
                AutoCombat      MartialArts ──────────────────────────────┐│
                   ▲                 ▲   (Core + Combat)                  ││
                   │                 │                                    ││
                   └──── BuildInterpretation (Core + Combat + Item + Technique)
                                     ▲
                                     │
                        ┌────────────┴──────────────┐
                        │  Game composition layer   │   lib/src/plugins/game/
                        │  runGame + 4 stages +      │   (headless sim; NOT consumed
                        │  enemy_content/run_content │    by the client — see [A1])
                        └───────────────────────────┘
```

No suspicious arrows inside `lib/`. Every arrow points down toward Core.
`Game` is a pure top-of-graph composition root; nothing imports it back.

### The arrow that is missing

```
built_engine/lib/src/plugins/game/   ─── X ───   Tome_client_v1
(reference composition)              not used     (ships its own composition:
                                                   CombatAdapter, RewardAdapter,
                                                   TrainingAdapter, RunBloc)
```

The client consumes plugin **barrels** (`item_plugin.dart`,
`technique_plugin.dart`, `martial_arts_plugin.dart`, `combat_plugin.dart`,
`auto_combat_plugin.dart`, `build_interpretation.dart`) directly and never
imports `game.dart`. See finding **[A1]**.

### Public API boundary

Every plugin has a barrel (`lib/<name>_plugin.dart` / `lib/build_interpretation.dart`
/ `lib/game.dart` / `lib/console_policy.dart`). Intended consumers need no
`src/` import — **except**:

- `tool/validate_content.dart` imports 8 `package:build_engine/src/plugins/*`
  private paths for content constants that public barrels already re-export.
- `test/content/content_expansion_audit_test.dart` does the same.

See finding **[A6]**. No `implementation_imports` lint fires because these are
in-package, but the validator — the piece meant to be reusable for CI and
future content packs — is coupled to internal file layout.

### Content ownership

| Content type | Representation | Registry-loaded | Validated |
|---|---|---|---|
| Items (43 forms) | `itemContentDefinitions` data maps | yes | yes (audit test + tool) |
| Techniques (41 forms) | `techniqueContentDefinitions` data maps | yes | yes |
| Martial techniques (18) | `martialTechniqueContentDefinitions` data maps + 18 hand-written factory wrappers | yes | partial (style-ref check only) |
| Physiques (4) | `physiqueContentDefinitions` data maps | yes | no |
| Enemies (engine, 5) | `enemyContentDefinitions` data maps | yes (headless only) | id-uniqueness only |
| Enemies (client, 8 + 3 bosses) | `EnemyArchetype` enum + `_base()` switch in `Tome_client` | no | no |
| **Martial styles (6)** | **`MartialStyles` constants + 4 switches + 2 maps, hand-maintained** | **no** | **no** |
| Rewards | client `RewardAdapter` weighting; engine `RewardResolver` unused by client | n/a | pool-id lock test (client) |

### Event flow

`EventBus` is a single Core service (`lib/src/event/event_bus.dart`).
Cross-domain facts flow as events: `TechniqueEvolved` (owned by Technique
plugin — `technique_events.dart`; **published by the composition layer**, not
the plugin — see [A4]), `EntityDamaged`/`EntityHealed`/`ActionCompleted`
(Combat), `ItemCombineSucceeded`/`Failed` (Item), `MasteryChanged`,
`DiscoveryRecorded`, `SlotUnlocked` (game layer). The `martial_arts_rules.dart`
rules react to Combat events (`EntityDamaged`, `ActionCompleted`,
`TurnStarted`) rather than intercepting `AttackAction` — correct decoupling.

### RNG flow

```
seed ─→ RngService (Core, lib/src/rng/) ─→ PluginContext.rng ─→ every gameplay draw
```

`dart:math` appears only for `min`/`max`/`sqrt` (`modifier_resolver.dart`,
`training_statistics.dart`, `precision_exercise.dart`) — no `Random()` in
`lib/`. `EvolutionResolver`, `CombineResolver`, `weighted_pick`, and the
headless sim's enemy/reward selection all draw from the injected `RngService`.
Client-side, `Tome_client`'s `enemy_roster.dart` uses pure arithmetic
(`runNumber * 7 + fightIndex * 3`) for deterministic archetype selection — no
RNG, acceptable, but note it is a *third* place run-progression randomness
policy is decided (engine `game_run` uses `rng.nextInt`, client `RunBloc`
uses the seed, `enemy_roster` uses arithmetic).

---

## Domain Ownership Table

| Concept | Current Owner | Recommended Owner | Status |
|---|---|---|---|
| Item mastery | Item plugin (`item_lifecycle`, `MasteryTracker`) | Item plugin | ✅ correct |
| Technique learning | Technique plugin (`technique_lifecycle`, `ProgressionEngine`) | Technique plugin | ✅ correct |
| Technique mastery | Technique plugin (`MasteryDefinition` per form) | Technique plugin | ✅ correct |
| Technique evolution **mechanism** | Core `EvolutionResolver` + Technique `evolveTechnique` wrapper | same | ✅ correct |
| Technique evolution **trigger** ("when to evolve") | `game/training_stage.dart` **and** client `training_bloc.dart` — two impls | Technique plugin contract (an explicit `maybeEvolveAfterTraining` the composition calls) OR one shared composition | ⚠️ **[A4]** |
| Item combine | Item plugin (`item_combine.dart`) + Core `CombineResolver` | same | ✅ correct |
| Item / grade evolution | content data (`gradeEvolution`) + `EvolutionResolver` | same | ✅ correct |
| Physique effects | Physique plugin (conditional modifiers on tradition tags) | Physique plugin | ✅ correct |
| Martial style **tradition / kit** | MartialArts plugin (`martialTraditionOf`, `stylesForTradition`) | MartialArts plugin | ✅ correct location, ⚠️ representation — see [A3] |
| Martial style **specialties (combat effects)** | client `CombatAdapter` (Conditioning, Burst Chain, off-specialty ×0.85) | MartialArts plugin + a generic Combat contract | ⚠️ **[A2]** |
| Martial style **static affinity modifier** | MartialArts `learnStyle` `switch` | MartialArts plugin | ✅ location; ⚠️ hardcoded per-id — see [A3] |
| Training evaluation | Core `training/` (`TrainingExercise`, `TrainingProfile`) | Core | ✅ correct |
| Training **input generation** | `game/training_simulation.dart` (synthetic) **and** client `TargetStrikeExercise` (real) | composition layer (both valid) | ✅ acceptable divergence |
| Combat resolution | Core-ish `CombatSystem` + `AutoCombatController` (engine) **and** `CombatAdapter._Resolver` (client) | one owner; client should build on `AutoCombatController`, not reimplement its loop | ⚠️ **[A1]/[A2]** |
| Enemy archetype behaviour | client only (`EnemyView` fields → `CombatAdapter`) | a Combat-adjacent contract or content type both layers read | ⚠️ **[A1]** |
| Reward generation | client `RewardAdapter` (weighted); engine `RewardResolver` (unused by client) | one owner | ⚠️ **[A1]** |
| Run progression | client `RunBloc` (`fightsForRun`) + engine `game_run` cycle loop | composition layer (both valid, but duplicated numbers) | ⚠️ **[A1]** |
| Tome placement | Core `TomeService` + `game/tome_manager.dart` / client `TomeAdapter` | Core mechanism ✅; composition wrappers duplicated | INFO |
| Discovery state | Core `discovery/` (`DiscoveryTracker`) | Core | ✅ correct |
| Tags / Modifiers | Core (`tag_set`, `modifier/`) | Core | ✅ correct |
| RNG | Core `RngService` via `PluginContext` | Core | ✅ correct |
| Serialization | **none for gameplay state** (6 types only: 3 combat components, 2 content types, Container) | Core Serialization service (unbuilt) | ⚠️ **[A5]** |

---

## Findings

### [A1] The shipped game composition is duplicated: `lib/src/plugins/game/` vs the client

**Category:** 4 (Domain Ownership), 15 (Game Composition Layer), 22 (Duplicated Engine Functionality)
**Severity:** High

**File:**
- `built_engine/lib/src/plugins/game/game_run.dart` (334 lines), `combat_stage.dart`, `reward_stage.dart`, `training_stage.dart`, `tome_manager.dart`, `enemy_content.dart`, `run_content.dart`
- `built_engine/lib/game.dart:1-27` (the barrel docstring claiming this is "the first real headless game run — composes every existing plugin")
- `Tome_client_v1/lib/core/engine/combat_adapter.dart`, `reward_adapter.dart`, `training_adapter.dart`, `tome_adapter.dart`
- `Tome_client_v1/lib/core/models/enemy_roster.dart`, `enemy_view.dart`
- `Tome_client_v1/lib/features/run/run_state.dart` (`fightsForRun`)

**Problem:** Two independent implementations of "compose the plugins into a
playable run" exist and have materially diverged. `built_engine/lib/src/plugins/game/`
resolves the Tome, spawns enemies, runs fights via `AutoCombatController`,
grants rewards from `run_content.dart`'s pools, and runs training via
`TrainingStage`. `Tome_client_v1` re-does every one of those in its own
adapters + blocs: `CombatAdapter._Resolver` is a hand-written turn loop that
*replaces* `AutoCombatController` for the player's side; `RewardAdapter` is a
weighted picker with no engine equivalent; `enemy_roster.dart` is an
8-archetype + 3-boss data model with `armour`/`dodge`/`missPunish`/`regen`/`hits`
fields the engine's `Enemy` type does not have. Content Expansion V1 landed
**entirely on the client side** for combat/reward/enemy behaviour — the engine
`game` layer still runs `enemy_content.dart`'s 5 flat stat blocks
(`training_dummy` … `boss`) scaled by a linear 12%/cycle ramp, offers the
pre-V1 8-id reward pool, and applies no style specialties.

**Why it matters:** (1) The engine's `game` layer is now a stale, unshipped
approximation — it can't validate the real game's balance, and any test that
relies on it (`test/game/`) is testing a fiction. (2) Every gameplay rule
added to the client (enemy archetypes, off-specialty penalty, reward
weighting) is invisible to the engine's test suite, so the engine cannot
regression-test the behaviour players actually see. (3) The client had to
reimplement a combat turn loop rather than extend `AutoCombatController`,
because `AutoCombatController` offers no hook for "roll success off live
mastery, then run damage" or "apply an off-specialty multiplier." That is an
engine API gap the client worked around by going one layer lower
(`CombatSystem.executeAction` directly). (4) Run-length numbers
(`fightsForRun` 3/5/7/9) and boss cadence now live in two places with nothing
tying them.

**Current ownership:** split, unclearly. `game.dart`'s docstring asserts
ownership the client does not honour.
**Recommended ownership:** Decide explicitly. Either (a) the engine's `game`
layer is the canonical composition and the client is a thin renderer over it —
in which case the V1 client rules must move down into it (and `CombatStage`
must grow the hooks `CombatAdapter` needed); or (b) the client owns
composition and `lib/src/plugins/game/` is explicitly relabelled a
**balance/CI simulation harness** (not "the game run"), kept deliberately
simple, with the shared gameplay contracts (enemy archetype shape, combat
success/mastery hook, off-specialty factor) extracted so both layers call the
same primitives.
**Recommended fix:** Pick (b) — it matches how the code actually evolved.
Concretely: (i) extract an `EnemyArchetype`/`EnemyView`-shaped content type
into the engine (data + fields, no behaviour) that both `enemy_content.dart`
and the client roster load; (ii) add a Combat-layer or BuildInterpretation
contract for "resolve one player action with a success roll + post-hit
modifiers" so the client builds on it instead of a bespoke `_Resolver`; (iii)
rename `lib/game.dart`'s docstring and `game_run`'s comments to "headless
balance simulation," and update `run_content.dart`'s pools to include V1
content so the sim exercises the real catalogue.
**Refactor risk:** Medium–High. Touches the client's combat path (recently
rebuilt and delicate) and the engine's `game` layer. Do it in slices behind
tests; the client's `combat_adapter_test.dart` and the engine's `test/game/`
are the safety nets.
**Related systems:** Combat, AutoCombat, BuildInterpretation, MartialArts
(specialties), the client's entire `core/engine/` layer.

---

### [A2] Style-specialty and off-specialty combat rules have no engine owner

**Category:** 5 (Hardcoded Gameplay), 9 (Martial Arts Architecture), 12/22
(Duplication), 27 (Client Boundary)
**Severity:** High

**File:**
- `built_engine/lib/src/plugins/martial_arts/martial_styles.dart:49-100` (`learnStyle` registers only the *static* modifier slice)
- `built_engine/lib/src/plugins/martial_arts/martial_vocabulary.dart:20-97` (`MartialSpecs`, `styleAlignedFamilies`, `recognisedFamilyTags`, `offSpecialtyDamageFactor` — **data with no engine consumer**)
- `Tome_client_v1/lib/core/engine/combat_adapter.dart` (`offSpec()`, `_bladeStreak`/Burst Chain, `conditioning`/−1 floor — **the only place the rules run**)

**Problem:** `learnStyle` grants `spec:*` tags and one static `Modifier` per
style, then its own docstring says the *dynamic* parts —
"opening pre-emption, clinch dodge-ignore, riposte window, conditioning
damage floor, redirect, swallow free-dodge, burst chain … and the −15%
off-specialty penalty are applied by the client `CombatAdapter`." The engine
ships the vocabulary (`MartialSpecs.byStyle`, `styleAlignedFamilies`,
`offSpecialtyDamageFactor`) but nothing in `lib/` reads it. The rules that
turn that data into damage numbers live exclusively in the client. The
engine's own `CombatStage` / `AutoCombatController` path ignores styles
entirely.

**Why it matters:** The off-specialty penalty is a core balance lever the user
explicitly requested ("penalty if technique is outside specialty — e.g.
broadsword by Shaolin"). It is currently untestable by the engine, unusable by
the headless balance sim, and un-reusable by any future client or the future
"Magic" build system. `claude.md` is explicit that "style-specific effects
[should be] implemented through generic systems" and that Combat "must never
know that magic exists" — the inverse risk here is that the *only*
implementation of style-scoped combat effects is in a Flutter app, so the
engine has no generic mechanism for "content-scoped damage multiplier keyed on
a capability set" at all.

**Current ownership:** client `CombatAdapter` (a Flutter-repo file).
**Recommended ownership:** MartialArts plugin owns the *policy* (which family
tags are in-lane, which `spec` does what); a generic Combat / BuildInterpretation
contract owns the *mechanism* (apply a per-action damage factor and per-spec
hooks during resolution). The off-specialty multiplier specifically is a
generic idea — "an actor's capability set vs. an action's tag set yields a
scalar" — and belongs as a generic Combat modifier hook, not a martial-arts
special case.
**Recommended fix:** Add a `CombatAction` resolution hook (or a
`BuildActionInterpreter` decorator) that takes an actor + action tags and
returns a damage scalar and optional per-hit callbacks; MartialArts registers
one implementation driven by `styleAlignedFamilies` / `MartialSpecs`. The
client then calls the engine hook instead of its private `offSpec()` /
`_bladeStreak` / `conditioning` code. Gate on `spec:*` tags generically, never
`if (styleId == …)` (the client already does this correctly — preserve it).
**Refactor risk:** Medium. Isolated to the resolution path; no content data
changes. The client's `combat_adapter_test.dart` already pins the expected
ratios (`shaolin == kunlun × 0.85`), so a move is verifiable.
**Related systems:** Combat, AutoCombat, BuildInterpretation, MartialArts,
[A1].

---

### [A3] Martial styles are 6 hand-maintained id-keyed structures, not content

**Category:** 6 (Content Architecture), 9 (Martial Arts Architecture), 24
(Content Scale Readiness)
**Severity:** Medium

**File:** `built_engine/lib/src/plugins/martial_arts/`
- `martial_styles.dart:14-21` — `MartialStyles` constant class (6 ids)
- `martial_styles.dart:77-99` — `learnStyle`'s `switch (styleId)` (per-style static modifier)
- `martial_styles.dart:105-114` — `martialTraditionOf` `switch`
- `martial_styles.dart:130-134` — `stylesForTradition` `switch`
- `martial_vocabulary.dart:38-52` — `MartialSpecs.byStyle` map
- `martial_vocabulary.dart:74-83` — `styleAlignedFamilies` map

**Problem:** Every other content type in this repo — items, techniques,
physiques, enemies — is a `ContentRegistry`-loaded data map validated by the
content audit. Styles are the sole exception: a style is a bare string
constant plus **six** separate hand-authored id-keyed structures (two
`switch`es on `styleId`, one `switch` for tradition→styles, and three maps).
Content Expansion V1 grew this from 2 structures to 6. Adding style #7 means
editing all six in lockstep — and nothing checks that they agree (e.g. a style
in `MartialSpecs.byStyle` but missing from `styleAlignedFamilies` compiles and
ships silently). `learnStyle`'s `switch` also has no `default`, so an
unrecognised style silently gets no affinity modifier.

**Why it matters:** `claude.md` names "MartialArts" as a content plugin and
says "content should preferably be represented as data … do not create a new
source-code class for every individual item." The style path violates the
spirit of that as content grows: it is the single highest-friction extension
point in the engine, and the friction scales with the number of per-style
levers (V1 tripled it). The prior audit already flagged that "style content is
[not] migrated to ContentRegistry" as latent; V1 makes it active debt.

**Current ownership:** MartialArts plugin (correct plugin, wrong shape).
**Recommended ownership:** MartialArts plugin, as `ContentRegistry` data —
one `styleContentDefinitions` entry per style carrying `{id, tradition,
alignedFamilies, specs, affinityModifier}`, parsed the way
`physiqueDefinitionFromContent` already parses conditional modifiers from raw
maps. `learnStyle` becomes a generic loop over the parsed definition; the four
switches and two maps collapse into one data list. `martialTraditionOf` /
`stylesForTradition` become registry queries.
**Recommended fix:** Model a `StyleDefinition` + `styleContentDefinitions`
mirroring `PhysiqueDefinition` / `physiqueContentDefinitions` (which already
solved "turn a raw modifier map into conditional `Modifier`s" without a
dependency cycle). Extend the content audit to cross-check
`specs`↔`alignedFamilies`↔`tradition` consistency per style.
**Refactor risk:** Medium. `learnStyle` is called by both composition layers
and several tests; keep the function signature, change only its body and its
data source. `martial_styles_test.dart` already asserts the per-style modifier
values and spec tags — a good safety net.
**Related systems:** MartialArts, Physique (the pattern to copy), content
validator [A6], [A2].

---

### [A4] Technique-evolution trigger policy lives in the composition layers, duplicated

**Category:** 7 (Technique Evolution Architecture), 22 (Duplication)
**Severity:** Medium

**File:**
- `built_engine/lib/src/plugins/technique/technique_evolution.dart` (`evolveTechnique` — doc: "Never called automatically by `attemptToLearnTechnique`; evolution stays an explicit, separate operation the caller invokes when ready")
- `built_engine/lib/src/plugins/game/training_stage.dart:118-131` (calls `evolveTechnique` immediately after a successful `attemptToLearnTechnique`, if `evolutionCandidates.isNotEmpty`, and publishes `TechniqueEvolved`)
- `Tome_client_v1/lib/features/training/training_bloc.dart` (evolves on training-run completion via `TargetStrikeExercise`, a different trigger condition)
- `built_engine/lib/src/plugins/game/run_events.dart:43` (doc explicitly notes `TechniqueEvolved` is "published here by `TrainingStage`", not by the plugin that owns the type)

**Problem:** The Technique plugin owns the evolution *mechanism*
(`EvolutionResolver` via `evolveTechnique`) and the event *type*
(`TechniqueEvolved`, correctly on the barrel since the prior fix). But it
deliberately does not decide *when* evolution is attempted or *publish* the
event — that is left to the caller. There are now two callers with two
different policies: the headless `TrainingStage` ("right after learning, once")
and the client `TrainingBloc` ("on every training-run completion"). Neither is
wrong, but "when does a technique evolve" is a gameplay rule with two
implementations and no shared definition, and `TechniqueEvolved` is published
from `game/` and from the client but never from the plugin that defines it.

**Why it matters:** As evolution gains inputs (V1 already threads a real
`TrainingProfile` from the minigame), the two triggers will drift in subtle
ways — e.g. one re-attempts evolution on a form that already evolved, the
other doesn't. A content pack author reading `technique_plugin.dart` has no
single place that says "this is the evolution lifecycle."

**Current ownership:** composition layers (two of them).
**Recommended ownership:** Technique plugin exposes one documented
`resolveEvolutionAfterTraining(character, technique, profile, context)` that
encapsulates the "has candidates? attempt? publish `TechniqueEvolved`?"
policy; both composition layers call it. The plugin publishes its own event.
**Recommended fix:** Add the wrapper to `technique_lifecycle.dart` /
`technique_evolution.dart`; move the `events.publish(TechniqueEvolved(...))`
into it; have `training_stage.dart` and the client bloc call it instead of
open-coding the sequence.
**Refactor risk:** Low. Additive; the existing `evolveTechnique` stays for
callers that want manual control. Covered by
`test/plugins/technique/technique_events_test.dart` (asserts one event per
evolution over 20 seeds).
**Related systems:** Technique, Training, the two composition layers, [A1].

---

### [A5] No serialization of gameplay / run / character state

**Category:** 19 (State Management), 20 (Serialization), 27 (Client Boundary),
29 (Data Integrity)
**Severity:** Medium (High as a *long-term-foundation* blocker)

**File:**
- `built_engine/lib/` — only 6 types implement `toJson`/`fromJson`:
  `CombatantComponent`, `CombatStateComponent`, `MartialLoadoutComponent`,
  `ContentRegistry`, `ContentDefinition`, `Container`.
- No serialization for: `ItemInstance` (incl. `itemClass`, `statBonuses`),
  `MasteryComponent` / `MasteryRecord`, `ProgressionState`, `DiscoveryState`,
  `PhysiqueComponent`, `TomeInstance` / `TomePlacement`, `StatComponent`,
  `TagSet`, `ResourceComponent`, `HealthComponent`, per-technique mastery
  axes, `spec:*` tags, or anything under `lib/src/plugins/game/`
  (`RunResult`, `DecisionLog`, telemetry events).
- `Tome_client_v1/lib/app/tome_app.dart` — rebuilds `EngineSession` from
  `RunState.sessionSeed` on every launch; persists only summary data
  (`records.v1`, `codex.v1`, `settings.v1`, `training_pace.v1`).

**Problem:** `claude.md`'s Serialization section requires save data to contain
"engine version, plugin versions, game state, entity state, component state,
RNG state." None of that exists. `ARCHITECTURE.md` lists Serialization under
"deliberately not here yet," so this is known scope — but the consequence is
now concrete: **a run cannot be saved and resumed.** The client's workaround
is to treat the seed as the save file and reconstruct the entire engine world
from scratch each session, replaying nothing. That works only because the
client also never lets a run span an app restart. `DecisionLog` (game layer)
is the one component built correctly for this — stable-id data, replayable —
but it is wired to nothing.

**Why it matters:** The prior audit noted this gap as "widening"; V1 widened it
further (`itemClass`, per-technique mastery, `spec:*` tags all unpersistable).
For an MVP it is tolerable. For "the long-term foundation for Tome and future
build-system plugins" it is the single largest missing subsystem, and every
month of new state added without a serialization contract makes the eventual
save format harder (there is no schema discipline forcing new fields to be
stable-id-addressable).

**Current ownership:** none.
**Recommended ownership:** a Core Serialization service (as `ARCHITECTURE.md`
anticipates), owning a `SaveDocument` with engine/plugin versions + a
component-registry-driven `toJson`/`fromJson` keyed by stable content ids and
`EntityId` sequence, plus RNG state capture from `RngService`.
**Recommended fix:** Not now, and not piecemeal. Design it as its own
subsystem before Content V2, starting from `DecisionLog`'s stable-id
discipline as the model. In the interim, add a lint/test that every new
component type either implements the (future) serialization interface or is
explicitly annotated run-local.
**Refactor risk:** High if attempted reactively; Low if designed once,
up-front. The danger is doing it wrong under deadline pressure.
**Related systems:** every stateful Core service, the plugin components, the
client's persistence layer, [A1].

---

### [A6] The content validator couples to `src/` private paths instead of public barrels

**Category:** 17 (Public API Boundary), 26 (Content Validation)
**Severity:** Medium

**File:**
- `built_engine/tool/validate_content.dart:10-17` — imports
  `src/plugins/game/enemy_content.dart`, `src/plugins/item/item_content.dart`,
  `src/plugins/martial_arts/{martial_item_content,martial_styles,martial_technique_content}.dart`,
  `src/plugins/physique/physique_content.dart`,
  `src/plugins/technique/{technique_content,technique_vocabulary}.dart`
- `built_engine/test/content/content_expansion_audit_test.dart:1-10` — same set

**Problem:** Every one of those symbols is already re-exported by a public
barrel: `techniqueContentDefinitions` / `TechniqueIds` via
`technique_plugin.dart`; `itemContentDefinitions` via `item_plugin.dart`;
`martialTechniqueContentDefinitions` / `martialItemContentDefinitions` /
`MartialStyles` via `martial_arts_plugin.dart`; `physiqueContentDefinitions`
via `physique_plugin.dart`; `enemyContentDefinitions` via `game.dart`. The
validator — the artifact whose whole purpose (per Category 26) is to be
"reusable, independent of test-only assumptions, suitable for CI and future
content packs" — reaches past those barrels into internal file layout. A file
rename inside any plugin breaks the validator; an external content pack could
not run the same checks without also depending on `src/`.

**Why it matters:** `claude.md`: "Plugins must not directly reach into another
plugin's private implementation. Use public contracts." The validator is not a
plugin, but it is precisely the cross-cutting consumer that should model the
public boundary. No `implementation_imports` lint fires because it is
in-package, which is exactly why this needs a human finding. (Root cause note:
this code was added in the same Content Expansion V1 pass that this audit
reviews — it is new debt, not inherited.)

**Current ownership:** `tool/` + `test/content/`.
**Recommended ownership:** unchanged location; change the imports to the public
barrels. If a needed constant is genuinely not exported (re-check: all six
appear to be), add it to the barrel rather than deep-importing.
**Recommended fix:** Swap the 8 `src/` imports for the 5 plugin barrels + the
`game.dart` barrel. Extract the shared check bodies into one
`lib/src/content/…` or a `tool/`-local library so the `test` and the `tool`
don't duplicate the logic (they currently do — ~120 lines restated).
**Refactor risk:** Very Low. Import-only change plus a small extraction; the
audit test's own assertions don't move.
**Related systems:** the public barrels, CI, future content-pack tooling.

---

### [A7] Content-definition files are large hand-authored data with linear factory boilerplate

**Category:** 6 (Content Architecture), 24 (Content Scale Readiness)
**Severity:** Low

**File:**
- `built_engine/lib/src/plugins/technique/technique_content.dart` — 553 lines, 41 forms in one `const` list
- `built_engine/lib/src/plugins/item/item_content.dart` — 663 lines, 43 forms in one `const` list
- `built_engine/lib/src/plugins/martial_arts/martial_technique_content.dart` — 460 lines: 18 data maps **plus 18 near-identical `MartialTechniqueAction xxx({actor, targets}) => _technique('xxx', ...)` convenience wrappers** (one per technique, added one-for-one in V1)

**Problem:** Content is data (good — `ContentRegistry`-loaded, no per-item
class), but it is a single growing Dart `const` list per type with no external
format and no sub-file organisation, and `martial_technique_content.dart`
carries a hand-written factory function per technique that scales strictly
1:1 with content count. At 41 techniques the files are readable; at 100–500
(the Content Scale target in the milestone brief) a single 2,000–6,000-line
`const` list and 500 factory wrappers become a genuine authoring and
review-diff problem, and merge conflicts on the one list become routine.

**Why it matters:** The engine is explicitly intended to become
"content-driven." The current shape works for the team hand-editing Dart; it
does not work for "content packs" (Category 26) or for non-engineers. The
factory wrappers in particular are pure boilerplate — `_technique('jab', …)`
etc. — that a single generic `martialTechnique(id, …)` call already subsumes
(the wrappers exist only for backward-compatible call sites).

**Current ownership:** each content plugin.
**Recommended ownership:** unchanged; change the shape when a second consumer
appears. Options, in increasing effort: (a) split the `const` list into
per-family files (`technique_content/punch.dart`, `…/palm.dart`, …) combined
in the plugin — mechanical, low risk; (b) deprecate the 18 per-technique
factory wrappers in favour of the generic `martialTechnique(id, …)` and remove
them once call sites migrate; (c) load content from bundled JSON/YAML assets
via the existing `ContentRegistry.loadAll` (it already takes
`List<Map<String,dynamic>>` — only the *source* would change).
**Recommended fix:** Do (a) + (b) before Content V2; defer (c) until an actual
external-pack requirement exists (YAGNI per `claude.md`).
**Refactor risk:** Low for (a)/(b) — no behaviour change, `ContentRegistry`
input is identical. The content audit test covers the whole roster.
**Related systems:** all content plugins, the validator [A6].

---

### [A8] `architecture_dependency_test.dart` has three coverage gaps

**Category:** 25 (Test Architecture)
**Severity:** Low

**File:** `built_engine/test/integration/architecture_dependency_test.dart`

**Problem:** The test is strong — it enumerates every Core subdirectory and
asserts none references `plugins/` or any plugin barrel, and it pins
Combat/Item/Technique/Physique isolation. Gaps: (1) it does not guard
`lib/src/plugins/build_interpretation/` (which legitimately depends on Item +
Technique + Combat, but nothing stops it gaining a MartialArts or Elemental
import); (2) it does not assert that **nothing** imports `game.dart` /
`lib/src/plugins/game/` — the "Game is top of the DAG" property is verified
only by prose in `ARCHITECTURE.md`; (3) it does not check the internal import
direction *within* `martial_arts/` or `game/` (e.g. a content file importing a
rules file).

**Why it matters:** The DAG-purity guarantee is one of this engine's best
properties and its enforcement is otherwise excellent; these three holes are
where a future regression could slip in unnoticed.

**Current ownership:** the test.
**Recommended ownership:** same.
**Recommended fix:** Add: a `build_interpretation` isolation group (may import
Item/Technique/Combat, must not import MartialArts/Elemental/Physique/Game); a
"no file outside `lib/src/plugins/game/` and `lib/game.dart` references
`game.dart` or `plugins/game/`" assertion; optionally a within-`martial_arts`
layering check.
**Refactor risk:** None (test-only, additive).
**Related systems:** CI, [A1] (the "nothing imports game" check would have made
[A1]'s divergence visible sooner).

---

### [INFO-1] `lib/src/reward/` imports `lib/src/tome/`

**Category:** 1 / 16
**Severity:** Info

`RewardCandidate.ref` reuses `BuildComponentRef` (a `tome/` value type). Core
module → Core module, no plugin boundary implicated. Carried over from both
prior audits, unchanged, still acceptable — noted only so it is not
re-discovered as new.

### [INFO-2] Engine `enemy_content.dart` is still the flat-stat pattern

**Category:** 6 / 24
**Severity:** Info

`built_engine/lib/src/plugins/game/enemy_content.dart` holds 5 enemies as
`{health, damage, damageStat, initiative}` with a linear `scaledEnemy` ramp —
the "HP 10 / 12 / 15" shape the client's V1 archetype model was built to
replace. It only feeds the headless sim, so it is not a shipped-content
problem, but it is dead-weight divergence and should be reconciled as part of
[A1].

### [INFO-3] `combine/` generic-naming finding from the prior audit is resolved

`CombineOutcome` is `{fail, tierUpgrade, branchUpgrade}` and
`CombineResolver` uses `atMaxTierForBranch` / `branchDefinition` etc.
Re-verified fixed; listed so it is not re-flagged.

---

## Content Architecture

**Can we add 10× more content without rewriting mechanics?**

| Content type | 10× ready? | Blocker |
|---|---|---|
| Items | **Yes** | none — data + `gradeEvolution` + validator; V1 added 13 forms with zero mechanic changes |
| Techniques | **Yes** | none — V1 tripled the roster (11 → 41) touching only `technique_content.dart` + vocab; tiers/dims/targets validated |
| Physiques | **Mostly** | data-driven, but no validator coverage (rarity/affinity/modifier shape unchecked) |
| Enemies | **No (as shipped)** | the real (client) enemy model is a Dart enum + `switch`, not content; the engine's is stale flat data. Needs [A1]. |
| Martial styles | **No** | 6 hand-maintained id-keyed structures, no validator, no `default`. Needs [A3]. |
| Rewards | **Partial** | client weighting is generic (style/physique/gap/novelty factors, no `if id ==`), but the pool is a hand-curated id list in two repos; no reward *content* type |
| Training exercises | **Yes** | `TrainingExercise` interface + `WeightedTrainingExercise`; the client's `TargetStrikeExercise` composes `PrecisionExercise` + `ReactionExercise` with zero engine change — the model works |
| Evolution candidates / training weights | **Yes** | fully content-driven (`evolution` / `training` fields), validated for target resolution + cycles + tier monotonicity |

**Net:** the two content types that are *not* 10×-ready (styles, enemies) are
exactly the two that are not `ContentRegistry` data. The pattern to fix both
already exists in-repo (`physiqueDefinitionFromContent` for styles;
`enemyDefinitionFromContent` for enemies — the latter just needs the client's
richer field set).

---

## Extensibility Review

1. **Add another martial style safely?** — *No, not safely.* Requires editing
   `MartialStyles`, `learnStyle`'s `switch`, `martialTraditionOf`,
   `stylesForTradition`, `MartialSpecs.byStyle`, `styleAlignedFamilies` (6
   files/structures), plus the client's `CombatAdapter` if the style needs a
   new `spec`. Nothing validates that the 6 agree. → **[A3]**.

2. **Add Magic as another plugin?** — *Yes, structurally.* Core has zero
   martial vocabulary; `combat_plugin.dart` / `build_interpretation.dart` are
   clean; the Elemental plugin already proves "a second content plugin with no
   dependency on the first." **Caveat:** the off-specialty / capability-vs-tag
   damage mechanism [A2] would have to be reinvented for Magic because it
   lives in the martial-arts-specific client code, not a generic Combat hook.

3. **Add 100 more techniques?** — *Yes.* Data + validator. The `const`-list
   file would hit ~1,500 lines and want a per-family split ([A7]), but no
   mechanic changes.

4. **Add 100 more items?** — *Yes.* Same as techniques; `item_content.dart`
   would want the split sooner (already 663 lines at 43 forms).

5. **Add another training exercise?** — *Yes.* Implement `TrainingExercise`;
   `WeightedTrainingExercise` and the content `trainingWeights` field do the
   rest. Proven by `TargetStrikeExercise`.

6. **Add another enemy archetype?** — *In the client, yes (add an enum case +
   `_base()` entry). In the engine, no* — there is no archetype concept, and
   the two enemy models are unrelated. → **[A1]**.

7. **Can the client consume all of this through public APIs?** — *Today, yes,
   but only because it reimplements the composition.* The client imports only
   barrels (no `src/`, no `implementation_imports`). But it consumes them by
   rebuilding combat/reward/training/enemy logic itself. A thinner client that
   *rendered* an engine-owned run would currently be impossible — the engine
   offers no run/session API at the fidelity the client needs (mastery-gated
   success rolls, archetype behaviour, style specialties, adaptive pacing).
   → **[A1]**, **[A2]**.

---

## Recommended Refactor Order

### Before more features

- **[A6]** Point the content validator at public barrels; de-duplicate its
  check bodies. (Very Low risk, ~1 hour, removes new debt immediately.)
- **[A8]** Close the three `architecture_dependency_test` gaps — especially
  "nothing imports `game.dart`". (No risk, test-only.)
- **[A4]** Add `Technique.resolveEvolutionAfterTraining(...)` and route both
  composition layers + the `TechniqueEvolved` publish through it. (Low risk,
  additive.)

### Before Content V2

- **[A1]** Decide the composition-ownership question and act on it. Recommended:
  relabel `lib/src/plugins/game/` as a balance/CI sim; extract the shared
  contracts (enemy archetype content type; a combat success/mastery/off-lane
  resolution hook) so the client builds on engine primitives instead of a
  bespoke `_Resolver`. This unblocks [A2] and [INFO-2].
- **[A2]** Add the generic "capability-set vs. action-tags → damage scalar +
  per-hit hooks" Combat contract; move the client's `offSpec` / Conditioning /
  Burst Chain onto it; MartialArts registers the policy from
  `styleAlignedFamilies` / `MartialSpecs`.
- **[A3]** Migrate styles to `styleContentDefinitions` +
  `StyleDefinition` (copy the `PhysiqueDefinition` pattern); collapse the 6
  structures into one data list; extend the validator to cross-check them.
- **[A7]** Split the content `const` lists per family; deprecate the 18
  per-technique factory wrappers.

### Before a public SDK / external clients

- **[A5]** Design and build the Core Serialization service (engine/plugin
  versions, stable-id component `toJson`/`fromJson`, `RngService` state, save
  migrations). Model it on `DecisionLog`. Do not build it reactively.
- **[A1]** cont'd — publish a stable "run/session" public API so a thin client
  is possible, and document which parts of `game/` are contract vs. sim.

### Later

- **[INFO-1]** `reward/`→`tome/` value dependency — leave unless a Core
  layering pass happens anyway.
- **[A7](c)** external JSON/YAML content assets — only when an actual content
  pack needs it.
- Physique validator coverage; within-plugin layering checks.

---

## Publisher / Production Readiness

**Is the engine architecture ready for continued MVP content production?**
**Yes.** Adding techniques, items, physiques and evolution/training data flows
through validated `ContentRegistry` data with no mechanic changes — Content
Expansion V1 is the proof (11 → 41 techniques, +13 item forms, one weekend,
suite stayed green). Core purity, the DAG, and RNG discipline are intact and
CI-enforced.

**Is it safe to expand techniques / items / enemies?**
- Techniques, items: **yes, safely** — data + validator.
- Enemies: **yes in the client, no in the engine** — the two models are
  unrelated; expand the client's, but know the engine's balance sim will not
  reflect it until [A1].
- Styles / style-scoped rules: **not safely** — [A3] + [A2].

**Top 3 architectural risks:**
1. **Two divergent game compositions ([A1]).** The engine's `game/` layer is
   an unshipped, stale approximation; the real rules live in the client and
   the engine cannot test them.
2. **Style-scoped combat rules have no engine owner ([A2]).** The
   off-specialty penalty and style specialties are implemented only in Flutter
   code — untestable by the engine, unusable by the sim, un-reusable by Magic.
3. **No gameplay-state serialization ([A5]).** A run cannot be saved; every
   month of new state added without a save contract raises the eventual cost.

**What should NOT be changed right now:**
- Core (`entity`, `component`, `event`, `query`, `rule`, `modifier`,
  `resource`, `rng`, `spatial`, `tome`, `evolution`, `mastery`, `progression`,
  `discovery`, `content`, `combine`, `character`) — it is clean across three
  audits; touching it risks the property that makes everything else possible.
- The plugin DAG and the barrels — do not add cross-plugin imports to "make
  something easier"; the isolation is load-bearing.
- `EvolutionResolver` / `CombineResolver` / `modifiersFromProperties` reuse —
  the generic-mechanism-plus-content-data pattern is working; keep copying it
  (it is the fix for [A3] and [INFO-2]).
- The client's generic `spec:*` / `styleAlignedFamilies` dispatch (no
  `if styleId ==`) — when [A2] moves this into the engine, preserve that
  shape.

**What must be fixed before the engine becomes the long-term foundation for
Tome and future build-system plugins:**
1. **Serialization ([A5])** — designed once, up-front, as its own subsystem.
2. **A single, documented composition contract ([A1])** — one place that
   defines "a run," whether that is engine-owned or an explicit engine/client
   split, with the shared gameplay primitives (enemy archetype, combat
   resolution hook, off-lane factor) extracted so they cannot diverge again.
3. **Styles as content ([A3])** and **style effects on a generic Combat hook
   ([A2])** — so the second build system (Magic) inherits the mechanism
   instead of reinventing it.

None of these is a Critical present-tense defect. All three are foundations
that get more expensive to lay the longer content production continues on top
of the current shape.
