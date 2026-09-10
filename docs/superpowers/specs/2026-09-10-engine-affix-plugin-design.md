# Engine-Owned Affix API — `AffixPlugin`

**Status:** implemented — feat/engine-affix-plugin, commits 86ed228..97bf1d6
**Date:** 2026-09-10
**Revised:** 2026-09-10 — acquisition identity given a single engine owner (`AffixAcquisitionIdSource`); `AffixAcquired` carries the whole `AffixAcquisition`; the affix plugin drops its `almanac.dart` dependency (`AffixAcquisition` is a plain engine record).
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
| D6 | **One `affixEventId` per acquired affix.** A reward that fills both slots produces two `AffixAcquisition`s with two distinct event ids; a one-slot reward produces one; a no-affix reward produces none. This is the natural granularity for the Almanac's `(affixId, affixEventId)` idempotency key and makes "two genuine acquisitions" vs "replay of one acquisition" unambiguous. |
| D7 | **Acquisition identity has exactly one owner: `AffixAcquisitionIdSource`**, a `build_engine` type (requirements §10 producer contract). One instance is created **per run by the engine reward/run layer** — headless: `game_run.dart` builds it next to `RngService(seed)` and threads it through `RewardStage`; client: the `lib/core/engine/` integration boundary builds it as per-run engine state and injects it into `RewardAdapter` like any other engine adapter. `acquireAffixes(...)` is the **only** caller of `idSource.next(...)`. `RewardAdapter` holds no counter and no allocator, never constructs an `affixEventId`, and only forwards `AffixAcquisition.affixEventId` verbatim to the recorder. The source is a deterministic monotonic counter — no RNG. **Uniqueness boundary:** the sequence guarantees distinct `affixEventId`s *within one logical run*; a logical run is identified by its `runId`, and distinct logical runs must supply distinct `runId`s (the engine does not guarantee uniqueness if a caller deliberately reuses a `runId`). A replay re-sends an existing `AffixAcquisition` and never reaches the source. |
| D8 | **Resolve once, at reward generation.** `resolveRewardAffixes(...)` is the sole RNG path; its result is carried by value through preview and TAKE. There is no re-resolve-on-read API. Preview consumes no RNG, writes no Almanac, mutates no state (requirements §7). |
| D9 | **RNG draw order is specified and engine-owned** (§5.3), so the headless harness and the client produce identical sequences from a seed. |
| D10 | **`recordAffixUsed` stays unused** — v1 is discovery-only. An item affix "biting while hung" is not a use event. Explicit non-goal (§11). |
| D11 | **Content port:** the 33 affix entries in `reward_affix.dart` move into `affix_content.dart` verbatim in label, magnitude, and lean — 11 item prefixes, 9 item suffixes, 7 technique prefixes, 6 technique suffixes. Two labels appear in two pools each (`Flowing`, `of Still Water`), so 33 entries / 31 distinct labels. Ids are freshly minted opaque tokens (`af_keen`, `af_of_the_ember`, …), **never derived from the label** (requirements §4.1). |
| D12 | **Full end-to-end harness wiring** — `reward_stage.dart`, `run_content.dart`, `run_events.dart`, `almanac_bridge.dart`, `game_run.dart` — so a `runGame` exercises roll → apply → record, and `_buildSnapshot`'s currently-stubbed `affixes` / `affixCategories` carry real values (§7). |
| D13 | **`AffixAcquisition` is a plain engine-domain record** — `affixId` (`String`), `affixEventId` (`String`), `runId` (`String`), `runNumber` (`int`), `stat` (**non-null `String`**), `value` (`num`), `category` (`String`). `stat` is a canonical engine-defined semantic identifier for the Almanac, **never a display label**, and is the **target-independent mechanic-kind string**: `WeaponStatBonus` → `'weapon_stat_bonus'` (**not** the resolved weapon stat), `ImmediateHeal` → `'heal'`, `BankProgression` → `'bank_progression'`. It matches the frozen non-nullable `AffixSnapshot.stat`. Rationale: `AffixSnapshot` holds exactly one canonical snapshot per `affixId` for the life of an `AlmanacRecorder` (`_upsertAffix`→`_fill` rejects a non-equal snapshot for the same `affixId`), so a per-target `stat` value is unrepresentable — a 2nd affix-bearing run (shared or hydrated recorder) that rolls the same affix on a different item type would feed a conflicting snapshot and raise `AlmanacIntegrityException`. The engine **still binds the resolved `WeaponStatTags` stat to `ItemInstance.statBonuses`** via `addItemStatBonuses`; only the Almanac snapshot's `stat` is the target-independent kind. The record carries no `almanac.dart` type; `affix_acquisition.dart` does not import `almanac.dart` and the affix plugin has **zero** Almanac coupling. The composition boundary builds `AffixObservation` / `AffixSnapshot` from these fields. |
| D14 | **`AffixAcquired` carries the whole `AffixAcquisition`** (plus `rewardBaseId`). The composition boundary forwards/records that one canonical result and never reconstructs affix mechanics or the snapshot from labels, `category` strings, or client constants — so the engine's applied mechanics and the Almanac record cannot diverge. |

