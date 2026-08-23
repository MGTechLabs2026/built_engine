# Build Engine — Architecture

This document describes the engine foundation implemented so far. See
`claude.md` for the full architecture contract this engine follows, and
`PLUGIN_SYSTEM.md` for the plugin lifecycle in detail.

## Core Principle

The core provides generic verbs (create an entity, attach a component,
publish/subscribe to an event, register a plugin). It has no knowledge of
any specific game content — no martial arts, no magic, no combat. All of
that belongs in plugins, built on top of this foundation, in later work.

## Services implemented so far

### EntityId (`lib/src/entity/entity_id.dart`)
An immutable value wrapping a sequential `int`, assigned in creation order.
Sequential (not random) so a run can be reproduced from seed + initial
state + actions.

### EntityRegistry (`lib/src/entity/entity_registry.dart`)
Tracks which `EntityId`s are currently alive. `create()` allocates a new id
and publishes `EntityCreated`; `destroy(id)` removes it and publishes
`EntityDestroyed`. Takes an `EventBus` via constructor injection — there is
no global/singleton event bus.

### ComponentStore (`lib/src/component/component_store.dart`)
Generic storage for components, keyed by the component's runtime `Type`.
Deliberately has **no reference to `EntityRegistry` or `EventBus`** — it is
independently constructible and testable. This is a boundary worth keeping:
it means you can reason about "how components are stored" completely
separately from "how entities are created and destroyed".

