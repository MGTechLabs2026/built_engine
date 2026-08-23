# Physique Plugin — Design

## Purpose

A new, independent content plugin representing a character's body type
(Sturdy/Power/Burst/Endurance), depending on nothing but Core, that
interoperates with the already-shipped MartialArts plugin purely through
generic tags/queries/rules/modifiers/events — never a Dart import in
either direction. This proves the same architecture-level claim the
prior cross-plugin interop pass proved for MartialArts↔Elemental, now
for a genuinely new plugin built from scratch rather than an existing
example retrofitted.

## The one necessary MartialArts touch

Physique's synergy needs to know "is this character trained in a
western or eastern martial tradition" — and nothing on a character
entity currently says that. `learnStyle`
(`lib/src/plugins/martial_arts/martial_styles.dart`) grants `'martial'`
+ `'style:$id'` tags but never a tradition tag, even though MartialArts'
own technique content (`martial_technique_content.dart`) already tags
individual techniques `'western'`/`'eastern'`. Adding one more
`AddTag(...)` call to `learnStyle` — `'western'` for Boxing, `'eastern'`
for Shaolin/Tai Chi — is the single line that makes this information
available on the entity, using vocabulary MartialArts already owns. This
is the "generic interoperability hook" the task explicitly permits: it
adds no Physique-specific vocabulary to MartialArts (Physique is never
mentioned), and any future plugin can read the same two tags for its own
purposes.

Verified safe: every existing MartialArts test asserting on the
entity's tags uses `containsAll`, never an exact-set `equals` — adding
one more tag breaks nothing.

## Runtime component

```dart
class PhysiqueComponent {
  const PhysiqueComponent(this.physiqueId);
  final String physiqueId;
}
```

Deliberately just the stable id — everything else (tags, primary
affinity, synergy modifiers) is data, resolved from
`ContentRegistry`/`ModifierCollection` when needed, never duplicated
onto the component.

## Content: definitions and the data/runtime split

`modifiers`/`affinities` aren't part of `ContentRegistry`'s native
vocabulary — `Modifier` isn't an `Effect`/`Condition`, the same gap that
kept MartialArts' items un-migrated in the prior pass. So, exactly
mirroring `martial_technique_content.dart`'s `baseDamage`/`damageStat`
pattern: these two fields land verbatim on `ContentDefinition.extra`,
and a small parser (`physiqueDefinitionFromContent`) turns that raw
shape into a typed `PhysiqueDefinition` whose `modifiersFor(character)`
builds real `Modifier` objects.

```json
{
  "id": "sturdy",
  "type": "physique",
  "tags": ["physique", "defense", "western_affinity"],
  "affinities": ["defense"],
  "modifiers": [
    {"stat": "defense", "operation": "multiply", "value": 1.25, "condition": "western"},
    {"stat": "defense", "operation": "multiply", "value": 0.85, "condition": "eastern"}
  ]
}
```

`affinities` is a list (today, always one element) rather than a bare
string, so a physique that later needs more than one affinity doesn't
need a schema change. Each `modifiers` entry's `condition` is a bare tag
name (`'western'`/`'eastern'`) — resolved into `HasTagQuery(name)`, Core's
existing generic query type. All four physiques, symmetrically:

| Physique | Primary affinity | Strong synergy | Anti-synergy |
|---|---|---|---|
| Sturdy | `defense` | western ×1.25 | eastern ×0.85 |
| Power | `strength` | western ×1.25 | eastern ×0.85 |
| Burst | `speed` | eastern ×1.25 | western ×0.85 |
| Endurance | `stamina` | eastern ×1.25 | western ×0.85 |

**"Neutral ×1.00" needs no explicit modifier.** `ModifierResolver`
already treats an empty active-modifier set as the identity — an entity
with neither `'western'` nor `'eastern'` simply has no active modifier
for that stat, which *is* neutral. Registering an explicit
always-active `×1.00` modifier would be redundant machinery for a
behavior the existing architecture already provides for free — this is
the one place the task's own "unless the existing engine architecture
suggests a better generic representation" carve-out applies.

`primaryAffinity` (`'defense'`/`'strength'`/`'speed'`/`'stamina'`) is an
arbitrary, caller-chosen stat name — exactly like `damageStat` on
`AttackAction`/`MartialTechniqueAction`. Physique never asks who reads
it; any future action (a Physique-aware attack, or eventually Magic/
Cultivation/Weapons content) that resolves one of these four stat names
through the Modifier Engine gets the synergy for free, with zero
additional code here.

## Random assignment

```dart
String initializePhysique(EntityId character, PluginContext context) {
  final existing = context.components.get<PhysiqueComponent>(character);
  if (existing != null) return existing.physiqueId;

  final physiqueId =
      PhysiqueTypes.all[context.rng.nextInt(PhysiqueTypes.all.length)];
  final definition =
      physiqueDefinitionFromContent(context.content.get(physiqueId));

  context.components.add(character, PhysiqueComponent(physiqueId));
  for (final modifier in definition.modifiersFor(character)) {
    context.modifiers.add(modifier);
  }
  context.events.publish(PhysiqueAssigned(character, physiqueId));
  return physiqueId;
}
```