---

## 2.1 Acquisition lifecycle (normative)

```
reward generation
      │
      ▼
resolveRewardAffixes(ctx, rng)                    ── RNG consumed here, and only here
      │
      ▼
AffixResolution            (immutable · ordered · exactly 2 slots)
      │
      ▼
preview / hold                                    ── pure read: no RNG, no mutation, no record
      │
      ▼
player TAKE
      │
      ▼
acquireAffixes(resolution, target, idSource, run) ── no RNG
      ├─ apply canonical mechanics                (statBonuses / heal / bank)
      ├─ idSource.next(run, slotPosition) ─► affixEventId   (engine-owned deterministic counter)
      └─ build AffixAcquisition                   (plain engine record — no almanac.dart type)
      │
      ▼
AffixAcquired { acquisition, rewardBaseId }       ── engine / game event
      │
      ▼
composition forwards        (headless AlmanacBridge · client RewardAdapter → AlmanacSession)
      │
      ▼
AlmanacRecorder.recordAffixDiscovered(
    affixId:     acquisition.affixId,
    observation: AffixObservation(acquisition.affixEventId, acquisition.runId, acquisition.runNumber),
    snapshot:    AffixSnapshot(acquisition.affixId, acquisition.stat, acquisition.value, acquisition.category),
    timestamp:   now)
```

Phase contract:

| Phase | What it is | Consumes RNG | Mutates game state | Writes Almanac |
|---|---|---|---|---|
| **RESOLVE** | deterministic slot selection (`resolveRewardAffixes`) | **yes** | no | no |
| **PREVIEW** | pure read of the held `AffixResolution` | no | no | no |
| **ACQUIRE** | mechanical application + engine event identity (`acquireAffixes`) | no | **yes** | no |
| **RECORD** | composition-side Almanac persistence (`recordAffixDiscovered`) | no | no | **yes** |

`affixEventId` is minted only in **ACQUIRE**, only by the engine-owned
`AffixAcquisitionIdSource` (§6.5). No other phase, and no composition-layer type,
ever creates one.

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
| `AlmanacRecorder.recordAffixDiscovered({affixId, observation, snapshot, timestamp})`, `AffixObservation`, `AffixSnapshot`, `AlmanacQueries.getAffixHistory` | `almanac.dart` | recording — used **only by the composition boundary** (headless `AlmanacBridge`, client `RewardAdapter`/`AlmanacSession`). The affix plugin does not import `almanac.dart` and the affix barrel does not re-export it. |
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
| `affix_content.dart` | `const affixContentDefinitions = <Map<String,dynamic>>[ … ]` — the 33 ported entries (§8). |
| `affix_resolver.dart` | `AffixRewardContext`, `AffixResolution`, `AffixResolvedSlot`, `resolveRewardAffixes(...)` (§5). |
| `affix_application.dart` | `applyAffixMechanic(AffixDefinition, AffixApplicationTarget, PluginContext) → ({String stat})` (§6). |
| `affix_acquisition.dart` | `RunRef`, `AffixAcquisitionIdSource` (the one stateful type — instance per run), `AffixAcquisition` (plain engine record), `acquireAffixes(...)` (§6.4–6.5). **No `almanac.dart` import.** |

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
({String stat}) applyAffixMechanic(
  AffixDefinition def, AffixApplicationTarget target, PluginContext context)
