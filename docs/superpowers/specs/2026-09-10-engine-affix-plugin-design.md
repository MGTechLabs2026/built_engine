# Engine-Owned Affix API — `AffixPlugin`

**Status:** design, pending review
**Date:** 2026-09-10
**Repo:** `built_engine` (`MGTechLabs2026/built_engine`)
**Answers:** the client-authored forward request `Tome_client/docs/superpowers/specs/2026-09-10-engine-affix-identity-and-reward-api.md` (status **BLOCKED — engine API gap**). That document is the *requirements*; this is the *engine design* that satisfies them. When this milestone merges, the client's Task 0 in `Tome_client/docs/superpowers/plans/2026-09-10-engine-owned-affix-migration.md` consumes **this file** as its "Resolved Engine API" note.
**Engine revision this design is written against:** `60a1b65` (one milestone past the client's pinned `b43b4147`).

---

## 1. Problem

Tome has a client-owned affix system in `Tome_client/lib/core/engine/reward_affix.dart`:
it defines affix identity, labels, lean/affinity, mechanical effect, numeric magnitude,
reward rolling (weighted by physique tradition, with an independent per-slot "no affix"
chance), and the item/technique apply semantics. The engine's Almanac can already
*record* affix history (`AlmanacRecorder.recordAffixDiscovered`, keyed
`(affixId, affixEventId)`), but the engine owns **no canonical affix vocabulary, no
reward-affix resolver, and no acquisition-event identity**. The client therefore cannot
migrate to engine-owned affixes without an engine API addition.

**Goal:** a dedicated `AffixPlugin` that owns affix identity, canonical mechanics
(stat *and* non-stat), deterministic reward-slot selection, and authoritative
acquisition-event identity — enumerable from content, driven by the one `RngService`,
recorded through the existing Almanac — with the smallest new engine surface, and wired
end-to-end through the headless `runGame` harness so it carries its own regression
coverage before the client integrates.

---

## 2. Resolved design decisions

Settled during brainstorming (2026-09-10):

| # | Decision |
|---|----------|
| D1 | **Dedicated `AffixPlugin`** under `lib/src/plugins/affix/`, barrel `package:build_engine/affix_plugin.dart`. Not a core `lib/src/reward/` verb, not split across the Item/Technique plugins. Affixes cross-cut items and techniques; a standalone content plugin mirrors `ConsumablePlugin` and keeps `ItemPlugin`/`TechniquePlugin` unchanged. |
| D2 | **Content type `'affix'`**, one `ContentDefinition` per affix, enumerated via `registry.allOfType('affix')` / `registry.withTag('affix_pool:<slot>')`. No client table; no second engine list. |
| D3 | **Each affix carries exactly one `AffixMechanic`** — a closed union `WeaponStatBonus(amount)` / `ImmediateHeal(amount)` / `BankProgression(amount)`. Not an `Effect` list: an item affix's stat target is resolved from the *item* at apply time (§6.1), so it cannot be fixed in content; and §8.1 of the requirements demands non-stat effects be first-class, not label-inferred. The union *is* the whole supported mechanic surface for v1; adding a variant is a content + `affix_application.dart` change, nothing else. |
| D4 | **Reward-slot selection is a small engine function on the resolver, pools are content.** The affinity weighting (`neutral` weight 2, favoured `lean` 3, opposite 1) and the per-slot `noAffixChance` are engine-owned rule code — exactly the logic being deleted from the client. The eligible affix ids per `(domain, slotKind)` are content (`affix_pool:*` tags). `RewardDefinition`/`RewardCandidate`/`RewardResolver` are **not** reused — their static `weight` cannot express affinity weighting, and bending them here is the over-design the requirements §5.1 warns against. |
| D5 | **`AffixResolution` is immutable and ordered** — a fixed-length-2 `List<AffixResolvedSlot>`, each `{position, slotKind, affix?}` where `slotKind ∈ {'prefix','suffix'}` is a **presentation hint on the slot**, not domain identity, and `affix == null` means "no affix for this slot". This gives the client its positional name-assembly convention (`<prefix> base <suffix>`) without the client owning affix identity or slot policy. |
| D6 | **One `affixEventId` per affix, not per reward.** A prefix+suffix reward produces two `AffixAcquisition`s with two event ids. Cleanest fit for the existing `(affixId, affixEventId)` Almanac idempotency key; makes the client's "two genuine acquisitions" vs "replay" tests unambiguous. |
| D7 | **The engine reward/run layer mints `affixEventId`** (requirements §10 "Preferred" producer). `acquireAffixes(...)` returns `AffixAcquisition`s carrying the id; the composition layer (client `RewardAdapter`, harness bridge) may only **forward** it to `recordAffixDiscovered`. No composition-minted substitute is ever required for Almanac correctness. |
| D8 | **Resolve once, at reward generation.** `resolveRewardAffixes(...)` is the sole RNG path; its result is carried by value through preview and TAKE. There is no re-resolve-on-read API. Preview consumes no RNG, writes no Almanac, mutates no state (requirements §7). |
| D9 | **RNG draw order is specified and engine-owned** (§5.3), so the headless harness and the client produce identical sequences from a seed. |
| D10 | **`recordAffixUsed` stays unused** — v1 is discovery-only. An item affix "biting while hung" is not a use event. Explicit non-goal (§11). |
| D11 | **Content port:** the 33 affix entries in `reward_affix.dart` move into `affix_content.dart` verbatim in label, magnitude, and lean — 11 item prefixes, 9 item suffixes, 7 technique prefixes, 6 technique suffixes. Two labels appear in two pools each (`Flowing`, `of Still Water`), so 33 entries / 31 distinct labels. Ids are freshly minted opaque tokens (`af_keen`, `af_of_the_ember`, …), **never derived from the label** (requirements §4.1). |
| D12 | **Full end-to-end harness wiring** — `reward_stage.dart`, `run_content.dart`, `run_events.dart`, `almanac_bridge.dart`, `game_run.dart` — so a `runGame` exercises roll → apply → record, and `_buildSnapshot`'s currently-stubbed `affixes` / `affixCategories` carry real values (§7). |

---

## 3. Existing surface this builds on (no change)

| Symbol | Barrel | Used how |
|---|---|---|
| `ContentDefinition` (`type`, `tags`, `extra`), `ContentRegistry.load*` / `allOfType` / `withTag` | `build_engine.dart` | affix content storage + enumeration |
| `RngService` (`nextDouble`, `nextInt`, `chance`) | `build_engine.dart` | the one RNG for slot resolution |
| `weightedPick<T>` | internal (`lib/src/rng/`) | the affinity-weighted draw within a slot |
| `PhysiqueTraditions.western` / `.eastern`, `PhysiqueDefinition.primaryAffinity` | `physique_plugin.dart` | maps a fighter's tradition → favoured `lean` |
| `ItemInstance.statBonuses`, `addItemStatBonuses(instance, {stat: n}, context)` | `item_plugin.dart` | `WeaponStatBonus` application |
| `WeaponStatTags.matchOrFallback(tags, fallback)` | `item_plugin.dart` | resolves an affixed item's stat target |
| `itemDefinition(id, context)` | `item_plugin.dart` | tag lookup for stat-target resolution |
| `HealthComponent`, `context.resources.add`, `ItemResources.upgradePoints` | `build_engine.dart` / `item_plugin.dart` | `ImmediateHeal` / `BankProgression` application |
| `AlmanacRecorder.recordAffixDiscovered({affixId, observation, snapshot, timestamp})`, `AffixObservation`, `AffixSnapshot`, `AlmanacQueries.getAffixHistory` | `almanac.dart` | recording — **stays in `almanac.dart`, not re-exported by the affix barrel** |
| `GamePlugin`, `PluginSdk` (`registerContentBatch`, `registerTag`, `disposeAll`) | `build_engine.dart` | plugin scaffolding, copied from `ConsumablePlugin` |
| headless: `RewardStage`, `run_content.dart`, `run_events.dart`, `HeadlessGameAlmanacBridge`, `game_run.dart` | `game.dart` | end-to-end wiring (§7) |

---

## 4. `AffixPlugin` module

New `lib/src/plugins/affix/`:

| File | Responsibility |
|---|---|
| `affix_plugin.dart` | `GamePlugin` (`id: 'affix'`, `version: '0.1.0'`). `initialize`: `registerTag('affix', …)`, the `lean:neutral/force/flow` and `affix_pool:item_prefix/item_suffix/technique_prefix/technique_suffix` tags, then `sdk.registerContentBatch(affixContentDefinitions)` behind the same load-once `context.content.find(...) == null` guard `ItemPlugin` uses. No rules, no components, no resources. `unregister`: `sdk.disposeAll()`. |
| `affix_types.dart` | `enum AffixLean { neutral, force, flow }`; `abstract final class AffixCategories { itemPrefix, itemSuffix, techniquePrefix, techniqueSuffix }`; `abstract final class AffixPoolTags { … }`. |
| `affix_mechanic.dart` | `sealed class AffixMechanic` + `WeaponStatBonus(num amount)`, `ImmediateHeal(num amount)`, `BankProgression(num amount)`. `factory AffixMechanic.fromJson(Map)` dispatching on `kind` (`weapon_stat_bonus` / `heal` / `bank_progression`); throws `ContentFieldException` on an unknown kind or a missing `amount`. |
| `affix_definition.dart` | `class AffixDefinition { String id; String label; String category; AffixLean lean; AffixMechanic mechanic; }` + `affixDefinitionFromContent(ContentDefinition)` (reads `extra['label']`, `extra['category']`, the `lean:*` tag, `extra['mechanic']`) + `affixDefinition(String id, PluginContext) => affixDefinitionFromContent(context.content.get(id))`. Immutable; no caching; mirrors `itemDefinitionFromContent`. |
| `affix_content.dart` | `const affixContentDefinitions = <Map<String,dynamic>>[ … ]` — the 30 ported entries (§8). |
| `affix_resolver.dart` | `AffixRewardContext`, `AffixResolution`, `AffixResolvedSlot`, `resolveRewardAffixes(...)` (§5). |
| `affix_application.dart` | `applyAffixMechanic(AffixDefinition, AffixApplicationTarget, PluginContext) → ({String? stat})` (§6). |
| `affix_acquisition.dart` | `AffixAcquisition`, `RunRef`, `acquireAffixes(...)` (§6.4). |

### 4.1 Content shape

```json
{
  "id": "af_keen",
  "type": "affix",
  "tags": ["affix", "affix_pool:item_prefix", "lean:neutral"],
  "label": "Keen",
  "category": "item_prefix",
  "mechanic": { "kind": "weapon_stat_bonus", "amount": 3 }
}
```

```json
{
  "id": "af_grounding",
  "type": "affix",
  "tags": ["affix", "affix_pool:technique_prefix", "lean:force"],
  "label": "Grounding",
  "category": "technique_prefix",
  "mechanic": { "kind": "heal", "amount": 12 }
}
```

`label`, `category`, `mechanic` land in `ContentDefinition.extra` (the registry parser
already routes unknown top-level keys there — confirmed in `content_registry.dart`
`_parse`). `lean` is a tag so `withTag` / balancing tools can slice on it; it is also
mirrored onto `AffixDefinition.lean` for the resolver. `category` is **not** a tag — it
is display/almanac data, read only from `extra`.

**Id opacity.** `id` is a hand-assigned `af_<slug>` token. The slug is a convenience for
humans reading content; nothing parses it. `label` is the only display string and it is
deterministic from the definition (requirements §4.1 — no lore table).

---

## 5. Selection & resolution

### 5.1 Inputs

```dart
class AffixRewardContext {
  const AffixRewardContext({required this.domain, required this.physiqueTradition});
  final AffixDomain domain;             // enum { item, technique }
  final String? physiqueTradition;      // PhysiqueTraditions.western | .eastern | null
}
```

`physiqueTradition` is resolved by the **caller** (harness `RewardStage` / client
`RewardAdapter`) from the fighter's physique — the resolver never reaches into component
state. `null` (or any unrecognized value) leaves every `lean` at weight 2 (a flat draw),
matching `reward_affix.dart`'s current `_ => null` branch.

### 5.2 Output — immutable, ordered

```dart
class AffixResolution {
  const AffixResolution(this.slots);
  final List<AffixResolvedSlot> slots;   // length 2, position order: [prefix, suffix]
}

class AffixResolvedSlot {
  const AffixResolvedSlot({required this.position, required this.slotKind, required this.affix});
  final int position;          // 0 | 1
  final String slotKind;       // 'prefix' | 'suffix' — presentation hint, NOT identity
  final AffixDefinition? affix; // null == "no affix" for this slot
}
```

Both classes are `const`-constructible value types with structural equality
(`package:equatable` or manual `==`/`hashCode`, matching the file's neighbours). A caller
holds one `AffixResolution` for the life of a reward offer and reads it freely.

Four requirement-visible states, one per `(slot0.affix == null?, slot1.affix == null?)`
combination: `none` / `prefix only` / `suffix only` / `prefix + suffix`. None can
collapse — `slots` is always length 2.

### 5.3 Algorithm (RNG order is normative)

```
resolveRewardAffixes(ctx, rng):
  favoured = { western: force, eastern: flow, _: null }[ctx.physiqueTradition]
  slots = []
  for slotKind in ['prefix', 'suffix']:            # position order, fixed
    poolTag = 'affix_pool:' + domainName(ctx.domain) + '_' + slotKind
    pool = registry.withTag(poolTag) -> [AffixDefinition]
    # draw 1: "no affix" for this slot
    if rng.nextDouble() < kNoAffixChance or pool.isEmpty:
      slots.add(AffixResolvedSlot(position, slotKind, affix: null))
      continue
    # draw 2: weighted pick within the slot
    weightOf(def) = def.lean == neutral ? 2
                  : favoured == null    ? 2
                  : def.lean == favoured ? 3 : 1
    chosen = weightedPick(pool, weightOf, rng)      # never null: pool non-empty, weights > 0
    slots.add(AffixResolvedSlot(position, slotKind, affix: chosen))
  return AffixResolution(slots)
```

- `kNoAffixChance = 0.34` — a `const` in `affix_resolver.dart`, ported from
  `reward_affix.dart`. Not a per-pool content field in v1 (YAGNI; one value today).
- **Exactly two `rng` reads per slot** in the affix-bearing case, one in the
  no-affix case — `rng.nextDouble()` then, if kept, `weightedPick`'s single
  `rng.nextDouble()`. Callers that drew the reward-pool pick from the same
  `RngService` **before** calling this get a stable, documented sequence.
- `weightedPick` is the existing shared helper; reused, not re-implemented.

### 5.4 Purity

`resolveRewardAffixes` touches only `registry` (read) and `rng`. It writes nothing, and
the `AffixResolution` it returns is inert data. Preview = reading that object.

---

## 6. Mechanical application

### 6.1 Target

```dart
sealed class AffixApplicationTarget {}
class ItemInstanceTarget   extends AffixApplicationTarget { final EntityId instance; final String itemId; }
class CharacterTarget      extends AffixApplicationTarget { final EntityId character; }
```

Item-domain rewards pass `ItemInstanceTarget` (the freshly-owned copy);
technique-domain rewards pass `CharacterTarget`.

### 6.2 `applyAffixMechanic`

```dart
({String? stat}) applyAffixMechanic(
  AffixDefinition def, AffixApplicationTarget target, PluginContext context)
```

| `def.mechanic` | Action | Returns `stat` |
|---|---|---|
| `WeaponStatBonus(a)` | require `ItemInstanceTarget`; `stat = WeaponStatTags.matchOrFallback(itemDefinition(t.itemId, context).tags, 'item:${t.itemId}')`; `addItemStatBonuses(t.instance, {stat: a}, context)` | that `stat` |
| `ImmediateHeal(a)` | require `CharacterTarget`; read `HealthComponent`, write back `current: min(current + a, max)` | `null` |
| `BankProgression(a)` | require `CharacterTarget`; `context.resources.add(t.character, ItemResources.upgradePoints, a)` | `null` |

A mechanic/target mismatch (`WeaponStatBonus` with a `CharacterTarget`, or either
non-stat mechanic with an `ItemInstanceTarget`) throws `ArgumentError` — it is a
composition bug, never reachable from validated content, because the `affix_pool:*` tag
that puts a definition in a slot is what decides the domain. **Content-parse validation
(§9) enforces the tag ⇒ mechanic-family correspondence**, so the throw is a
belt-and-braces guard, not a runtime branch the game relies on.

`ImmediateHeal` / `BankProgression` amounts match `reward_affix.dart`'s current
`_applyTechniqueAffix` exactly (heal via `HealthComponent` clamp, bank via
`ItemResources.upgradePoints`). `WeaponStatBonus` reproduces
`reward_adapter.dart`'s current `addItemStatBonuses(instance, {stat: total}, …)` — with
the important change that **each slot applies independently** (`+3` then `+4`), not a
pre-summed `total`; `addItemStatBonuses` already accumulates into `statBonuses`, so two
calls == one call with the sum.

### 6.3 Why not an `Effect` list

`ContentDefinition` already parses `effects: List<Effect>` and the built-ins include
`heal` / `modifyStat` / `modifyResource`. Rejected because:

1. A `WeaponStatBonus` has **no stat in content** — it is `WeaponStatTags`-resolved from
   the target item. An `Effect` would need a new `modifyWeaponStat` factory that only
   makes sense for weapon-tagged items, plus a resolution hook at apply time — more
   surface than the union, for one caller.
2. `heal` / `modifyResource` `Effect`s apply through `RuleContext`; the reward path is a
   direct composition call, not a rule fire. Routing affix application through the rule
   engine to reuse two `Effect` classes is heavier than three `switch` arms.
3. The union makes `AffixSnapshot` derivation (§6.4) a total function with no
   interpretation.

The `AffixMechanic` union is the minimal representation of "every supported affix
effect type … without requiring the client to infer semantics from labels"
(requirements §8.1).

### 6.4 Acquisition — apply, then describe, then hand back identity

```dart
class RunRef { final String runId; final int runNumber; }

class AffixAcquisition {
  final String affixId;
  final String affixEventId;          // engine-minted, opaque
  final AffixObservation observation; // AffixObservation(affixEventId, runId, runNumber)
  final AffixSnapshot snapshot;       // AffixSnapshot(affixId, stat, value, category)
}

List<AffixAcquisition> acquireAffixes({
  required AffixResolution resolution,
  required AffixApplicationTarget target,
  required RunRef run,
  required PluginContext context,
})
```

For each slot with `affix != null`, in position order:

1. `stat = applyAffixMechanic(slot.affix!, target, context).stat` — mechanics land now.
2. `affixEventId = _mintAffixEventId(run, slot)` — see §6.5.
3. `snapshot = AffixSnapshot(affixId: slot.affix!.id, stat: stat, value: slot.affix!.mechanic.amount, category: slot.affix!.category)`.
4. `observation = AffixObservation(affixEventId: affixEventId, runId: run.runId, runNumber: run.runNumber)`.
5. append `AffixAcquisition(...)`.

A `null` slot yields nothing. `acquireAffixes` **does not record** — it returns the
list; the composition layer calls `recordAffixDiscovered` per element (client keeps
Almanac wiring at its own composition root; harness bridge does it on an event). This is
the requirements §10 "Preferred" split: engine produces the canonical taken-reward
result carrying `(affixId, affixEventId)`; composition forwards.

`acquireAffixes` takes no `RngService` — no v1 mechanic needs a draw. If a future
mechanic does, it gets its own `rng` parameter then.

### 6.5 `affixEventId` minting

```dart
String _mintAffixEventId(RunRef run, AffixResolvedSlot slot) =>
    '${run.runId}:affix:${slot.position}:${_acquisitionSeq++}';
```

- One id **per affix** (D6): a prefix+suffix reward calls this twice, two ids.
- The seq counter makes **two genuine acquisitions of the same affix in one run**
  produce **distinct** ids → the Almanac keeps one `AlmanacAffixRecord` with two
  discovery observations (the client's "Test A").
- **Replaying the identical acquisition** means re-feeding the *same*
  `AffixAcquisition` object (same `affixEventId`) to `recordAffixDiscovered` — the
  Almanac's `(affixId, affixEventId)` `_appendUnique` makes that a no-op (the client's
  "Test B"). The engine never re-mints for a replay because a replay does not call
  `acquireAffixes` again.
- The counter is **acquisition-context-local**, exactly like
  `HeadlessGameAlmanacBridge`'s `_usageSeq` / `_trainingSeq` / `_buildSeq`. In the
  harness it lives on the object that owns the run's reward loop (`RewardStage`); in the
  client it lives on `RewardAdapter`. The string is opaque downstream — the
  `AffixObservation` carries `runId` / `runNumber` as explicit fields and *those*, never
  the id, are how a relationship is read. Matches the Almanac module's stated id
  discipline ("no key is ever parsed").

> **Why a counter and not a UUID.** The requirements §9.1 forbid a
> *composition-minted* substitute (client UUID / timestamp / random-at-TAKE) because
> those break replay idempotency. An **engine-minted** monotonic-per-run token is
> authoritative, is stable for a given acquisition, and distinguishes genuine repeats
> from replays — which is the entire contract. `runId` is already an opaque
> caller-supplied token in the harness (`HeadlessGameAlmanacBridge.runId`, "never
> `'run_$seed'`"); the affix id extends the same scheme.

---

## 7. Headless harness wiring (end-to-end)

| File | Change |
|---|---|
| `lib/src/plugins/game/game_run.dart` | `AffixPlugin().initialize(context)` after `ConsumablePlugin` (line ~191). It reads `item`/`technique` content domains, so it initializes after both. |
| `lib/src/plugins/game/run_content.dart` | no new roster constant needed — pools come from `affixContentDefinitions` via `withTag`. Add a doc line pointing at `AffixPlugin` as the affix source. |
| `lib/src/plugins/game/reward_stage.dart` | in `resolveReward`, `RewardKind.itemOrTechnique` branch: after `ownItem(...)` / `discoverTechnique(...)`, build `AffixRewardContext` (domain from `entry.referenceType`, `physiqueTradition` from the character's physique — `RewardStage` gains a `physiqueTradition` field set at construction), call `resolveRewardAffixes(ctx, context.rng)` — **the resolver draw comes right after `rewardIndex++`, i.e. after the pool pick, per §5.3** — then `acquireAffixes(resolution, target, RunRef(runId, runNumber), context)`. For each `AffixAcquisition`, `events.publish(AffixAcquired(...))`. Return string becomes `item:iron_sword+af_keen+af_of_the_ember` (base id, then each non-null slot's affix id in position order; unchanged when no affix rolls). `RewardStage` needs `runId` / `runNumber` (already available to `runGame`) and the character's `RngService` handle — it currently gets `context`, which exposes `rng`. |
| `lib/src/plugins/game/run_events.dart` | new telemetry type `class AffixAcquired { final String affixId; final String affixEventId; final String category; final String rewardBaseId; }`. Added to the events table doc. Not a domain fact — a run telemetry point, same tier as `RewardSelected`. |
| `lib/src/plugins/game/almanac_bridge.dart` | subscribe `AffixAcquired` in `attach`; handler calls `_recorder.recordAffixDiscovered(affixId:, observation: AffixObservation(affixEventId:, runId:, runNumber:), snapshot:, timestamp: DateTime.now())`. The bridge already holds `runId`/`runNumber`. It reconstructs `AffixObservation`/`AffixSnapshot` from the event fields — **or** the event carries the ready `AffixAcquisition` (preferred: no reconstruction, one import). `_buildSnapshot` stops hard-coding `affixes: const <AffixSnapshot>[]` / `affixCategories: const <String>[]` — it accumulates the run's `AffixSnapshot`s (from the same event stream) and passes them to `AlmanacBuildRecord.affixes` and `buildDna(affixCategories: …)`. |

**Composition boundary note.** `almanac_bridge.dart` is already "the only in-repo file
that imports both a gameplay plugin and the Almanac — by design". Adding the affix
subscription keeps that property; the affix *recording* call stays in the bridge, the
affix *identity* comes from `AffixAcquisition` on the event, the affix *plugin* never
imports `almanac.dart`.

---

## 8. Ported content (D11)

33 entries, `label` / magnitude / lean verbatim from `reward_affix.dart`. Mechanic
family is fixed by pool:

| Pool tag | Count | `mechanic.kind` | Source constant |
|---|---|---|---|
| `affix_pool:item_prefix` | 11 | `weapon_stat_bonus` | `itemPrefixes` |
| `affix_pool:item_suffix` | 9 | `weapon_stat_bonus` | `itemSuffixes` |
| `affix_pool:technique_prefix` | 7 | `heal` or `bank_progression` (per entry) | `techniquePrefixes` |
| `affix_pool:technique_suffix` | 6 | `heal` or `bank_progression` (per entry) | `techniqueSuffixes` |

`category` = the pool name (`item_prefix` etc.). `lean` tag from the source
`AffixLean`. `amount` = the source `amount`. The source `blurb` string is **dropped** —
it was client presentation prose; the client composes its own descriptor from
`category` + `stat`/`value` (client plan Task 3/8). Ids: `af_` + snake-cased label with
`of_the_`/`of_` kept (`af_of_the_ember`, `af_hard_won`, `af_of_still_water`). The
`AffixLean` enum values used by content: `neutral` / `force` / `flow`.

Example subset:

```
af_plain          item_prefix   neutral  weapon_stat_bonus 1
af_sturdy         item_prefix   neutral  weapon_stat_bonus 2
af_keen           item_prefix   neutral  weapon_stat_bonus 3
af_ember_forged   item_prefix   force    weapon_stat_bonus 6
af_whispering     item_prefix   flow     weapon_stat_bonus 3
af_of_the_ember   item_suffix   force    weapon_stat_bonus 4
af_of_still_water item_suffix   flow     weapon_stat_bonus 5
af_hard_won       technique_prefix  neutral  bank_progression 1
af_grounding      technique_prefix  force    heal             12
af_serene         technique_prefix  flow     heal             10
af_of_the_rising_sun  technique_suffix  force  heal            14
af_of_the_coiled_spring technique_suffix flow  bank_progression 2
```

(`af_flowing` appears in both `techniquePrefixes` as `heal 14` and `itemPrefixes` as
`weapon_stat_bonus 4` in the source — the two get distinct ids: `af_flowing`
(item_prefix) and `af_flowing_technique` (technique_prefix). Labels can collide;
**ids cannot**.)

---

## 9. Content-parse validation

`AffixPlugin.initialize` validates each entry after `registerContentBatch` (or a
`affixContentDefinitions`-level assertion helper, matching how `ItemPlugin` post-processes
its batch for mastery defs):

- `extra['label']` — non-empty `String`.
- `extra['category']` — one of the four `AffixCategories`.
- exactly one `lean:*` tag, value in `{neutral, force, flow}`.
- exactly one `affix_pool:*` tag; its `(domain, slotKind)` must agree with `category`.
- `extra['mechanic']` parses via `AffixMechanic.fromJson`; **`weapon_stat_bonus` ⇔
  `affix_pool:item_*`**, **`heal`/`bank_progression` ⇔ `affix_pool:technique_*`**.
- `amount` > 0.

A violation throws `ContentValidationException` / `ContentFieldException` at
`initialize` — a fail-loud content bug, never a runtime surprise.

---

## 10. Public surface (`lib/affix_plugin.dart`)

```dart
export 'src/plugins/affix/affix_plugin.dart'      show AffixPlugin;
export 'src/plugins/affix/affix_types.dart';       // AffixLean, AffixCategories, AffixDomain
export 'src/plugins/affix/affix_mechanic.dart';    // AffixMechanic + 3 variants
export 'src/plugins/affix/affix_definition.dart'   show AffixDefinition, affixDefinition, affixDefinitionFromContent;
export 'src/plugins/affix/affix_content.dart'      show affixContentDefinitions;
export 'src/plugins/affix/affix_resolver.dart';    // AffixRewardContext, AffixResolution, AffixResolvedSlot, resolveRewardAffixes, kNoAffixChance
export 'src/plugins/affix/affix_application.dart'  show applyAffixMechanic, AffixApplicationTarget, ItemInstanceTarget, CharacterTarget;
export 'src/plugins/affix/affix_acquisition.dart'; // AffixAcquisition, RunRef, acquireAffixes
```

`AffixSnapshot` / `AffixObservation` / `recordAffixDiscovered` are **not** re-exported —
they stay the `almanac.dart` surface. The affix plugin depends on `almanac.dart` only in
`affix_acquisition.dart` (to construct `AffixSnapshot` / `AffixObservation`), which is
acceptable: the acquisition type is the seam between the two. If that dependency is
judged undesirable, the fallback is `acquireAffixes` returning a plain
`({String affixId, String affixEventId, String? stat, num value, String category, String runId, int runNumber})`
record and the composition layer building the Almanac value objects — one extra line at
each of the two call sites. **Decision: keep the `almanac.dart` import in
`affix_acquisition.dart`**; it is the natural home for the seam and both call sites stay
trivial.

---

## 11. Non-goals

- No `recordAffixUsed` path — discovery only (D10).
- No Almanac schema change — `AffixSnapshot` / `AffixObservation` / `AlmanacAffixRecord`
  are used as-is.
- No `RewardDefinition` / `RewardCandidate` / `RewardResolver` change.
- No `CodexRepository` (that is client-only anyway).
- No per-pool `noAffixChance` content field, no rarity field, no reward-context
  weighting beyond physique tradition — v1 ports exactly what `reward_affix.dart` does.
- No prefix/suffix as domain identity — `slotKind` is a slot-level presentation hint.
- No second RNG — `resolveRewardAffixes` is the only draw; `acquireAffixes` takes none.
- No client-facing visual/format concerns.
- No migration of pre-existing player data — affixes were never recorded before, so a
  fresh Almanac simply has an empty affix roster that fills in.

---

## 12. Acceptance criteria

Maps 1:1 onto the client forward request's §13. The engine milestone is complete when:

**Identity & enumeration**
- [ ] `affixContentDefinitions` holds all 33 ported affix entries; every `id` is an
      opaque `af_*` token, none derived from `label`; the two cross-pool labels get
      distinct ids.
- [ ] `registry.allOfType('affix')` returns them; `registry.withTag('affix_pool:item_prefix')`
      returns exactly the 11 item prefixes; likewise the other three pools.
- [ ] the client cannot reproduce the roster without this content — no engine-side
      duplicate list, no fallback.

**Selection**
- [ ] `resolveRewardAffixes` selects through `RngService` only; same seed + context →
      identical `AffixResolution`; a different seed may differ.
- [ ] affinity weighting matches `reward_affix.dart`: `western`→`force` favoured,
      `eastern`→`flow` favoured, `neutral` always weight 2, unknown tradition → flat.
- [ ] across seeds, all four slot states occur for both domains: `none`,
      `prefix only`, `suffix only`, `prefix + suffix`; `slots` is always length 2.
- [ ] RNG draw order per §5.3 is asserted (a fixed seed drives a fixed sequence of
      `rng` reads, and a preceding reward-pool pick from the same service is
      unperturbed).

**Offer stability & purity**
- [ ] a held `AffixResolution` is equal to itself on repeat reads; no method on it
      consumes RNG or mutates state.
- [ ] nothing between `resolveRewardAffixes` and `acquireAffixes` re-rolls a slot.

**Mechanics**
- [ ] `WeaponStatBonus` → `ItemInstance.statBonuses` gains `{resolvedStat: amount}` via
      `addItemStatBonuses`, stat resolved by `WeaponStatTags.matchOrFallback`; two
      slots apply independently and sum in `statBonuses`.
- [ ] `ImmediateHeal` → `HealthComponent.current` rises by `amount`, clamped to `max`.
- [ ] `BankProgression` → `ItemResources.upgradePoints` rises by `amount`.
- [ ] recorded `AffixSnapshot` fields equal the canonical `AffixDefinition`
      (`value == mechanic.amount`, `category` verbatim, `stat` set for weapon bonus /
      null for heal/bank) — never a client constant.

**Acquisition identity**
- [ ] `acquireAffixes` mints one `affixEventId` per non-null slot; a prefix+suffix
      reward → two `AffixAcquisition`s.
- [ ] two genuine acquisitions of one affix in a run → two distinct `affixEventId`s →
      one `AlmanacAffixRecord`, two discovery observations.
- [ ] re-feeding one `AffixAcquisition` to `recordAffixDiscovered` is idempotent.
- [ ] no composition-minted id is needed for correctness.

**Wiring & exports**
- [ ] `lib/affix_plugin.dart` exports the §10 surface; `dart analyze` clean.
- [ ] a full `runGame` seed exercises roll → apply → `recordAffixDiscovered`, and the
      resulting `AlmanacState.affixes` / `AlmanacBuildRecord.affixes` /
      `buildDna(affixCategories:)` carry real values (no stub `const []`).
- [ ] headless unit tests cover definition load, id opacity, resolver determinism +
      weighting + four states, offer stability, all three mechanics, per-affix event
      identity, idempotent re-record, serialization round-trip.
- [ ] `flutter test` (or `dart test`) green; no unrelated test weakened.

---

## 13. Client-side follow-up (informational — not this milestone)

When this merges, the client's Task 0 pins the new revision and maps its
`// SPEC §N` placeholders to:

| Client placeholder | This design |
|---|---|
| `AffixDefinition`, `registry.allOfType('affix')` | §4, §4.1 |
| affix roll / reward-candidate integration | `resolveRewardAffixes` (§5) |
| taken-reward result carrying `affixId` + `affixEventId` | `AffixAcquisition` (§6.4) |
| slot container shape (`prefix?`/`suffix?` vs list vs handles) | ordered `List<AffixResolvedSlot>` length 2, `slotKind` hint (§5.2) |
| one event vs one-per-affix | one per affix (D6, §6.5) |
| `AlmanacRecorder.recordAffixDiscovered`, `AlmanacRepository`, `AlmanacSerialization` | unchanged `almanac.dart` — client already targets these |

The client's `RewardAdapter` calls `resolveRewardAffixes` in `offerLoot()` (storing the
`AffixResolution`), reads it during preview, and in `applyLoot` calls `acquireAffixes`
then forwards each `AffixAcquisition` to its `AlmanacSession.recorder`. `_applyTechniqueAffix`,
the `Affix`/`AffixEffect`/`AffixLean` client types, and `reward_affix.dart` are deleted.
