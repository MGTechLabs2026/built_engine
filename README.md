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
      combat/        # Combat plugin
      auto_combat/   # AutoCombat plugin
      martial_arts/  # MartialArts plugin (-> combat)
      elemental/     # Elemental plugin (Core only)
      physique/      # Physique plugin (Core only)
test/
  ...            # unit tests, mirroring lib/'s layout
  integration/   # cross-service/cross-plugin integration tests,
                 # including the architecture dependency-governance suite
```