```

The returned `stat` is **always a non-null `String`** — the frozen `AffixSnapshot`
schema (`final String stat`, non-nullable) requires one for every recorded affix — and
is **always the mechanic *kind* string**, `'weapon_stat_bonus'` / `'heal'` /
`'bank_progression'`, never a per-target resolved value. It reads correctly in the
Almanac's `category · stat +value` display (`technique_prefix · heal +12`,
`item_prefix · weapon_stat_bonus +3`). For `WeaponStatBonus` the resolved
`WeaponStatTags` tag is still computed locally and bound to `ItemInstance.statBonuses`
via `addItemStatBonuses` — it is just not what the function returns, because
`AffixSnapshot` holds exactly one canonical snapshot per `affixId` and a per-target
`stat` would break cross-run / hydrated recording (D13).

| `def.mechanic` | Action | Returns `stat` |
|---|---|---|
| `WeaponStatBonus(a)` | require `ItemInstanceTarget`; `resolvedStat = WeaponStatTags.matchOrFallback(itemDefinition(t.itemId, context).tags, 'item:${t.itemId}')`; `addItemStatBonuses(t.instance, {resolvedStat: a}, context)` | `'weapon_stat_bonus'` |
| `ImmediateHeal(a)` | require `CharacterTarget`; read `HealthComponent`, write back `current: min(current + a, max)` | `'heal'` |
| `BankProgression(a)` | require `CharacterTarget`; `context.resources.add(t.character, ItemResources.upgradePoints, a)` | `'bank_progression'` |

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

### 6.4 Acquisition — apply, mint identity, hand back a plain record

```dart
class RunRef {
  const RunRef({required this.runId, required this.runNumber});
  final String runId;
  final int runNumber;
}

/// A plain engine-domain result. Carries no `almanac.dart` type; the
/// composition boundary builds `AffixObservation` / `AffixSnapshot` from
/// these fields (§7). One instance per acquired affix.
class AffixAcquisition {
  const AffixAcquisition({
    required this.affixId,
    required this.affixEventId,
    required this.runId,
    required this.runNumber,
    required this.stat,
    required this.value,
    required this.category,
  });
  final String affixId;
  final String affixEventId;   // from AffixAcquisitionIdSource (§6.5) — opaque, never parsed
  final String runId;
  final int runNumber;
  final String stat;           // mechanic kind: 'weapon_stat_bonus' / 'heal' / 'bank_progression' (target-independent; AffixSnapshot.stat is a required non-null String)
  final num value;             // == the affix's AffixMechanic.amount
  final String category;       // the affix definition's category, verbatim
}