A plain function, not a `Rule` reacting to `EntityCreated` — not every
entity Core creates is a character (battle entities, item entities, ...),
so entity-creation alone can't say "assign a physique now." This matches
`learnStyle`/`attuneToElement`/`equipItem`'s existing "explicit function,
caller decides when" idiom exactly, and is what "a generic plugin-owned
initialization API that future plugins could reuse" means here — it
lives in and is exported by PhysiquePlugin, but nothing about Physique
itself decides when a character is created; whoever does (a future
character-creation flow, a test, anything — never this plugin, and never
a game-specific `NewGameManager`) calls it explicitly.

Idempotent by construction (step 2 of the required behavior): a second
call on an already-physique'd character returns the existing id and
does nothing else — no duplicate component write, no duplicate modifier
registration, no duplicate event.

Uses only `context.rng` (`RngService`, already seeded and injected via
`PluginContext`) — `dart:math`'s `Random` never appears in this plugin,
satisfying the determinism requirement directly: the same seed feeding
the same `RngService` construction, called at the same point in a
sequence of prior draws, produces the same `nextInt` result and
therefore the same physique.

## Event

```dart
class PhysiqueAssigned {
  const PhysiqueAssigned(this.character, this.physiqueId);
  final EntityId character;
  final String physiqueId;
}
```

Physique's own event vocabulary, defined and published the same way
Combat defines and publishes `BattleStarted`/`ActionCompleted` — no
core changes needed, `EventBus` dispatch is already open to any event
type.

## Dependency graph

```
Core  <──  Combat  <──  MartialArts
Core  <──  Physique
```

`PhysiquePlugin.dependencies => const []`. No file under
`lib/src/plugins/physique/` references `martial_arts`/`example_...`/
`combat`; no file under `lib/src/plugins/martial_arts/` or
`lib/src/plugins/combat/` references `physique`. Extending the existing
automated `test/integration/architecture_dependency_test.dart` (built in
the prior cross-plugin-interop pass) to also check Physique in both
directions against MartialArts, and Combat against Physique, makes this
a permanent, CI-enforceable property rather than a one-time claim.

## File layout

```
lib/src/plugins/physique/
  physique_types.dart          # PhysiqueTypes (id constants + `all`)
  physique_component.dart      # PhysiqueComponent
  physique_content.dart        # PhysiqueDefinition, physiqueContentDefinitions,
                                # physiqueDefinitionFromContent
  physique_events.dart         # PhysiqueAssigned
  physique_initialization.dart # initializePhysique
  physique_plugin.dart         # PhysiquePlugin
lib/physique_plugin.dart       # public barrel
```

Mirrors MartialArts'/Elemental's existing file-per-responsibility shape
exactly — no new structural pattern introduced.

## Test plan

Maps directly onto the 12 required scenarios:

1–4 (exactly one physique; uses `RngService`; deterministic per seed;
different seeds can differ) — `physique_initialization_test.dart`:
construct two contexts with `RngService(sameSeed)` and assert identical
results across repeated `initializePhysique` calls on fresh characters;
construct with two different seeds and assert at least one of several
draws differs (a single draw isn't guaranteed to differ with only 4
outcomes, so the test samples enough draws to make a same-result-by-
chance false failure vanishingly unlikely, or directly asserts the
underlying `RngService.nextInt` sequence itself differs, which is
already covered by `rng_service_test.dart` — this plugin's test only
needs to prove *it uses* `context.rng`, not re-litigate `RngService`'s
own PRNG properties).

5–7 (Physique alone, MartialArts alone, both together) — new
`test/integration/physique_synergy_test.dart`, mirroring
`cross_plugin_synergy_test.dart`'s existing D/E/F shape.

8–11 (Sturdy/Power positive-western/negative-eastern; Burst/Endurance
positive-eastern/negative-western) — same file: for each of the four
physiques, load its `PhysiqueDefinition` directly (not through the
random `initializePhysique`, since these need a *specific*, guaranteed
physique), register its modifiers for a character, `learnStyle` a
matching-tradition and then a mismatched-tradition style onto separate
characters, and assert `ModifierResolver().resolve(100, activeModifiersFor(...))`
comes out to `125`/`85` respectively.

12 (no direct import) — extends
`test/integration/architecture_dependency_test.dart`'s existing
`_pluginBarrels` list and G/Combat-direction groups with Physique, the
same mechanism already proven sound for MartialArts/Elemental.

## Non-goals (explicit)

No fifth physique type, no Cultivation, no Magic, no rewrite of the
existing plugin architecture, no `ContentRegistry`/`PluginSdk` changes,
no `WesternSynergySystem`/`EasternSynergySystem`/
`MartialArtsPhysiqueSystem` class, no explicit "neutral" modifier, no
progression mechanics beyond the flat multipliers given.