### EventBus (`lib/src/event/event_bus.dart`)
Typed publish/subscribe. `subscribe<T>(handler)` registers a handler for
events whose exact runtime type is `T`; `publish<T>(event)` dispatches to
every such handler. There is no dispatch across a type hierarchy (a
subscriber for a supertype will not receive a subtype's events) — every
event type used so far is a concrete, non-hierarchical class, so this has
not been a limitation. Revisit if a future plugin needs otherwise.
`subscribeDynamic(Type, handler)` also exists, for callers that only know
the event type at runtime rather than at compile time (e.g. `RuleEngine`
dispatching on a `Rule.trigger` value read from data).

### Plugin system (`lib/src/plugin/`)
`GamePlugin`, `PluginContext`, and `PluginManager` — see `PLUGIN_SYSTEM.md`
for the full lifecycle, dependency-resolution algorithm, and exception
types. In brief: `PluginManager` topologically sorts registered plugins by
their declared `dependencies` and drives `register`/`initialize`/`start`
(forward, dependency order) and `stop`/`unregister` (reverse order).

### Supporting components (`lib/src/components/`)
`TagSet`, `HealthComponent`, `ResourceComponent`, `StatComponent`,
`StatusComponent` — plain immutable value objects stored via
`ComponentStore`, no game-specific defaults. `StatComponent` is a
stopgap: it's a raw value store until the Modifier Engine adds
proper `base + modifiers = derived` stat computation; `ModifyStat`
mutates it directly for now.

### RngService (`lib/src/rng/rng_service.dart`)
The only place `dart:math`'s `Random` is allowed to appear in this
package. Seeded and injectable — gameplay code asks `RngService` for
randomness, never `dart:math` directly, so a run stays reproducible from
its seed.

### EventCounter (`lib/src/rule/event_counter.dart`)
Tallies published-event counts per `Type`, but only for types explicitly
`trackType`-registered — there is no retroactive counting. `RuleEngine`
auto-tracks whatever type an `EventCount` condition names, at the moment
the owning rule is registered.

### Query Engine (`lib/src/query/`)
`Query` is a composable predicate over a single entity (`and`/`or`/`not`
combinators plus six concrete queries: `HasComponentQuery`, `HasTagQuery`,
`ResourceAboveQuery`, `ResourceBelowQuery`, `HealthBelowQuery`,
`StatusActiveQuery`). `QueryEngine.evaluate(candidates, query)` finds
every matching entity in a candidate set (typically `EntityRegistry.all`)
— independently useful without any Rule involved.

### Condition / Rule / Effect Engine (`lib/src/rule/`)
`Condition` and `Effect` are public interfaces — plugins implement them
directly, compose `Rule` objects (`trigger`, `subjectOf`, `conditions`,
`effects`) in code, and hand them to `RuleEngine.register`. The six
entity-scoped conditions (`HasTag`, `HasComponent`, `ResourceAbove`,
`ResourceBelow`, `HealthBelow`, `StatusActive`) delegate to the matching
`Query`; `EventCount` and `RandomChance` are not entity queries and
implement `Condition` directly. `RuleEngine` subscribes each rule via
`EventBus.subscribeDynamic` (dispatch on a `Type` known only at runtime),
evaluates every condition (AND) in list order, and runs every effect (in
list order) only if they all pass — no other source of nondeterminism
beyond whatever `RngService` itself produces. There is no registry:
plugins register their own conditions/effects simply by implementing the
public `Condition`/`Effect` interfaces, the same way `GamePlugin` already
is public.

### Modifier Engine (`lib/src/modifier/`)
`Modifier` (`source`, `target`, `stat`, `operation`, `value`, `priority`,
`duration`, `condition` — matching claude.md's MODIFIER SYSTEM field list
exactly) is a plain immutable value; `ModifierSource` is a small string-id
wrapper used for bulk removal, not tied to `EntityId`. `ModifierCollection`
is the single repository of every registered modifier across every entity
and stat (not per-entity) — `add`, `removeBySource`, and
`activeModifiersFor(target, stat, components)` (filtering by target+stat,
expiry, and `condition`, in registration order). `condition` reuses the
existing `Query` system rather than a new predicate type, since a
conditional modifier is a continuous "is this entity in state X" check, not
an event-triggered `Rule` condition. `tick()` is the only mechanism for
temporary modifiers — decrements durations, drops expired ones; no
Scheduler exists yet, so callers invoke it directly.

`ModifierResolver` is a pure function (`resolve(base, modifiers)`) with no
storage dependency, implementing a fixed, documented pipeline:

```
base -> ADD (sum) -> MULTIPLY (product) -> OVERRIDE (highest priority wins)
     -> MIN (ceiling) -> MAX (floor) -> final value
```

`priority` only orders modifiers within their own operation group — it
never changes this macro order. MIN/MAX stacking is order-independent
(`math.min`/`math.max` are associative); only the MIN-before-MAX group
ordering is a fixed, documented convention (relevant only for
contradictory content where a ceiling is below a floor). Ties within a
group (equal priority) break by each modifier's position in the input
iterable — `ModifierResolver` runs its own explicit stable sort rather
than relying on `List.sort`'s unspecified stability, and
`ModifierCollection` naturally hands back modifiers in registration
order, so the whole pipeline is deterministic without any extra
sequence-number field on `Modifier` itself.

`StatComponent`'s "stopgap" status (see above) is unchanged by this pass:
the Modifier Engine now exists, but rewiring the already-shipped
`ModifyStat` effect to route through it is a deliberate, separate design
decision for a future pass, not a mechanical follow-on to this one.

### Spatial/Container Engine (`lib/src/spatial/`)
`Container` is a single class with two factory constructors, not a
`GridContainer`/`SlotContainer` subclass split: `Container.grid(width,
height)` generates one `Slot` per cell with a derived `SlotId` and a
non-null `Position`; `Container.namedSlots(ids)` generates one `Slot` per
given id with `position: null`. Both are the same underlying structure —
a future Backpack, Tome, Weapon Rack, or Equipment Board plugin is just a
different factory call plus its own content, with zero
container-shape-specific code anywhere in this module.

9 of the 11 queryable relationships CLAUDE.md's SPATIAL/CONTAINER SYSTEM
section lists split by their actual mathematical shape rather than one
artificial interface: `Above`/`Below`/`Left`/`Right`/`Adjacent`/
`SameRow`/`SameColumn` are boolean `SpatialRelation`s between two
`Position`s (row 0 is the top; `Adjacent` is orthogonal only, no
diagonals); `distance` is a plain top-level Manhattan-distance function,
not a `SpatialRelation`; `ContainedBy` is entity-container membership —
`Container.contains(EntityId)` — not a relation between two positions.
Of the remaining two, `EquippedTo` is expressible as membership in a
named slot (`Container.namedSlots(['weapon', ...])` + `Container.contains`)
rather than a distinct query, and `ConnectedTo` (socket/connection
graphs) is a deliberately deferred future pass, not implemented by this
module.
`Container.relatesTo(relation, a, b)` looks up each item's anchor
position — never its full multi-cell footprint — and returns `false`
(not a crash) if either item lacks a position, so asking about adjacency
on a named-slot container is well-defined.

`ItemSize` + `Rotation` model only an axis-aligned bounding box — a
rotation swaps width/height at 90°/270°, no per-cell/Tetris-style
footprints. Placement validation runs through `PlacementRule`
(`WithinBounds`, `NoCollision`, matching the `Condition`/`Effect`
no-registry pattern), always AND'd with any caller-supplied extra rules —
the plugin extension point for content-specific placement constraints.
`PlacementRule.isSatisfied` takes a minimal `ContainerView` interface
(`hasSlot`/`itemAt`), not the concrete `Container` — this is what lets
`placement_rule.dart` have zero dependency on `container.dart`, avoiding
a circular dependency (`Container implements ContainerView`) rather than
needing any forward-reference workaround. `place`/`move` throw
`InvalidPlacementException` carrying the failing rule(s); `canPlace`
never throws. `move` validates the new placement before clearing the
item's old footprint, so moving an item to overlap its own current
position succeeds correctly, and a rejected move leaves the item
unchanged (atomic — no partial mutation).

`Container.toJson()`/`Container.fromJson()` are a self-contained
capability of this module only — a plain, stable-ID-based structure
(slots + placements) — not an integration point for the engine-wide
Serialization service `claude.md` describes (engine version, RNG state,
etc.), which remains a separate future pass.

**Later addendum (Tome pass):** `placedItems`, `anchorOf(item)`,
`sizeOf(item)`, `rotationOf(item)` were added — small, generic,
purely-additive getters (no existing method's signature changed)
mirroring `positionOf`'s exact shape, filling a real gap: nothing
previously let a caller enumerate every current placement or read back
what an item was placed with. Needed for the Tome/Build system's
`inspect` operation, but not Tome-specific — any future `Container`
consumer wanting an inventory-style listing needs the same capability.

## Tome/Build system (`lib/src/tome/`)

The first real consumer of `Container` beyond its own tests, proving
`claude.md`'s own worked example (Backpack, Tome, Weapon Rack, Equipment
Board are "just a different factory call plus its own content") true —
`TomeDefinition` builds directly on `Container.grid`/`Container
.namedSlots`, no `TomeGrid`/`BackpackGrid` subclass anywhere.

**The Tome is not an inventory — it's an active build configuration.**
`Tome -> placements -> build resolution -> ActiveBuild -> Combat` is a
one-way data flow, not an import dependency: Combat never inspects a
Tome directly, it only ever consumes the `ActiveBuild` snapshot handed to
it, and (being Core) `lib/src/tome/` structurally cannot import any
plugin at all — `test/integration/architecture_dependency_test.dart`'s
group H already enumerates every Core directory dynamically, so
`lib/src/tome` was automatically covered by the existing "Core doesn't
import content plugins" governance check the moment the directory
existed, with zero new test code needed.

**What a Tome slot holds.** `BuildComponentRef {referenceType,
contentId}` is an opaque reference — `'item'`/`'iron_sword'`,
`'technique'`/`'jab'`, `'modifier'`/`'ember_charm_mod'`,
`'tag'`/`'martial'` — Core never interprets either field, the same
opacity `ContentDefinition.type` already has. It doubles as its own ECS
component (no redundant wrapper): `TomeService.insert` creates a fresh
throwaway `EntityId` for each placement, attaches the `BuildComponentRef`
to it, and hands that id to `Container.place` — `Container` tracks only
*where* that placeholder sits, never what it means, exactly as
`Container`'s own docs already promise. There is deliberately no
`TomeSlot` class: a Tome's slot vocabulary is `Slot`/`SlotId` from
`lib/src/spatial/`, reused directly rather than duplicated under a new
name.

**Definition vs. instance.** `TomeDefinition` (`id`, a
`Container Function()` closure built via `Container.grid`/`.namedSlots`,
and `extraPlacementRules: List<PlacementRule>` — the same extension point
`Container` already offers) is registered once via
`TomeService.defineTome`, shape-only, no owner. `TomeInstance`
(`definitionId`, `container`) is the per-owner live state,
`ComponentStore`-attached exactly like any other component — lives under
`lib/src/tome/` rather than `lib/src/components/`, the same placement
choice `CharacterComponent` made for the same reason (it's this
subsystem's own vocabulary, not one of the generic cross-cutting base
components).

**`TomeService`** (constructed from `entities`+`components` only — no
`events`, since this pass deliberately adds no event vocabulary; not
requested, and easy to add later without a breaking change) provides the
full requested operation set:

- `defineTome`/`createTome`/`tomeOf`
- `validate` — pure `Container.canPlace` check, using a private
  sentinel `EntityId(-1)` as the placement-preview identity (`Entity
  Registry` only ever allocates positive, sequential ids, so `-1` can
  never collide with a real entity) — never mutates, never throws, safe
  to call repeatedly for a UI placement preview.
- `insert` — creates the placeholder entity, attempts `container.place`;
  on `InvalidPlacementException` the placeholder is destroyed and its
  component removed before rethrowing, so a failed insert leaves nothing
  behind. Throws `StateError` if the owner has no Tome at all (a
  genuinely different situation from "nothing to act on" — there is no
  valid interpretation of inserting into a Tome that was never created).
- `remove` — removes from `Container` *and* destroys the placeholder
  entity, full symmetric cleanup; safe because `TomeService` is the sole
  owner of these placeholder entities end to end, the same reasoning
  `CharacterService`'s self-cleanup already established. A no-op (not a
  throw) for an empty slot or a missing Tome, mirroring `Container
  .remove`'s own permissive convention.