List<AffixAcquisition> acquireAffixes({
  required AffixResolution resolution,
  required AffixApplicationTarget target,
  required AffixAcquisitionIdSource idSource,   // engine-owned, one per run (§6.5)
  required RunRef run,
  required PluginContext context,
})
```

For each slot with `affix != null`, in position order:

1. `stat = applyAffixMechanic(slot.affix!, target, context).stat` — mechanics land now
   (this is the **ACQUIRE** phase's game-state mutation).
2. `affixEventId = idSource.next(run: run, slotPosition: slot.position)` — the **sole**
   mint point for an `affixEventId` anywhere in the system.
3. append `AffixAcquisition(affixId: slot.affix!.id, affixEventId: affixEventId,
   runId: run.runId, runNumber: run.runNumber, stat: stat,
   value: slot.affix!.mechanic.amount, category: slot.affix!.category)`.

A `null` slot yields nothing. `acquireAffixes` **does not touch the Almanac** and
**consumes no RNG**. It returns the list; the composition boundary takes each
`AffixAcquisition` and calls `recordAffixDiscovered` (§7). This is the requirements §10
producer contract: the engine produces the canonical taken-reward result carrying
`(affixId, affixEventId)` and the canonical mechanical fields; composition only forwards.

If a future mechanic needs randomness, `acquireAffixes` gains its own `RngService`
parameter then — never a second, hidden randomness source.

### 6.5 `AffixAcquisitionIdSource` — the single owner of acquisition identity

```dart
/// Engine type, in `affix_acquisition.dart`. The ONLY type that constructs an
/// `affixEventId`. Deterministic monotonic counter — no RNG. One instance per
/// logical run; the sequence makes acquisition ids distinct *within* that run.
class AffixAcquisitionIdSource {
  int _seq = 0;
  String next({required RunRef run, required int slotPosition}) =>
      '${run.runId}:affix:$slotPosition:${_seq++}';
}
```

- **Defined and advanced only inside `build_engine`.** The `_seq++` lives here and
  nowhere else.
- **One instance per logical run, created by the engine reward/run layer:**
  - headless harness — `game_run.dart` builds it next to `RngService(seed)` and passes
    it into `RewardStage`, which forwards it to every `acquireAffixes` call in that run.
  - client — the `lib/core/engine/` integration boundary owns it as per-run engine
    state (alongside `EngineSession`) and injects it into `RewardAdapter` the same way
    every other engine adapter is injected. `RewardAdapter` **never calls `.next()`** —
    only `acquireAffixes` does. `RewardAdapter` has no counter, no allocator, and no
    code path that constructs an `affixEventId`.
- **Deterministic** — a plain integer counter, no RNG (keeps "exactly one RNG").
- **Uniqueness contract (precise):**
  - `runId` is the authoritative *logical-run* identity — opaque, caller-supplied.
  - the acquisition sequence guarantees **distinct `affixEventId`s within one logical
    run**: for a fixed `runId`, each `next(...)` call yields a fresh `slotPosition:_seq`
    tail.
  - **distinct logical runs must supply distinct `runId`s.** If a caller deliberately
    reuses a `runId` across two separate `AffixAcquisitionIdSource` instances, the
    engine does **not** guarantee the resulting ids differ — that is a caller contract,
    not this type's responsibility. No UUID, timestamp, second RNG, or global allocator
    is introduced to paper over a reused `runId`.
  - the string is **opaque downstream**: the `AffixAcquisition` carries `runId` /
    `runNumber` as explicit fields and *those*, never the id, are how run identity is
    read (matches the Almanac module's "no key is ever parsed" discipline).
- **Genuine repeat vs replay:**
  - two real acquisitions of `af_keen` in one run → two `.next()` calls → two distinct
    `affixEventId`s → one `AlmanacAffixRecord`, two discovery observations (client "Test A").
  - replaying one acquisition = re-sending an existing `AffixAcquisition` to
    `recordAffixDiscovered`; `AffixAcquisitionIdSource` is not consulted, the id is
    unchanged, and the Almanac's `(affixId, affixEventId)` de-dupe makes it a no-op
    (client "Test B").

> **Why an engine counter and not a UUID or a client-side allocator.** Requirements
> §9.1 forbid a *composition-minted* substitute (client UUID / timestamp /
> random-at-TAKE) — those break replay idempotency and move canonical identity out of
> the engine. An engine-owned monotonic per-run counter is authoritative, stable for a
> given acquisition, distinguishes genuine repeats from replays, and adds no second
> randomness source. The client holds at most a *reference* to the engine-provided
> source object; it never defines or advances the sequence and never mints an id.

---

## 7. Headless harness wiring (end-to-end)

| File | Change |
|---|---|
| `lib/src/plugins/game/game_run.dart` | `AffixPlugin().initialize(context)` after `ConsumablePlugin` (line ~191) — it reads `item`/`technique` content domains, so it initializes after both. Separately, build one `AffixAcquisitionIdSource()` next to `RngService(seed)` (line ~163) and pass it into `RewardStage` alongside `runId` / `runNumber`. |
| `lib/src/plugins/game/run_content.dart` | no new roster constant needed — pools come from `affixContentDefinitions` via `withTag`. Add a doc line pointing at `AffixPlugin` as the affix source. |
| `lib/src/plugins/game/reward_stage.dart` | `RewardStage` gains `physiqueTradition`, `runId`, `runNumber`, and `idSource` fields, all set at construction. In `resolveReward`, `RewardKind.itemOrTechnique` branch: after `ownItem(...)` / `discoverTechnique(...)`, build `AffixRewardContext` (domain from `entry.referenceType`, `physiqueTradition` from the field), call `resolveRewardAffixes(ctx, context.rng)` — **the resolver draw comes right after `rewardIndex++`, i.e. after the pool pick, per §5.3** — then `acquireAffixes(resolution: …, target: …, idSource: idSource, run: RunRef(runId: runId, runNumber: runNumber), context: context)`. For each returned `AffixAcquisition a`, `events.publish(AffixAcquired(acquisition: a, rewardBaseId: '<base id>'))`. Return string becomes `item:iron_sword+af_keen+af_of_the_ember` (base id, then each acquired affix id in position order; unchanged when no affix rolls). `RewardStage` never calls `idSource.next(...)` itself. |
| `lib/src/plugins/game/run_events.dart` | new telemetry type `class AffixAcquired { const AffixAcquired({required this.acquisition, required this.rewardBaseId}); final AffixAcquisition acquisition; final String rewardBaseId; }` — it carries the whole canonical engine result, no primitive-field variant. Added to the events table doc. Not a domain fact — a run telemetry point, same tier as `RewardSelected`. |
| `lib/src/plugins/game/almanac_bridge.dart` | subscribe `AffixAcquired` in `attach`. The handler builds the Almanac value objects **from `e.acquisition`** — `AffixObservation(affixEventId: e.acquisition.affixEventId, runId: e.acquisition.runId, runNumber: e.acquisition.runNumber)` and `AffixSnapshot(affixId: e.acquisition.affixId, stat: e.acquisition.stat, value: e.acquisition.value, category: e.acquisition.category)` — never from labels, `category` guesses, or client constants — then `_recorder.recordAffixDiscovered(affixId: e.acquisition.affixId, observation:, snapshot:, timestamp: DateTime.now())`. `_buildSnapshot` stops hard-coding `affixes: const <AffixSnapshot>[]` / `affixCategories: const <String>[]` — it accumulates the run's `AffixSnapshot`s from the same event stream and passes them to `AlmanacBuildRecord.affixes` and `buildDna(affixCategories: …)`. |

**Composition boundary note.** `almanac_bridge.dart` stays "the only in-repo file that
imports both a gameplay plugin and the Almanac — by design". The affix *plugin* imports
neither the bridge nor `almanac.dart`: it hands back a plain `AffixAcquisition`, the
game event carries that record whole, and the bridge is the one place the
`almanac.dart` value objects are constructed. Because both the applied mechanic (§6.2)
and the recorded `AffixSnapshot` derive from the *same* `AffixAcquisition`, engine
application and Almanac history cannot drift apart.

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
export 'src/plugins/affix/affix_acquisition.dart'; // RunRef, AffixAcquisitionIdSource, AffixAcquisition, acquireAffixes
```

