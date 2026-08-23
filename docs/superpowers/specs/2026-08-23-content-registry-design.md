# Content Registry — Design

## Purpose

Implement the engine's **Asset/Data Registry** (`claude.md`'s core
service #12) — the mechanism that lets content (items, skills, styles,
spells, trinkets, statuses, rules) be defined as data instead of a new
Dart class per piece of content, per `claude.md`'s DATA DRIVEN CONTENT
section. This is Core, not a plugin: the mechanism (parse, validate,
store-by-id, look up) is pure verb — it never contains martial-arts,
magic, or any other content-domain vocabulary. `type` fields on loaded
content are opaque strings Core stores and indexes but never interprets.

Scope boundary: this registry consumes already-decoded Dart data
(`Map<String, dynamic>` / `List<dynamic>`), the same boundary
`Container.toJson()`/`fromJson()` already drew for itself (see
`ARCHITECTURE.md`). Reading JSON text off disk or an asset bundle is a
thin wrapper an application adds later — out of scope here, same as it
was explicitly deferred in the "What's deliberately not here yet"
section of `ARCHITECTURE.md`.

## Why not a giant generic JSON interpreter

`claude.md` explicitly warns against this. The alternative used
throughout this codebase already — `Condition`/`Effect`/`PlacementRule`
are "implement the interface directly, no registry required" — doesn't
by itself let *data* pick which `Effect` subclass to instantiate. The
fix is a **flat keyed factory dispatch**, not a recursive AST
interpreter: `{"type": "damage", "amount": 15}` looks up the factory
registered under the key `"damage"` and calls it with `{"amount": 15}`.
Each factory is a small, typed, independently-testable function. Core
pre-registers factories for its own existing generic `Effect`/
`Condition` classes (the ones `claude.md`'s EFFECTS/CONDITIONS sections
already name); plugins register more for their own. No new parsing
machinery is invented per content kind — every kind reuses the same two
factory registries.

## The content envelope

Items, skills, styles, spells, trinkets, and statuses are structurally
identical from the engine's point of view: an id, an opaque type label,
tags, an optional single resource cost, optional conditions, optional
effects, optional cross-references to other content, and whatever
domain-specific fields the owning plugin cares about. One typed class
covers all of them — no per-kind schema class, matching
`MartialItemDefinition`'s and `MartialTechniqueAction`'s existing "one
class covers many content items via data" precedent.

```dart
class ContentDefinition {
  final String id;
  final String type;                 // opaque — Core never branches on it
  final Set<String> tags;
  final List<Effect> costEffects;    // 0 or 1 entries; see "cost" below
  final List<Condition> conditions;
  final List<Effect> effects;
  final Set<String> requires;        // other content ids that must exist
  final Map<String, dynamic> extra;  // unrecognized fields, verbatim
  final Map<String, dynamic> raw;    // the original decoded JSON, verbatim
}
```

### JSON shape

```json
{
  "id": "dragon_palm",
  "type": "skill",
  "tags": ["attack", "fist", "fire", "dragon"],
  "components": {
    "cost": { "resource": "qi", "amount": 4 }
  },
  "conditions": [
    { "type": "hasTag", "tag": "style:shaolin" }
  ],
  "effects": [
    { "type": "damage", "amount": 15 }
  ],
  "requires": ["style:shaolin"],
  "flavorText": "..."
}
```

- `id`, `type`: required strings, non-empty.
- `tags`: optional array of strings; defaults to empty.
- `components.cost`: optional; if present, must be `{"resource": string,
  "amount": num}`. Parses to exactly one entry in `costEffects`:
  `ModifyResource(resource, -amount)`. This is a direct data-driven
  mirror of `CombatAction.costEffects` and of every hand-written
  technique in `martial_technique_action.dart` (each has exactly one
  resource cost) — the field name in JSON is `components.cost` to match
  `claude.md`'s own example verbatim; internally there is exactly one
  cost, not a list of cost *kinds*, because no content in this engine
  has ever needed more than one.
- `conditions` / `effects`: optional arrays of `{"type": <factory key>,
  ...params}`. Each entry dispatches through the matching factory
  registry (see below). An empty/absent array means no conditions/no
  effects — not an error.
- `requires`: optional array of other content ids. Checked once, after
  every definition in a `loadAll` batch has been structurally parsed —
  so two definitions in the same batch may reference each other in
  either order.