- `move` — re-reads the existing placement's size/rotation via the new
  `Container` getters so a move never silently reverts to a default 1x1
  footprint; `Container.move`'s own atomicity (unchanged on failure)
  carries through unchanged.
- `replace` — implemented as `remove` then `insert`, reusing both
  directly rather than a third mutation path; preserves the prior
  occupant's size/rotation if there was one.
- `inspect` — the full `List<TomePlacement>` (`slot`, `buildComponentRef`,
  `size`, `rotation`) for an owner, built from the new `Container`
  getters plus each placeholder's attached `BuildComponentRef`.
- `resolve` — `BuildResolver.resolve(owner, inspect(owner))`.

**`BuildResolver`** is a pure function with no storage dependency,
mirroring `ModifierResolver`'s existing "pure function, no state" shape
exactly — calling it twice with the same placements (same order) always
yields the same `ActiveBuild`, so build resolution is deterministic for
free; no `RngService` involved anywhere in this module. **`ActiveBuild`**
(`owner`, `components: List<BuildComponentRef>`) deliberately discards
slot/size/rotation — spatial layout is a Tome/UI concern, `ActiveBuild`
only carries *what* is active, which is all Combat (or anything else)
should ever need to consume.

**Wiring.** `TomeService` is reachable only via `PluginContext.tome` — it
was *not* threaded through `RuleContext`/`RuleEngine`, unlike every
service added in the Resource/Progression/Mastery/Discovery passes,
because this pass requested no Condition/Effect integration at all. A
plain optional `tome` parameter defaulting to a fresh `TomeService` was
enough; no factory-constructor sharing subtlety was needed (`TomeService`
depends on nothing else already defaulted, and nothing else depends on
it).

Deliberately not here yet: any event vocabulary (`TomePlacementChanged`
and similar were considered and dropped — not requested, and CLAUDE.md's
IMPLEMENTATION STYLE section warns against speculative abstractions) and
any automatic cleanup of a Tome (or its placeholder entities) on the
owner's `EntityDestroyed` — the general documented convention, left as
the caller's responsibility, the same choice already made for
`ResourceComponent`/`ProgressionComponent`(-now-removed)/`MasteryComponent`/
`DiscoveryComponent`.

## Integrating EntityRegistry and ComponentStore

Because `ComponentStore` does not know about `EntityRegistry`, component
cleanup on entity destruction is not automatic. Wire them together by
subscribing to `EntityDestroyed`:

```dart
final events = EventBus();
final registry = EntityRegistry(events);
final components = ComponentStore();

events.subscribe<EntityDestroyed>((event) {
  // Call components.remove<T>(event.id) for every component type your
  // application actually uses — ComponentStore has no registry of "every
  // type that has ever been added", so this list is the caller's to know.
  components.remove<SomeComponentType>(event.id);
});
```

This is also the pattern for bootstrapping the seven core services together
for a `PluginContext` — construct one `EventBus`, pass the same instance to
`EntityRegistry`, `RuleEngine`, and the `PluginContext`, so plugins that
subscribe via `context.events` actually see entity lifecycle events:

```dart
final events = EventBus();
final entities = EntityRegistry(events);
final components = ComponentStore();
final rng = RngService(1);
final resources = ResourcePool(components: components, events: events);
final mastery = MasteryTracker(components: components, events: events);
final progression = ProgressionEngine(
  components: components,
  events: events,
  mastery: mastery, // must be the same instance as `mastery` below
);
final discovery = DiscoveryTracker(components: components, events: events);
final context = PluginContext(
  entities: entities,
  components: components,
  events: events,
  rng: rng,
  rules: RuleEngine(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    resources: resources,
    mastery: mastery,
    progression: progression,
    discovery: discovery,
  ),
  queries: QueryEngine(QueryScope(components: components)),
  modifiers: ModifierCollection(),
  resources: resources,
  mastery: mastery,
  progression: progression,
  discovery: discovery,
);
```

Constructing `resources`/`mastery`/`progression`/`discovery` once and
passing the same instances to both `RuleEngine` and `PluginContext`
matters — see the Resource Engine section above for why relying on
each's own default would silently give you two independent pools/
engines, and the Progression section for why `progression` specifically
must be built with the *same* `mastery` instance too.

## Dependency rule

Plugins depend on core; core never depends on any plugin. Within core,
services depend only downward toward more primitive services — for
example `EntityRegistry` depends on `EventBus`, never the reverse. See
`PLUGIN_SYSTEM.md` for how this applies across plugins.

## Determinism

`EntityId` allocation is sequential, not random, specifically so that a
run's entity ids are reproducible given the same sequence of `create()`
calls. All randomness is centralized in `RngService` (see above) — gameplay
code asks it for random values, never `dart:math`'s `Random()` directly, so
a run stays reproducible from its seed plus initial state plus actions.

## What's deliberately not here yet

A dedicated Resource Engine *service* (this pass added only the
`ResourceComponent` data shape), Scheduler, Asset/Data Registry,
Serialization, and any registry/factory/data-driven rule deserialization
mechanism. Each is a separate future subsystem, to be brainstormed and
planned on its own rather than stubbed out speculatively here.

## Combat — the first plugin (`lib/src/plugins/combat/`, `lib/combat_plugin.dart`)