`AffixSnapshot` / `AffixObservation` / `recordAffixDiscovered` are **not** re-exported
and **not imported** by the affix plugin. `acquireAffixes` returns the plain
`AffixAcquisition` record (§6.4); the composition boundary — `HeadlessGameAlmanacBridge`
and the client's `RewardAdapter` / `AlmanacSession` — is the only place the `almanac.dart`
value objects are built, from that record's fields. The affix plugin's engine
dependencies are Core plus `item_plugin.dart` (`addItemStatBonuses`,
`WeaponStatTags`, `itemDefinition`); physique vocabulary enters only as the
caller-supplied `physiqueTradition` string, so not even a direct import. **Zero Almanac
coupling** — an affix `dart analyze` / import graph shows no path to
`src/plugins/almanac/`.

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
      duplicate list, and the client keeps no affix roster of its own.

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
      (`value == mechanic.amount`, `category` verbatim, `stat` = the mechanic-kind
      string `'weapon_stat_bonus'` / `'heal'` / `'bank_progression'`, target-independent)
      — never a client constant, and never a per-target resolved weapon stat (which the
      one-canonical-snapshot-per-`affixId` rule cannot represent).

**Acquisition identity** (single owner, per-run uniqueness)
- [ ] `AffixAcquisitionIdSource` is the **only** type in the codebase that constructs an
      `affixEventId`, and it lives in `build_engine`.
- [ ] `acquireAffixes` mints one `affixEventId` per filled slot via `idSource.next(...)`;
      a two-slot reward → two `AffixAcquisition`s, a no-affix reward → none.
