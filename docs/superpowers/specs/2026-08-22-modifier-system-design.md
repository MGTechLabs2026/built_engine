# Build Engine — Modifier System Design

Date: 2026-08-22
Status: Approved

## Purpose

Add the Modifier Engine (`claude.md`'s core service #7) to `build_engine`:
`Modifier`, `ModifierCollection`, `ModifierSource`, `ModifierResolver`,
deterministic stat calculation, priority/ordering, temporary (duration-based)
modifiers, and conditional modifiers. This directly supersedes
`StatComponent`/`ModifyStat`'s "raw value, stopgap" status noted in
`ARCHITECTURE.md` — proper `base + modifiers = derived value` computation,
per `claude.md`'s MODIFIER SYSTEM section, replaces direct mutation of final
derived stats.

No martial-arts, magic, cultivation, or other game-specific content. No
Spatial/Container Engine, dedicated Resource Engine service, Scheduler,
Asset/Data Registry, or Serialization — each remains a separate future pass.
No registry/factory/data-driven modifier deserialization — `Modifier`
instances are composed directly in code, consistent with how `Condition`/
`Effect` are composed (no registry) in the previous pass.

## Data Shapes (`lib/src/modifier/`)

New directory, matching the established `lib/src/<subsystem>/` convention.

```dart
enum ModifierOperation { add, multiply, override, min, max }

/// Identifies where a modifier came from, for later bulk removal. Not tied
/// to `EntityId` — a source can be an item's data id, a rule's identifier,
/// a plugin name, anything a caller chooses as a stable string key.
class ModifierSource {
  const ModifierSource(this.id);
  final String id;
  // == / hashCode by id, so ModifierCollection.removeBySource can match.
}

/// A single stat adjustment. Fields match claude.md's MODIFIER SYSTEM
/// section exactly: source, target, stat, operation, value, priority,
/// duration, condition.
class Modifier {
  const Modifier({
    required this.source,
    required this.target,
    required this.stat,
    required this.operation,
    required this.value,
    this.priority = 0,
    this.duration,
    this.condition,
  });

  final ModifierSource source;
  final EntityId target;
  final String stat;             // arbitrary engine-agnostic string key
  final ModifierOperation operation;
  final num value;
  final int priority;            // orders modifiers WITHIN their operation group only
  final int? duration;            // null = permanent; N = expires after N ModifierCollection.tick() calls
  final Query? condition;         // null = always active; reuses the existing Query system
}
```

`Modifier` carries both `target` (an `EntityId`) and `stat` explicitly, per
`claude.md`'s literal field list — `ModifierCollection` is a single global
repository of all registered modifiers across every entity/stat, not a
per-entity component. This mirrors how `ComponentStore` is a single
repository keyed by `(Type, EntityId)`; `ModifierCollection` is keyed by
`(EntityId, String stat)`.

## Reusing `Query` for Conditional Modifiers

A conditional modifier ("this bonus only applies while the entity has tag X
/ is below health threshold Y") is a continuous "is this entity currently in
state Z" check — exactly what the existing `Query` abstraction
(`lib/src/query/query.dart`) already models, with `and`/`or`/`not`
combinators for composability already built. This is **not** the same
concept as a Rule's `Condition` (which evaluates against a `RuleContext`
carrying a triggering event, RNG, event counts, etc.) — a modifier has no
triggering event, it's evaluated fresh every time a stat is computed. Reusing
`Query` avoids inventing a third predicate abstraction and keeps this
consistent: `condition: Query?` on `Modifier`, evaluated via
`condition.matches(target, QueryScope(components: ...))`.

## `ModifierCollection` (`lib/src/modifier/modifier_collection.dart`)

The repository of all registered modifiers. Internally stores each added
`Modifier` alongside a private, separately-mutable "remaining duration"
counter (the public `Modifier.duration` stays immutable — it's the
*configured* duration; `ModifierCollection` tracks how much is left).

```dart
class ModifierCollection {
  void add(Modifier modifier);

  /// Removes every modifier whose `source` equals [source].
  void removeBySource(ModifierSource source);

  /// Modifiers currently applicable to [target]'s [stat]: matching
  /// target+stat, not yet expired, and whose `condition` (if any) currently
  /// matches. Returned in the order they were added (see Determinism below)
  /// — `ModifierResolver` relies on this ordering.
  Iterable<Modifier> activeModifiersFor(
    EntityId target,
    String stat,
    ComponentStore components,
  );

  /// Decrements every timed (`duration != null`) modifier's remaining
  /// duration by 1; removes any that reach 0. The only mechanism for
  /// "temporary modifiers" — no Scheduler, no new event type. A future
  /// Scheduler pass calls this; for now, callers (including tests) call it
  /// directly.
  void tick();
}
```

## `ModifierResolver` (`lib/src/modifier/modifier_resolver.dart`)

A pure function — no storage, no `ComponentStore`/`EntityRegistry`
dependency — taking an already-filtered (target+stat-matching,
condition-passing, non-expired) set of modifiers and a base value, producing
the derived value.

```dart
class ModifierResolver {
  const ModifierResolver();

  num resolve(num base, Iterable<Modifier> modifiers);
}
```

### Pipeline (documented, deterministic)

```
base → ADD (sum) → MULTIPLY (product) → OVERRIDE (last wins) → MIN (ceiling) → MAX (floor) → final value
```

This macro-order is **always fixed**, regardless of any modifier's
`priority` — priority only orders modifiers *within* their own operation
group.

- **ADD**: `value += m.value` for every ADD modifier, in priority order.
- **MULTIPLY**: `value *= m.value` for every MULTIPLY modifier, in priority
  order. `value` is the literal multiplier factor (e.g. `1.1` for a +10%
  effect) — not a delta added to an implicit 1.0.
- **OVERRIDE**: `value = m.value` for every OVERRIDE modifier, in priority
  order — each replaces the accumulated value, so the **highest-priority**
  OVERRIDE (applied last) wins.
- **MIN**: `value = math.min(value, m.value)` for every MIN modifier —
  can only lower the value (a ceiling). Stacking multiple MIN modifiers is
  order-independent (min is associative): the tightest ceiling always wins
  regardless of priority/order.
- **MAX**: `value = math.max(value, m.value)` for every MAX modifier — can
  only raise the value (a floor). Same order-independence within the group.
- **MIN-group runs before MAX-group.** This ordering only matters for
  misconfigured content where a MIN ceiling is below a MAX floor (undefined/
  contradictory by construction) — documented as a fixed, arbitrary-but-
  consistent tie-break for that case, not a claim that it "fixes" the
  contradiction.

### Determinism Without an Extra Sequence Field

Ties within an operation group (equal `priority`) break by each modifier's
position in the `Iterable` passed to `resolve()`. `ModifierCollection`
stores modifiers in a `List` (insertion-ordered) and
`activeModifiersFor`'s `.where()` never reorders — so the incoming iterable
already reflects registration order, deterministically. `ModifierResolver`
does its own explicit **stable** sort (decorate-with-original-index, sort by
`(priority, originalIndex)`, undecorate) rather than relying on `List.sort`,
whose stability Dart does not guarantee. No sequence-number field is added
to `Modifier` itself — the caller-provided iteration order *is* the
tiebreak source, and this is documented as a contract: whoever calls
`resolve()` directly (bypassing `ModifierCollection`) is responsible for
passing modifiers in a meaningful, stable order.

## Testing

Unit tests for: `ModifierSource` equality/removal matching; `Modifier` as a
plain immutable value holder; `ModifierResolver` covering each operation in
isolation, each operation stacking (multiple ADD, multiple MULTIPLY,
multiple OVERRIDE-last-wins, multiple MIN/MAX order-independence), the full
pipeline order end-to-end (a case with all five operation types together,
proving ADD→MULTIPLY→OVERRIDE→MIN→MAX order), and priority-based ordering
within a group including a same-priority tie broken by input order;
`ModifierCollection` covering stacking, removal by source, `tick()`
expiring a temporary modifier and leaving permanent ones untouched, and
conditional modifiers (`condition` gating whether `activeModifiersFor`
includes a modifier, using a real `Query` against a real `ComponentStore`).
One integration-style test wiring `ModifierCollection` + `ModifierResolver`
together end-to-end (register several modifiers including one conditional
and one temporary, resolve a stat, tick until the temporary one expires,
resolve again and confirm the change) — using real, non-fake services.

## Documentation Deliverables

Amend `ARCHITECTURE.md`: add a `### Modifier Engine` subsection under
"Services implemented so far"; update `ModifyStat`'s and `StatComponent`'s
existing "stopgap" language to note the Modifier Engine now exists (whether
`ModifyStat` itself is rewired to use it is a scope question for the next
pass, not this one — this pass adds the calculation engine, it does not
retrofit the already-shipped `ModifyStat` effect); remove "Modifier Engine"
from "What's deliberately not here yet".

## Explicitly Out of Scope

Rewiring `ModifyStat`/`ModifyResource` effects to route through
`ModifierCollection` instead of directly mutating `StatComponent`/
`ResourceComponent` (a real follow-up, but a separate, deliberate design
decision about how effects and modifiers interact — not a mechanical
extension of this pass). Extending `PluginContext` to expose `modifiers`
(also flagged as future work in the previous pass's final review, still
not this pass's job). A `ModifierApplied`/`ModifierRemoved`/
`ModifierExpired` event trio (`claude.md`'s event list doesn't require one,
and no consumer needs it yet — would be speculative). Any registry/
factory/data-driven modifier deserialization.