Combat is the first real `GamePlugin` built on this engine — proof that
the core/plugin boundary CLAUDE.md describes actually holds. It lives in
the same package (no workspace/multi-package tooling exists yet) but
imports core exclusively through `package:build_engine/build_engine.dart`,
never `lib/src/...` directly, and is exported through its own barrel,
`lib/combat_plugin.dart`.

`CombatantComponent` (`team`, `initiative`) and `CombatStateComponent`
(`participants`, `currentTurnIndex`, `round`, `active` — attached to a
dedicated battle entity, not to a participant) are the only new component
types. `CombatAction` is abstract, mirroring `Condition`/`Effect`'s
"implement directly, no registry" pattern; `AttackAction` is the one
concrete implementation, resolving its damage through the Modifier Engine
(`ModifierResolver().resolve(baseDamage, ...)`) before delegating to the
existing core `Damage` effect. "Healing" needed no dedicated action class
— any `CombatAction` whose `effectsFor` returns a `Heal` runs through the
identical pipeline.

`CombatSystem.executeAction` validates turn order (throwing
`IllegalActionException` on caller misuse), evaluates an action's
`Condition`s via a manually-built `RuleContext` (the same public type
`RuleEngine` itself uses — no new machinery), and applies its
`Effect`s the same way. Team-elimination (defeat/win/loss) is checked via
`QueryEngine` once per `executeAction` call — not once per individual
`EntityKilled` — because a single action can kill members of multiple
teams at once; checking per-kill would let an early check run before a
simultaneous second kill has landed, misjudging a mutual kill as a normal
win. A kill from outside `executeAction` (e.g. a future plugin's
independent rule) is still checked immediately, since by construction it
isn't part of any such batch.

This pass also grew `PluginContext` to expose `rng`/`rules`/`queries`/
`modifiers` (previously entities/components/events only) — the four core
services that existed but weren't yet reachable from a plugin's lifecycle
methods. `RuleContext`/`RuleEngine` were deliberately left unchanged; an
earlier version of this design routed `AttackAction`'s modifier
resolution through a `RuleContext`-carried `ModifierCollection`, which
would have cascaded into extending `RuleEngine`'s constructor too — the
final design resolves modifiers directly against `PluginContext` instead,
inside `CombatAction.effectsFor`, avoiding that cascade entirely.

## MartialArts — the first content plugin (`lib/src/plugins/martial_arts/`, `lib/martial_arts_plugin.dart`)