- Any other top-level field (`flavorText` above) is preserved verbatim
  in `extra` and never interpreted by Core — the owning plugin reads it
  itself, same spirit as `MartialTechniqueAction.tags` being "content
  metadata, not read by any Condition in this plugin." This includes any
  sibling key inside `components` besides `cost` — e.g. `claude.md`'s own
  `iron_sword` example (`"components": {"attack": {"damage": 12}}`) has
  no `cost`, so nothing is consumed into `costEffects`, and the whole
  `components` map — `{"attack": {"damage": 12}}` — surfaces verbatim at
  `extra['components']` for whichever plugin knows what an "attack"
  component is. Only the single key `cost` is ever removed from
  `components` before the remainder lands in `extra`.
- `raw` always holds the exact input map, for lossless re-export
  (§ Serialization).

## Factory registries

```dart
class ContentRegistry {
  void registerEffectFactory(
      String key, Effect Function(Map<String, dynamic> params) factory);
  void registerConditionFactory(
      String key, Condition Function(Map<String, dynamic> params) factory);
  void registerTrigger(
      String key, Type eventType, EntityId? Function(Object event) subjectOf);
  // ... loading/lookup, below
}
```

`ContentRegistry`'s constructor pre-registers exactly the factories
covering Core's existing, already-shipped generic `Effect`/`Condition`
classes:

| key | factory | required params |
|---|---|---|
| `damage` | `Damage` | `amount: num` |
| `heal` | `Heal` | `amount: num` |
| `modifyStat` | `ModifyStat` | `stat: string`, `delta: num` |
| `modifyResource` | `ModifyResource` | `resource: string`, `delta: num` |
| `applyStatus` | `ApplyStatus` | `status: string` |
| `removeStatus` | `RemoveStatus` | `status: string` |
| `addTag` | `AddTag` | `tag: string` |
| `removeTag` | `RemoveTag` | `tag: string` |
| `createEntity` | `CreateEntity` | `tags: string[]` (optional) |
| `destroyEntity` | `DestroyEntity` | — |
| `transformEntity` | `TransformEntity` | `tags: string[]` |

| key | factory | required params |
|---|---|---|
| `hasTag` | `HasTag` | `tag: string` |
| `resourceAbove` | `ResourceAbove` | `resource: string`, `threshold: num` |
| `resourceBelow` | `ResourceBelow` | `resource: string`, `threshold: num` |
| `healthBelow` | `HealthBelow` | `threshold: num` |
| `statusActive` | `StatusActive` | `status: string` |
| `randomChance` | `RandomChance` | `probability: num` |

`HasComponent<T>` and `EventCount` are omitted: both need a compile-time
`Type`/generic argument that a JSON string key cannot supply without a
separate name→`Type` registry of its own — no concrete content in this
engine has ever needed either from data, so adding that registry now
would be exactly the "speculative abstraction without a concrete use
case" `claude.md`'s IMPLEMENTATION STYLE section forbids. A plugin that
needs one registers its own factory under its own key, the same way it
would register any custom `Effect`.

`registerTrigger` is pre-seeded (in the constructor, alongside the
effect/condition factories) for Core's own events, since these are Core
vocabulary, not a content domain's:

| key | event type | subjectOf |
|---|---|---|
| `EntityDamaged` | `EntityDamaged` | `.id` |
| `EntityHealed` | `EntityHealed` | `.id` |
| `EntityKilled` | `EntityKilled` | `.id` |
| `EntityCreated` | `EntityCreated` | `.id` |
| `EntityDestroyed` | `EntityDestroyed` | `.id` |

Plugins call the same `registerEffectFactory`/`registerConditionFactory`/
`registerTrigger` methods during their own `initialize` to add
domain-specific ones (e.g. a future MartialArts pass could register
`ActionCompleted`/`TurnStarted` triggers) — this spec does not modify
`MartialArtsPlugin` or any other existing plugin; it only adds the
registry itself.

## Rule definitions

A `Rule`'s `trigger` is a `Type` and `subjectOf` a closure — the two
pieces a bare `{"type": "..."}` factory dispatch can't produce on its
own. Rule content therefore loads through a second, explicitly-typed
path that reuses the same two factory registries:

```json
{
  "id": "shaolin_iron_body_heal",
  "trigger": "EntityDamaged",
  "conditions": [{ "type": "hasTag", "tag": "stance:iron_body" }],
  "effects": [{ "type": "heal", "amount": 2 }]
}
```

