# build_engine

A modular, data-driven game engine core, written in pure Dart.

The core provides generic verbs — entities, components, events, rules,
effects, modifiers, spatial containers, resources, progression, and a
plugin system — with no game-specific content of any kind. Game content
(martial arts, magic, cultivation, or anything else) lives entirely in
plugins built on top of this foundation, never in the core itself.

## Status

Core services implemented so far:

- **Entity/Component/Event** — `EntityId`, `EntityRegistry`,
  `ComponentStore`, `EventBus`: deterministic entity identity, generic
  per-type component storage, typed publish/subscribe.
- **Plugin system** — `GamePlugin`, `PluginContext`, `PluginManager`,
  `PluginSdk`: dependency-ordered lifecycle (register → initialize →
  start → stop → unregister), with a convenience façade for writing a
  plugin without touching Core directly.
- **Rule / Condition / Effect Engine** — composable, data-driven
  `Rule`s (trigger + conditions + effects) reacting to events; both
  `Condition` and `Effect` are plain interfaces plugins implement
  directly, no registry required.
- **Modifier Engine** — `base + modifiers = derived`, with a fixed
  add → multiply → override → min → max resolution pipeline.
- **Spatial/Container Engine** — a single generic `Container`
  (grid or named-slot) for placement, movement, and spatial queries —
  one abstraction for a future Backpack, Tome, Weapon Rack, or
  Equipment Board.
- **Query Engine** — composable entity predicates (`and`/`or`/`not`)
  over components, tags, resources, health, and status.
- **Content Registry** — the engine's data-driven Asset/Data Registry:
  load items/skills/spells/styles/trinkets/statuses (and the rules that
  reference them) from plain JSON-shaped data instead of one Dart class
  per piece of content.
- **RngService** — the sole sanctioned source of randomness; every
  system that needs randomness is seeded and injected, so a run is
  reproducible from its seed.
- **Character** — the generic run-state identity every character needs,
  independent of what plugins later attach to it.
- **Resource Engine** — generic named resource pools (get/set/add/
  subtract/clamp/canAfford/consume/restore), integrated with Condition/
  Effect.
- **Progression layer** and **Mastery system** — generic
  owner/subject/level/progress tracking for arbitrary progression
  subjects (item mastery, technique tier, a future cultivation
  breakthrough, ...) — no per-domain system classes.
- **Discovery system** — a generic unknown → discovered → unlocked
  tri-state for arbitrary content subjects.
- **Tome/Build system** — an active build configuration (not an
  inventory) built entirely on the Container abstraction:
  insert/remove/move/replace/inspect/validate/resolve, resolving into an
  `ActiveBuild` snapshot.
- **Training Framework** — a headless framework for interactive
  practice sessions, producing a `TrainingProfile` of generic
  performance dimensions (speed, power, precision, reaction, ...) via a
  pluggable `TrainingExercise` interface.
- **Evolution System** — resolves a branching `EvolutionDefinition`'s
  candidates into an `EvolutionResult`, weighted by a `TrainingProfile`
  through the real Modifier Engine, gated by real `Condition`s.
- **Reward/Loot system** — generic weighted-candidate reward
  generation, referencing arbitrary content IDs (item, technique,
  currency, consumable, trinket, ...).

Plugins built on top of Core (each depending only on Core, or on Combat
where noted):

- **Combat** — turn-based battle orchestration (turns, actions, damage,
  healing, defeat) with zero martial-arts/magic/weapon vocabulary.
- **AutoCombat** — a separate layer on top of Combat deciding *what
  action to perform* each turn, without any change to `CombatSystem`
  itself; content-agnostic, deterministic, deliberately simple policy.
- **MartialArts** *(depends on Combat)* — styles, techniques, stances,
  items, and trinkets, the first plugin proving `MartialArts -> Combat
  -> Core`.
- **Elemental** *(Core only)* — Fire/Water/Lightning affinities and
  spells, the reference example for writing a third-party plugin.
- **Physique** *(Core only)* — character body types with cross-plugin
  synergy via shared tags, with zero import coupling to MartialArts.
- **Item** *(Core only)* — the real item lifecycle (unknown →
  discovered → locked → usable → placed in a Tome), built entirely on
  Discovery/Mastery/Tome, with zero item-specific vocabulary in Core.