MartialArts is the first plugin to depend on another plugin
(`dependencies => ['combat']`, per `claude.md`'s `MartialArts -> Combat ->
Core`) rather than sitting directly on Core, and the first proof that a
content plugin can add cross-entity combat behavior without Combat
exposing anything new. Two mechanics needed a genuine design decision:
Shaolin's damage mitigation and Tai Chi's counter both sound like they
need to intercept an incoming attack, but `AttackAction`/`Damage` only
resolve the *attacker's* modifiers and `EntityDamaged` carries no attacker
reference — closing either gap would mean editing Combat. Instead both
react to Combat's already-public events: Shaolin's mitigation is a `Rule`
on `EntityDamaged` (a heal-back, not a block), and Tai Chi's counter is a
`Rule` on `ActionCompleted` (which always carries `actor` *and* `targets`,
letting a custom `Condition` — `TaiChiCounterCondition` — redirect damage
onto whoever the attacker was, even a plain core `AttackAction` from a
martial-arts-unaware entity). Boxing's momentum generation needed neither:
it's a flat `costEffects: [ModifyResource('momentum', +N)]` on the
attacking technique itself.

Styles (`boxing`/`shaolin`/`taiChi`) are marker tags, not components,
granted by `learnStyle` — which also, for Shaolin specifically, registers
a permanent conditional `Modifier` (`condition: HasTagQuery('stance:iron_body')`)
that lets a defensive stance boost offense purely through the Modifier
Engine. One `MartialTechniqueAction extends CombatAction` class (mirroring
`AttackAction`) covers all 6 techniques and 3 stances via data; one
`MartialItemDefinition` class covers all 5 items and 3 trinkets — trinkets
are simply the items whose behavior comes from a `Rule` reacting to their
`equipped:<id>` tag rather than a static `Modifier`.

`MartialArtsPlugin` never holds a reference to `CombatPlugin`/
`CombatSystem` — only to Combat's event *vocabulary*, reached through the
shared `RuleEngine` every plugin gets via `PluginContext`. It captures
every `EventSubscription` its 4 rules return at `initialize` and cancels
them all at `unregister`, mirroring `CombatPlugin`'s own teardown — proven
by an integration test that unregisters `MartialArtsPlugin` mid-session
and confirms Combat keeps running normally and MartialArts' rules stop
firing.

**Later addendum (`martial_technique_content.dart`):** an architecture
audit (`ARCHITECTURE_AUDIT.md`) flagged the 9 techniques/stances above as
hardcoded Dart, since `ContentRegistry` postdates this plugin. They were
migrated to data — `martialTechniqueContentDefinitions`, loaded into the
real `PluginContext.content` via `PluginSdk.registerContentBatch` in
`MartialArtsPlugin.initialize`, exactly like `ElementalPlugin`'s
spells. `MartialTechniqueAction` itself stayed hand-written Dart — it
has to, since resolving `baseDamage` against the actor's *current*
modifiers at execution time isn't expressible as a static, load-time
`Effect` list. The one design trick: a technique's `effects` list means
"what this does to its actor" for *either* shape — for an attack
technique that becomes `costEffects` (paid once before the damage
lands); for a stance (no `baseDamage`) it becomes `selfEffects` instead
(the point of a self-targeted technique) — see
`martialTechniqueFromDefinition`. This needed zero `ContentRegistry`
changes. The 9 original factory functions (`jab()`, `powerCross()`, ...)
keep their exact call shape for backward compatibility — each parses
`martialTechniqueContentDefinitions` through a fresh, throwaway
`ContentRegistry` on every call rather than a persistent module-level
one, deliberately: a persistent private registry would be exactly the
singleton pattern this same audit checked the engine for and confirmed
absent everywhere else.

The 8 items/trinkets (`martial_item.dart`) were **not** migrated — their
payload is `Modifier` objects (`operation`/`priority`/`duration`/
`condition`), which isn't part of `ContentRegistry`'s vocabulary at all.
Migrating them would mean either extending Core with a new "modifier
factory" concept or a meaningfully riskier plugin-local JSON→`Modifier`
parser; left for a future, separately-designed pass.

## Character — the generic run-state identity (`lib/src/character/`)

`CharacterComponent` is deliberately empty — no name, no seed, no stats.
Its presence on an entity *is* the identity signal; anything queryable
about "is this a character" goes through the existing generic
`HasComponentQuery<CharacterComponent>()`, no new query type needed. This
follows `TagSet`'s own minimalism and avoids inventing identity vocabulary
(a name, a seed) that later plugins may want to shape differently — a
`Player`/`Hero`/`Fighter`-style class would violate `claude.md`'s entity
model outright, and even a bespoke identity component would be more than
the engine currently needs.

`CharacterService` is Core, not a plugin — the same precedent
`Container`/`ContentRegistry` already set (both are Core modules despite
`claude.md`'s plugin-type table naming "Container" as infrastructure),
because every future content plugin this pass anticipates (Physique,
resources, item mastery, learned techniques, Tome, progression, combat
state) depends on Character, not the other way around. `create()` calls
`EntityRegistry.create()` (sequential, deterministic — no `RngService`
involved, since nothing about a bare character's identity is random) and
publishes `CharacterCreated`, mirroring `EntityCreated`/`EntityDestroyed`'s
shape exactly.

Unlike the general `ComponentStore` cleanup convention documented above
(each caller subscribes to `EntityDestroyed` for the component types it
knows about), `CharacterService`'s constructor subscribes to
`EntityDestroyed` itself and removes `CharacterComponent` automatically —
safe here specifically because one Core service owns this one Core
component end-to-end, unlike `TagSet` or other components multiple
plugins might independently touch.

`PluginContext` grew a `characters` field (`CharacterService`), defaulted
in the constructor's initializer list to a fresh `CharacterService` built
from the same `entities`/`components`/`events` already passed in, when the
caller doesn't supply one explicitly — so none of the existing call sites
that construct `PluginContext` directly needed to change. This is also why
`PluginContext`'s constructor is no longer `const`: the default expression
constructs a real object, and no call site actually invoked it with the
`const` keyword to begin with.

Deliberately not here yet: items, techniques, Tome, training, and any
martial-arts vocabulary — those are separate future passes, each needing
its own component(s) attached to the same character entity, exactly the
way `PhysiqueComponent`/`ElementalAffinityComponent` already attach onto
whatever entity holds them.

## Resource Engine (`lib/src/resource/`)

`ResourceComponent` keeps its exact pre-existing shape — `Map<String,
num>` of current values only, no "maximum" field added — per the explicit
instruction that state stays state and a service gets built around it.
"Maximum" instead lives in `ResourceDefinition` (`id`, `min = 0`, `max`),
registered separately via `ResourcePool.define` and never stored
per-entity; `ResourceState` (`current`, `max`) is the read-model
`ResourcePool.stateOf` computes on demand by combining a
`ResourceComponent`'s value with a registered `ResourceDefinition`'s
bounds — it is not a storage format either. This kept the change to
`ResourceComponent`, `ResourceAboveQuery`/`ResourceBelowQuery`, and the
existing `ResourceAbove`/`ResourceBelow` conditions at zero, across all
19 files that already referenced them.

`ResourcePool` (constructed from `components`+`events`, mirroring
`ModifierCollection`'s and `CharacterService`'s shape) is the full
operation vocabulary — `currentOf`/`maximumOf`/`minimumOf`/`stateOf`,
`clampValue` (pure, stateless), `set`/`add`/`subtract` (clamp to the
registered `[min, max]`; an undefined resource floors at `0` with no
upper bound — the same permissive-default convention
`ResourceAboveQuery`/`ResourceBelowQuery` already use for a missing
resource), `canAfford` (never mutates, never throws — mirrors
`Container.canPlace`), `consume` (throws
`InsufficientResourceException` without mutating anything if
`canAfford` would be `false` — mirrors `Container.place`/`canPlace`'s
split), and `restore` (`add`, naturally clamped to max). `set` publishes
`ResourceChanged` only when clamping leaves the stored value actually
different — not on a no-op set (e.g. adding to a resource already at
its maximum). No `RngService` anywhere in this module: every operation
is pure arithmetic and clamping, so resource changes stay deterministic
for free.

**Wiring** reuses the exact "default-if-absent" constructor pattern the
Character State layer established: `RuleContext` gained a `resources`
field, `RuleEngine` gained an optional `resources` constructor parameter
(forwarded into every `RuleContext` it builds internally in `_fire`),
and `PluginContext` gained a `resources` field — each defaults to a
fresh `ResourcePool` built from the same `components`/`events` already
passed in, when the caller doesn't supply one explicitly. This means
none of the ~30 existing call sites that construct `PluginContext`/
`RuleContext`/`RuleEngine` directly needed to change.
`PluginContext.ruleContextFor` passes through `resources: resources`
explicitly (the same shared instance), so a plugin's standalone
rule-context calls see the one pool with its registered definitions.

One correctness note for whoever bootstraps a real game session (not
enforced by the type system, the same way today's `entities`/`rng`
consistency across `RuleEngine` and `PluginContext` already isn't):
construct one `ResourcePool` and pass the *same* instance to both
`RuleEngine(..., resources: resources)` and
`PluginContext(..., resources: resources)`. `PluginContext` cannot do
this wiring itself — it receives an already-constructed `RuleEngine` as
its `rules` parameter, the same way it already receives an
already-constructed `EventBus`/`EntityRegistry` — so if neither default
is overridden, `PluginContext.resources` and `RuleEngine`'s internal
pool end up as two independent instances that never see each other's
registered definitions. See the bootstrap example below.

**Effects.** `ModifyResource` (pre-existing) now routes its `add`
through `context.resources` instead of hand-rolling the map mutation —
a pure superset of its old behavior (verified against every existing
test that executes it end-to-end: none drives a resource negative,
since existing content already gates cost effects behind a
`ResourceAbove` condition first). Two new effects:
`ConsumeResource(resource, amount)` silently no-ops — no mutation, no
event — when unaffordable, matching `Damage`/`Heal`'s existing "no-op
on an invalid precondition" convention (Effects never throw in this
engine; guard with a condition to detect the insufficient case
instead); `RestoreResource(resource, amount)` always succeeds, clamped
to the registered maximum.

Deliberately not here yet: any notion of passive regeneration/decay
over time (that's `Scheduler`'s job, once it exists) and any
per-entity-varying maximum (today's `ResourceDefinition` bounds are
global per resource id, not per character — sufficient for every
current use case; a future pass could layer per-entity scaling through
the existing Modifier Engine against a stat like `'max_stamina'`
without touching this module at all).

## Mastery system (`lib/src/mastery/`, `lib/src/components/mastery_component.dart`)

The generic, authoritative engine for "how good is this owner at this
arbitrary subject" — item mastery, technique tier, style mastery, a
future crafting recipe — one `MasteryTracker` for every unrelated subject
a game registers, never a per-domain system class (no `SwordMastery`, no
`TechniqueMastery`). Each plugin picks its own subject-id namespace (e.g.
`"item:iron_sword"`, `"technique:jab"`); Core never interprets it.

`MasteryComponent` (`Map<String, num> progress`, keyed by subject id) is
pure state. `MasteryDefinition` (`subject`, `thresholds: List<num>`) is
the level curve — `thresholds[i]` is the cumulative progress required to
reach level `i + 1` — registered once per subject id, global (not
per-owner). `MasteryRecord` (`owner`, `subject`, `level`, `progress`) is
the read-model identifying one mastery record exactly as specified: level
is *never stored*, always computed from progress + the registered
thresholds, so it can't desync.

`MasteryTracker` (constructed from `components`+`events`): `define`/
`definitionOf`, `progressOf` (0 default), `levelOf` (0 if no definition
registered — the same permissive-default convention `ResourcePool` uses
for an undefined resource), `recordOf`, `increase` (floors at 0,
publishes `MasteryChanged` with the actual delta applied, then one
`MasteryLevelReached` per level newly crossed in ascending order — a
single large grant that jumps two levels at once still fires both
events). No `unlock`-style instant-grant method exists here — that's
Discovery's job (see below); Mastery only answers "how good," never "can
this even be used."

`MasteryAtLeast(subject, level)` (`lib/src/rule/condition.dart`) and
`IncreaseMastery(subject, amount)` (`lib/src/rule/effect.dart`) — usable
by any plugin for any subject, delegating straight to
`context.mastery.levelOf`/`.increase`, the same "service-backed, not
`Query`-backed" reasoning `ProgressionTierAbove` uses (see below).

**Wiring** uses the same "default-if-absent" pattern as Resources/
Progression: `RuleContext`/`RuleEngine`/`PluginContext` each gained a
`mastery` field/param, defaulting to a fresh `MasteryTracker`.

## Progression layer (`lib/src/progression/`)

One generic engine for every arbitrary progression subject a plugin cares
about (the same shape of problem Mastery solves), kept as its own thin
adapter with its own `tier`/`experience` naming and its own event
vocabulary (`ProgressionChanged`/`ProgressionTierReached`, distinct from
`MasteryChanged`/`MasteryLevelReached`) — **but it reads and writes
through the same `MasteryTracker`/`MasteryComponent` storage Mastery
owns, rather than keeping independent state.** This was a deliberate,
explicit decision (not the initial design — Progression originally had
its own `ProgressionComponent`; Mastery was built afterward as a
standalone system per the same design conversation, and Progression was
then refactored to read through it) to avoid two independent stores that
could silently drift for what is, underneath, the same kind of data.
`ProgressionComponent` no longer exists — deleted as dead code once
`ProgressionEngine` stopped writing to it.

`ProgressionEngine`'s constructor now takes an optional `MasteryTracker`
(defaulting to a fresh one built from the same `components`/`events` if
not supplied); every read (`experienceOf`, `tierOf`, `stateOf`) forwards
directly to the tracker's `progressOf`/`levelOf`, and `define`/
`definitionOf` translate `ProgressionDefinition` to/from
`MasteryDefinition`. `addExperience` calls `_mastery.increase` (which
publishes `MasteryChanged`/`MasteryLevelReached` on the shared bus as
normal), then additionally publishes Progression's own
`ProgressionChanged`/`ProgressionTierReached` for the same occurrence —
so both event vocabularies fire for one underlying change, preserving
each system's existing public contract. `unlock(id, subject, tier)` is
unchanged in behavior (sets experience to a tier's threshold, never
regresses, throws `ArgumentError` for an invalid tier) — it now just
reads the registered thresholds via `_mastery.definitionOf` instead of
its own registry.

**Wiring — the one subtlety.** Because `ProgressionEngine` now needs the
*same* `MasteryTracker` instance the context's own `mastery` field uses
(two independently-defaulted `MasteryTracker`s would each hold their own
in-memory `_definitions` registry, silently splitting one store's
configuration in two even though both would still read/write the same
`MasteryComponent` data via the shared `ComponentStore`), `RuleContext`,
`RuleEngine`, and `PluginContext` were each converted from a plain
constructor into a **factory constructor plus a private named
constructor** (`RuleContext._`, `RuleEngine._`, `PluginContext._`) —
Dart's initializer lists can't introduce a local variable shared across
multiple field defaults, so the factory computes
`final sharedMastery = mastery ?? MasteryTracker(...)` once and passes it
into *both* the `mastery` field and `ProgressionEngine`'s own `mastery:`
parameter. This is purely a constructor-shape change; the public
parameter lists are unchanged (`mastery` and `progression` are both still
optional, defaulted), so none of the existing call sites needed updating.

**Conditions**/**Effects** are unchanged in this pass: `ProgressionTierAbove`/
`ProgressionTierBelow` and `GrantProgressionExperience`/
`UnlockProgressionTier` still delegate to `context.progression` exactly as
before — see their original reasoning (service-backed, not `Query`-backed,
to avoid duplicating registered thresholds into a second parameter).

## Discovery system (`lib/src/discovery/`, `lib/src/components/discovery_component.dart`)

A generic `unknown` → `discovered` → `unlocked` tri-state for arbitrary
content subjects — an item, technique, style, weapon, spell, or crafting
recipe — again one `DiscoveryTracker`, no per-domain system class.
`discovered` deliberately doesn't imply usable: "a discovered content
instance may still be unusable" is exactly why `unlocked` is a separate,
stronger state.

`DiscoveryState` (`unknown`/`discovered`/`unlocked`) — `unknown` is the
implicit default and *never actually stored*; `DiscoveryComponent`
(`Map<String, DiscoveryState>`, keyed by subject id) only ever holds
`discovered`/`unlocked` entries. `DiscoveryTracker` (constructed from
`components`+`events`): `stateOf` (default `unknown`), `discover`
(`unknown` → `discovered`; no-op, no event, if already at or past that
state — discovery never regresses), `unlock` (→ `unlocked`; if starting
from `unknown`, auto-promotes through `discovered` first, publishing both
`SubjectDiscovered` and `SubjectUnlocked` — an entity can never end up
`unlocked` without ever having been `discovered`; no-op if already
unlocked).

Unlike Mastery/Progression, Discovery's state needs no registered
configuration to interpret — a stored `DiscoveryState` is the complete
answer, no thresholds to look up — so both read paths this engine
generally offers exist here: `DiscoveredQuery`/`UnlockedQuery`
(`lib/src/query/queries.dart`, pure `Query`s reading `QueryScope`'s bare
`ComponentStore`, usable directly via `QueryEngine.evaluate` for bulk
scans) and `IsDiscovered`/`IsUnlocked` (`lib/src/rule/condition.dart`,
wrapping those same queries, mirroring `StatusActive`'s exact
Query-wrapping shape) — a deliberate contrast with
`ProgressionTierAbove`/`MasteryAtLeast`, which had to bypass `Query`
entirely because a tier/level check *does* need external registered
thresholds. `DiscoverSubject`/`UnlockSubject`
(`lib/src/rule/effect.dart`) delegate to `context.discovery`.

**Wiring** uses the same "default-if-absent" pattern, with no
factory-sharing subtlety needed — Discovery depends on nothing else and
nothing else depends on it, so a plain optional `discovery` param
defaulting to a fresh `DiscoveryTracker` sufficed on `RuleContext`/
`RuleEngine`/`PluginContext`.

Deliberately not here yet, for both Mastery and Discovery: any
per-entity-varying threshold curve (global per subject id, same scoping
choice as `ResourceDefinition.max`) and any automatic component cleanup
on `EntityDestroyed` (left as the general documented convention — the
caller's responsibility — same choice already made for
`ResourceComponent`).

## Content Registry — the engine's Asset/Data Registry (`lib/src/content/`)

`ContentRegistry` is core service #12 from `claude.md`: the mechanism
that lets content (items, skills, styles, spells, trinkets, statuses)
and rules be defined as data instead of a new Dart class per piece of
content. It is Core, not a plugin — `type` fields on loaded content are
opaque strings the registry stores and indexes but never branches on.

One `ContentDefinition` envelope (id, type, tags, an optional single
resource cost, conditions, effects, cross-references via `requires`, and
a passthrough `extra` map for anything else) covers items/skills/
styles/spells/trinkets/statuses uniformly — they're structurally
identical from the engine's point of view, matching
`MartialItemDefinition`'s and `MartialTechniqueAction`'s existing "one
class covers many content items via data" precedent. `components.cost`
parses into exactly one `ModifyResource(resource, -amount)` — a direct
data-driven mirror of `CombatAction.costEffects` and of every
hand-written technique in `martial_technique_action.dart` (each has
exactly one resource cost).

Turning `{"type": "damage", "amount": 15}` into a real `Damage(15)` goes
through a flat keyed factory dispatch, not a recursive JSON-AST
interpreter — `claude.md` explicitly warns against the latter. The
registry's constructor pre-registers factories for Core's own existing
generic `Effect`/`Condition` classes only; a plugin registers more for
its own via the same `registerEffectFactory`/`registerConditionFactory`
methods it would use for anything else optional in this engine.
`HasComponent<T>`/`EventCount` are deliberately not among the built-ins
— both need a compile-time type argument a JSON string key can't supply
without a second name-to-`Type` registry, and no concrete content has
ever needed either from data, so adding it now would be exactly the
speculative abstraction `claude.md`'s IMPLEMENTATION STYLE section
forbids.

`RuleDefinition` covers data-defined `Rule`s through one more registry —
`registerTrigger` — because a `Rule`'s `trigger`/`subjectOf` are a `Type`
and a closure, neither directly JSON-expressible. Core pre-registers
triggers only for its own events (`EntityDamaged`, `EntityHealed`,
`EntityKilled`, `EntityCreated`, `EntityDestroyed`); `ContentRegistry`
never calls `RuleEngine.register` itself — turning a loaded
`RuleDefinition` into a live rule stays the caller's explicit choice,
the same "nothing wires itself up automatically" convention documented
above for `EntityDestroyed` component cleanup.

`loadAll` is fully atomic: every entry is parsed, then every id is
checked for duplicates, then every `requires` is checked against the
union of the registry and the whole batch, and only then does anything
get registered — so two definitions in one batch can reference each
other in either order, and a bad entry anywhere in a batch leaves the
registry exactly as it was before the call.

`ContentRegistry.toJson()`/`loadAll`/`loadRule` round-trip losslessly at
the data level — like `Container.toJson()`/`fromJson()` before it, this
is a self-contained capability of this module only, not the engine-wide
Serialization service `claude.md` describes (still a separate future
pass), and it re-exports each definition's original decoded JSON rather
than attempting to re-serialize live `Effect`/`Condition` objects.

This pass also grew `PluginContext` with a `content` field (alongside
the existing seven services) — every plugin can now register its own
factories/triggers and load/query content from any lifecycle method.

## Plugin SDK and ElementalPlugin (`lib/src/plugin/plugin_sdk.dart`, `lib/src/plugins/elemental/`)

`PluginSdk` is a convenience façade over `PluginContext`, not a new Core
capability — every method delegates to a service `PluginContext` already
exposed before this pass (`entities`/`components`/`events`/`rules`/
`content`). Its entire value is eliminating the
`List<EventSubscription>` bookkeeping `MartialArtsPlugin` originally had
to manage by hand: `registerComponentCleanup`/`registerEvent`/
`registerRule` all track their `EventSubscription` internally, and
`disposeAll()` cancels every one of them in a plugin's `unregister` —
see `PLUGIN_SYSTEM.md` for the full method table and a step-by-step
walkthrough for third-party developers.

`registerAsset`/`registerLocalization` are sugar over `content` rather
than new services: `claude.md`'s numbered core-service list has one
combined entry, "12. Asset/Data Registry" — `ContentRegistry` (the prior
pass) already is that registry, so "asset" and "localization" are simply
two more opaque `type` values, no different in kind from "skill" or
"item". This does mean neither is undoable via `disposeAll()` —
`ContentRegistry` has no factory-removal or unload operation, a
limitation this pass didn't change, so it's documented rather than
papered over.

`ElementalPlugin` is the SDK's reference implementation:
Fire/Water/Lightning, depending on nothing but Core (`dependencies =>
const []`) — deliberately not Combat, unlike `MartialArtsPlugin`, so a
third-party developer's first example is the simplest one, not one that
also demonstrates cross-plugin dependency. Its "water conducts"
interaction (a `status:soaked` entity that takes damage also becomes
`status:shocked`) reacts to Core's own `EntityDamaged` event exactly the
way MartialArts' Shaolin rule does, proving the same "react to events,
don't intercept effects" pattern holds with zero Combat involvement at
all. Its `ElementalAffinityComponent`/`HasElementalAffinity`/
`ApplyElementalStatus` mirror `MartialLoadoutComponent`/`ResourceAbove`/
composed-`ApplyStatus` in shape, and its three content definitions
(`fireball`/`tidal_wave`/`spark_bolt`) each mix a built-in
`ContentRegistry` factory (`damage`) with two of the plugin's own
(`applyElementalStatus`, `hasElementalAffinity`), loaded atomically via
`sdk.registerContentBatch` — proving last pass's `loadAll` atomicity
composes cleanly with a real plugin's `initialize`.

## Cross-plugin interoperability proof (`test/integration/cross_plugin_synergy_test.dart`, `test/integration/architecture_dependency_test.dart`)

`MartialArtsPlugin` and `ElementalPlugin` are two independent
content plugins — neither imports or depends on the other, and neither
is a dependency of the other in `claude.md`'s sense (only MartialArts's
existing `-> combat` edge is real). Their one demonstrated synergy uses
tags and the Modifier Engine together: `ElementalPlugin`'s
`emberCharm` registers a `Modifier` against stat `'punch'` — the exact,
arbitrary-caller-chosen `damageStat` MartialArts' `jab`/`powerCross`
already resolve through `ModifierResolver` — gated on
`condition: HasTagQuery('martial')`, the same conditional-`Modifier`
pattern `counterstrikeRing` already uses. An entity that both
`learnStyle`s Boxing (which grants the generic `'martial'` tag) and
`equipElementalItem(elementalItem(ElementalItemIds.emberCharm, context),
...)` deals bonus punch damage, with
zero new `Rule`/`Condition` class and zero cross-plugin import — the
same mechanism Shaolin's own iron-body synergy already proved, just
registered by a different plugin and gated on a different plugin's tag
this time.

`architecture_dependency_test.dart` makes the "neither imports the
other, Core imports neither" property an automated, CI-enforceable
check (reading source files' text at test time) rather than a one-time
manual audit that rots the next time a file moves.

## Physique (`lib/src/plugins/physique/`, `lib/physique_plugin.dart`)

A character's body type — Sturdy/Power/Burst/Endurance — the second
independent content plugin depending on nothing but Core (after
Elemental), and the first plugin built with a real cross-plugin
mechanic as a first-class design goal from the start, rather than
retrofitted onto an existing example.

**Runtime component.** `PhysiqueComponent` holds only the stable
physique id — no tags, no affinity, no modifiers duplicated onto it.
Everything else is data, resolved from `ContentRegistry` when needed.

**Data definition.** `physiqueContentDefinitions` (`physique_content.dart`)
loads through `ContentRegistry` exactly like Elemental's spells and
MartialArts' migrated techniques. `modifiers`/`affinities` aren't part
of `ContentRegistry`'s native vocabulary (`Modifier` isn't an `Effect`/
`Condition`) — they land in `ContentDefinition.extra` verbatim, and
`physiqueDefinitionFromContent` turns that into a typed
`PhysiqueDefinition` whose `modifiersFor(character)` builds real
`Modifier` objects, mirroring `martialTechniqueFromDefinition`'s
`baseDamage`/`damageStat` pattern exactly.

**Random assignment.** `initializePhysique(character, context)` — a
plain function, not a `Rule` on `EntityCreated` (not every entity is a
character, so creation alone can't say when to run this) — is
idempotent (returns the existing id if the character already has a
`PhysiqueComponent`), selects uniformly via `context.rng.nextInt(4)`
(never `dart:math` directly, so a run stays reproducible from its
seed), attaches the component, registers the physique's two synergy
`Modifier`s, and publishes `PhysiqueAssigned`. Matches
`learnStyle`/`attuneToElement`/`equipItem`'s existing "explicit
function, caller decides when" idiom — no game-specific
`NewGameManager` needed; whoever creates a character calls this.

**Tag model.** Each physique's content carries descriptive tags
(`physique`, its primary-affinity name, `western_affinity`/
`eastern_affinity`) — metadata, not read by any condition, the same
role `MartialTechniqueAction.tags` already plays. The tags that
actually drive synergy are different: `'western'`/`'eastern'`, granted
on the *character entity* by MartialArts' `learnStyle`. Physique never
inspects a physique's own descriptive tags to decide anything.

**Synergy model.** Each physique registers two conditional `Modifier`s
targeting its primary-affinity stat (`defense`/`strength`/`speed`/
`stamina` — an arbitrary, caller-chosen name exactly like `damageStat`):
`×1.25` gated on `HasTagQuery('western')` or `HasTagQuery('eastern')`
(whichever tradition that physique favors), `×0.85` gated on the other.
No explicit "neutral ×1.00" modifier exists — `ModifierResolver`
already treats an empty active-modifier set as the identity, so an
entity with neither tradition tag is neutral for free. This is the same
mechanism Shaolin's own iron-body synergy proved, and the same one
`ElementalPlugin`'s `emberCharm` proved again across a different plugin
pair — Physique is the third independent proof of the identical
pattern.

**The one MartialArts touch.** `learnStyle` now also grants a broad
tradition tag — `'western'` for Boxing, `'eastern'` for Shaolin and Tai
Chi — reusing vocabulary MartialArts' own technique content
(`martial_technique_content.dart`) already uses per-technique. This is
the single line Physique's synergy needs to have anything to check on
the character; it adds no Physique-specific vocabulary to MartialArts
(Physique is never named), and any future plugin can read the same two
tags.

**Dependency direction.** `PhysiquePlugin.dependencies => const []` —
Core only. No file under `lib/src/plugins/physique/` imports
`martial_arts`/`combat`/`elemental`; no file under
`lib/src/plugins/martial_arts/` or `lib/src/plugins/combat/` imports
`physique` (a doc comment may still name another plugin in prose — the
governance test below checks import-shaped substrings, not the bare
plugin name, precisely so a legitimate mention like that doesn't fail
it). `test/integration/architecture_dependency_test.dart` — the
automated dependency-governance test built in the prior
cross-plugin-interop pass — now checks Physique in both directions
against MartialArts and Combat, alongside its existing Elemental
checks, making this a permanent, CI-enforceable property.