```dart
class RuleDefinition {
  final String id;
  final Rule rule;          // trigger/subjectOf resolved via registerTrigger
  final Map<String, dynamic> raw;
}
```

`ContentRegistry.loadRule(Map<String, dynamic> json) -> RuleDefinition`
and `ContentRegistry.rule(String id) -> RuleDefinition` parallel
`load`/`get` below, sharing the same id space (a rule id collides with a
content id exactly like two content ids would) and the same error types.
`ContentRegistry` never calls `RuleEngine.register` itself — turning a
loaded `RuleDefinition` into a live, running rule stays the caller's
explicit choice, matching this engine's existing "nothing wires itself
up automatically" convention (`ARCHITECTURE.md`'s "Integrating
EntityRegistry and ComponentStore" section makes the same point about
event wiring).

## Loading, lookup, validation

```dart
class ContentRegistry {
  ContentDefinition load(Map<String, dynamic> json);          // single
  List<ContentDefinition> loadAll(List<Map<String, dynamic>> jsonList);
  RuleDefinition loadRule(Map<String, dynamic> json);

  ContentDefinition get(String id);        // throws ContentNotFoundException
  ContentDefinition? find(String id);      // null instead of throwing
  List<ContentDefinition> allOfType(String type);
  List<ContentDefinition> withTag(String tag);

  List<Map<String, dynamic>> toJson();     // every loaded definition's `raw`, in load order
}
```

- `load`/`loadRule` validate and register one definition immediately;
  `requires` is checked against everything already registered (no
  forward-reference partner in a single-definition call).
- `loadAll` is fully atomic — it commits nothing to the registry until
  every entry in the batch has cleared every check. Order: (1) parse
  every entry structurally (id/type presence, factory dispatch, cost
  shape) — a raw JSON entry never mutates registry state; (2) check
  every parsed entry's id for a duplicate, against both the registry and
  the rest of the batch; (3) check every parsed entry's `requires`
  against the union of the registry and every id in the batch — so
  entries within one batch may reference each other in either order;
  (4) only once every entry has cleared all three checks, register them
  all. A failure at any step — a bad field, a duplicate id, an
  unresolved `requires` — leaves the registry exactly as it was before
  the call; nothing partially lands.
- IDs are globally unique across every type and across rules (`claude.md`:
  "use stable IDs") — `load`/`loadAll`/`loadRule` throw
  `ContentDuplicateIdException` on collision, including within the same
  batch.

### Errors

```dart
abstract class ContentSystemException implements Exception {
  final String message;
}

class ContentFieldException extends ContentSystemException {
  // thrown by factories; e.g. ContentFieldException('amount', 'required num field missing')
  ContentFieldException(this.path, String problem);
  final String path;
}

class ContentValidationException extends ContentSystemException {
  // what load()/loadAll() actually throw — wraps a ContentFieldException
  // with which definition it came from
  ContentValidationException(String definitionId, ContentFieldException cause);
}

class ContentDuplicateIdException extends ContentSystemException {
  ContentDuplicateIdException(String id);
}

class ContentDependencyException extends ContentSystemException {
  ContentDependencyException(String definitionId, String missingRequiredId);
}

class ContentNotFoundException extends ContentSystemException {
  ContentNotFoundException(String id);
}

class UnknownContentFactoryException extends ContentSystemException {
  // thrown when an effect/condition/trigger `"type"` key has no
  // registered factory
  UnknownContentFactoryException(String kind, String key);
}
```