- [ ] no client-side type — `RewardAdapter` included — contains an acquisition-id
      allocator, counter, or `affixEventId` constructor; a grep for a client-side
      `affixEventId` assignment finds nothing.
- [ ] replaying an `AffixAcquisition` does **not** call `idSource.next(...)` and does
      not change its `affixEventId`.
- [ ] one fresh `AffixAcquisitionIdSource` is used per **logical run**; a logical run is
      identified by its `runId`.
- [ ] two genuine acquisitions within the same logical run get **distinct**
      `affixEventId`s → one `AlmanacAffixRecord`, two discovery observations.
- [ ] `affixEventId` is **not** required to be globally unique when a caller
      deliberately reuses the same `runId`; distinct logical runs supplying distinct
      `runId`s is a caller contract, not `AffixAcquisitionIdSource`'s responsibility.
- [ ] acquisition identity stays engine-owned even when the **client** is the caller of
      `acquireAffixes` (the client only supplies the engine-provided `idSource` and
      forwards the result).
- [ ] no UUID, timestamp, second RNG, or global allocator is introduced;
      `acquireAffixes` and `AffixAcquisitionIdSource` consume no RNG.
- [ ] `affixEventId` stays opaque downstream — nothing parses it for run identity; run
      identity is read from `runId` / `runNumber`.

**Event & recording boundary**
- [ ] `AffixAcquired` carries the whole `AffixAcquisition`; the bridge builds
      `AffixObservation` / `AffixSnapshot` from it, never from labels, `category`
      strings, or client constants.
- [ ] `affix_acquisition.dart` (and every other affix-plugin file) does not import
      `almanac.dart`; the affix plugin's import graph has no path to
      `src/plugins/almanac/`.
- [ ] the applied mechanic (§6.2) and the recorded `AffixSnapshot` are both derived from
      the same `AffixAcquisition` — engine application and Almanac record cannot diverge.

**Wiring & exports**
- [ ] `lib/affix_plugin.dart` exports the §10 surface; `dart analyze` clean.
- [ ] a full `runGame` seed exercises RESOLVE → ACQUIRE → RECORD, and the
      resulting `AlmanacState.affixes` / `AlmanacBuildRecord.affixes` /
      `buildDna(affixCategories:)` carry real values (no stub `const []`).
- [ ] headless unit tests cover definition load, id opacity, resolver determinism +
      weighting + four states, offer stability, all three mechanics, single-owner event
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
| taken-reward result carrying `affixId` + `affixEventId` | `AffixAcquisition` — plain engine record (§6.4, D13) |
| slot container shape (`prefix?`/`suffix?` vs list vs handles) | ordered `List<AffixResolvedSlot>` length 2, `slotKind` hint (§5.2) |
| one event vs one-per-affix | one `affixEventId` per acquired affix (D6) |
| who mints `affixEventId` | engine `AffixAcquisitionIdSource`, one instance per logical run; the client only supplies it to `acquireAffixes` and forwards the result. Ids are unique *within* a logical run; the client must give each logical run a distinct `runId` (D7, §6.5) |
| `AlmanacRecorder.recordAffixDiscovered`, `AlmanacRepository`, `AlmanacSerialization` | unchanged `almanac.dart` — client builds `AffixObservation` / `AffixSnapshot` from `AffixAcquisition` and calls the recorder |

The client's `RewardAdapter` calls `resolveRewardAffixes` in `offerLoot()` (storing the
`AffixResolution`), reads it during preview, and in `applyLoot` calls `acquireAffixes` —
passing the per-run `AffixAcquisitionIdSource` it was injected with from the
`lib/core/engine/` boundary — then hands each returned `AffixAcquisition` to its
`AlmanacSession`, which builds the `AffixObservation` / `AffixSnapshot` and calls
`recordAffixDiscovered`. `RewardAdapter` mints nothing, holds no counter, and never
constructs an `affixEventId`. The one obligation on the client is to pass a `runId` that
is distinct per logical run (it already tracks run id/number for `AffixObservation`); the
engine handles within-run acquisition uniqueness. `_applyTechniqueAffix`, the `Affix` /
`AffixEffect` / `AffixLean` client types, and `reward_affix.dart` are deleted.