- **Technique** *(Core only)* — the real technique lifecycle (discover
  → learning → learned → evolve), built on Discovery/Progression/the
  Evolution System, independent of Item and MartialArts.

On top of those, two composition layers combine multiple plugins
without modifying any of them:

- **Build Interpretation** *(depends on Technique, Item, Combat)* — the
  bridging layer between a resolved Tome (`ActiveBuild`) and Combat
  (`CombatAction`), the same "separate layer" positioning `AutoCombat`
  already established for Combat itself.
- **Game** *(depends on Physique, MartialArts, Item, Technique,
  Training, Tome, Build Interpretation, AutoCombat, Combat)* — the
  first real headless game run: `runGame(seed, {policy, eventBus})`
  composes every plugin above into one deterministic ~10–15 minute run
  (encounters, elites, a boss, reward/training/Tome decisions). Also
  provides the tooling for the first human playtest: 10 new telemetry
  events on the existing `EventBus` (observable live via the optional
  `eventBus` parameter), a `DecisionLog` +
  `RecordingDecisionPolicy`/`ReplayDecisionPolicy` pair so a seed and
  its recorded decisions reproduce the exact same run, a per-run
  `formatPlaytestReport`, and cross-seed `BalanceSignals`. See
  `tool/game_run_report.dart` for a runnable multi-seed report.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for how every implemented
service and plugin fits together and why, [`PLUGIN_SYSTEM.md`](PLUGIN_SYSTEM.md)
for the plugin lifecycle and dependency-resolution details, and
[`ARCHITECTURE_AUDIT.md`](ARCHITECTURE_AUDIT.md) for the latest
architecture-contract compliance audit. The full architecture contract
this engine follows lives in [`claude.md`](claude.md).

## Requirements

- Dart SDK `^3.7.0`

This is a pure Dart package — it has no Flutter dependency, so it can be
tested and used headlessly.

## Getting started

```bash
dart pub get
dart test
dart analyze
```

## Package layout

```
lib/
  build_engine.dart         # Core public API barrel export
  combat_plugin.dart        # Combat plugin barrel
  auto_combat_plugin.dart   # AutoCombat plugin barrel
  martial_arts_plugin.dart  # MartialArts plugin barrel
  elemental_plugin.dart     # Elemental plugin barrel
  physique_plugin.dart      # Physique plugin barrel
  item_plugin.dart          # Item plugin barrel
  technique_plugin.dart     # Technique plugin barrel
  build_interpretation.dart # Build Interpretation layer barrel
  game.dart                 # Game composition layer barrel
  src/
    entity/       # EntityId, EntityRegistry
    component/     # ComponentStore
    components/    # Health/Resource/Stat/Status/Mastery/Discovery
                    # components, TagSet
    event/         # EventBus
    rule/          # Condition, Effect, Rule, RuleEngine, RuleContext,
                    # system_conditions, system_effects
    modifier/      # Modifier, ModifierCollection, ModifierResolver
    spatial/       # Container, Slot, PlacementRule, ...
    query/         # Query, QueryEngine, generic queries
    content/       # ContentRegistry, ContentDefinition
    rng/           # RngService, weightedPick
    plugin/        # GamePlugin, PluginContext, PluginManager, PluginSdk
    character/     # Character State layer
    resource/      # Resource Engine
    progression/   # Progression layer
    mastery/       # Mastery system
    discovery/     # Discovery system
    tome/          # Tome/Build system
    training/      # Training Framework
    evolution/     # Evolution System
    reward/        # Reward/Loot system
    plugins/
      combat/                # Combat plugin
      auto_combat/           # AutoCombat plugin
      martial_arts/          # MartialArts plugin (-> combat)
      elemental/             # Elemental plugin (Core only)
      physique/              # Physique plugin (Core only)
      item/                  # Item plugin (Core only)
      technique/             # Technique plugin (Core only)
      build_interpretation/  # Build -> Action bridging layer
      game/                  # Game composition layer: runGame, telemetry,
                              # decision log, playtest report, balance signals
test/
  ...            # unit tests, mirroring lib/'s layout
  game/          # tests for the runGame composition layer, telemetry,
                 # decision-log replay, multi-seed diversity, playtest report
  integration/   # cross-service/cross-plugin integration tests,
                 # including the architecture dependency-governance suite
tool/
  vertical_slice_report.dart # multi-seed report for the vertical-slice proof
  game_run_report.dart       # multi-seed playtest report for runGame
```