Every factory (Core's built-in ones and any a plugin adds) validates its
own params and throws `ContentFieldException` on a missing/wrong-typed
field — `ContentRegistry` catches it and re-throws
`ContentValidationException` carrying the owning definition's id, so a
caller sees e.g. `Invalid content 'dragon_palm': effects[0].amount —
required num field missing` in one exception's `toString()`, mirroring
`PluginSystemException`'s existing `toString() => message` convention
exactly.

A small set of typed field-extraction helpers — static methods on a
`ContentField` class (`requireString`/`requireNum`/`requireMap`/
`optionalMapList`/`optionalStringSet`), in
`lib/src/content/json_helpers.dart` — throw `ContentFieldException`
directly and are used both by Core's built-in factories and available
for any plugin's own factories. Namespaced under one class rather than
exported as top-level functions specifically so the package's public
surface doesn't gain generic top-level names like `requireString`; this
is also what keeps every individual factory a few lines long rather than
each reimplementing field validation.

## Serialization

`ContentRegistry.toJson()` returns every loaded definition's `raw` map
(content definitions then rule definitions, in load order) — re-feeding
that list through a fresh `ContentRegistry`'s `loadAll` (plus `loadRule`
for the rule entries) reproduces an equivalent registry. This mirrors
`Container.toJson()`/`fromJson()`'s existing "self-contained capability
of this module only" boundary: it is not an integration point for the
engine-wide Serialization service `claude.md` describes (that remains a
separate future pass), and it deliberately does not attempt to
re-serialize live `Effect`/`Condition` objects — only the original
decoded JSON, which is lossless because `raw` is never mutated after
parsing.

## Wiring into `PluginContext`

`PluginContext` gains one new required field:

```dart
class PluginContext {
  const PluginContext({
    ..., // existing fields unchanged
    required this.content,
  });
  final ContentRegistry content;
}
```

Every existing call site that constructs a bare `PluginContext(...)`
(13 files, all under `test/`, plus `lib/src/plugin/plugin_context.dart`
itself has none to change — it's the class definition) must add
`content: ContentRegistry()`. This is purely mechanical — one line added
per call site, same shape everywhere, no logic — a single batched task
in the implementation plan rather than one task per file.

## File layout

```
lib/src/content/
  content_definition.dart   # ContentDefinition, RuleDefinition
  content_errors.dart       # every exception type above
  json_helpers.dart         # requireString/requireNum/optionalNum/requireMap/requireList
  content_registry.dart     # ContentRegistry: factories, load/loadAll/loadRule, lookup, toJson
```

`lib/build_engine.dart` exports all four new files, alphabetically
positioned like every existing export.

## Test plan

Mirrors the six categories requested, each as its own `test/src/content/`
file (or grouped where natural):

1. **Loading** — `load` parses a full envelope (tags/cost/conditions/
   effects/extra all populated) into the expected typed shape;
   `loadAll` loads multiple; `loadRule` parses a trigger/conditions/
   effects rule and the resulting `Rule.trigger`/`subjectOf` behave
   correctly when handed to a real `RuleEngine` (subject resolution
   verified against a real event, not just structurally).
2. **Validation** — missing `id`/`type` fields rejected; an unknown
   effect/condition/trigger key throws `UnknownContentFactoryException`
   naming the key; a malformed `components.cost` (missing `resource` or
   `amount`, wrong type) throws `ContentValidationException` whose
   message names the definition id and field path; each of the 11
   built-in effect factories and 6 built-in condition factories rejects
   its own missing/mistyped required param.
3. **Lookup** — `get`/`find`/`allOfType`/`withTag` against a
   multi-definition registry, including `find` returning `null` and
   `get` throwing `ContentNotFoundException` for an absent id.
4. **Dependency errors** — a `requires` referencing an id absent from
   both the registry and the batch throws `ContentDependencyException`
   naming both ids; two definitions in the same `loadAll` batch that
   reference each other (A requires B's id, B requires A's id, both
   otherwise valid) both load successfully, proving the two-phase
   register-then-check order.
5. **Duplicate IDs** — loading the same id twice (across two calls, and
   within one `loadAll` batch) throws `ContentDuplicateIdException`; a
   rule id colliding with a content id (and vice versa) also throws.
6. **Serialization** — `toJson()` on a registry loaded from a batch of
   content + rule definitions, fed through `loadAll`/`loadRule` on a
   fresh `ContentRegistry`, produces a registry whose `get`/`allOfType`/
   `withTag` results match the original (compared by id/type/tags,
   since `Effect`/`Condition` instances aren't `==`-comparable) — proves
   the round trip is lossless at the data level.

Additionally, an integration test (`test/integration/`) demonstrates the
full loop end-to-end: load a skill definition equivalent to
`claude.md`'s own `dragon_palm` example from a JSON-shaped `Map`, resolve
its `costEffects`/`conditions`/`effects` against a real
`entities`/`components`/`events` triple (no plugin involved — this
proves the registry needs nothing beyond what `PluginContext` already
carries), and confirm a `RuleContext`-driven `evaluate`/`apply` pass
behaves identically to the equivalent hand-written `Condition`/`Effect`
objects would.
