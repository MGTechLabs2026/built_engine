# SP4a — Client engine bump + consumable Almanac debt — brainstorm notes

**Date:** 2026-09-08
**Status:** brainstorm notes — decomposition agreed, design sketched, **not yet validated**. Open questions in §6 block promotion to a `-design.md` spec.
**Repo:** `build_engine` (`Tome:RougelikeGame`) + `Tome_client` (`/Users/m4maxpro/Projects/Tome_client`, Flutter)
**Parent:** `2026-09-02-tiered-component-effects-design.md` §1.2 (the SP0–SP4 decomposition)

---

## 1. Where this sits

The parent decomposition's **SP4** is "`Tome_client` surfacing — reward affixes
roll a tier, detail sheet shows effects by tier, Tome feeds the owned set.
Closes the original technique-affix bug."

Exploration on 2026-09-08 found SP4-as-scoped is not directly buildable:

- **`Tome_client`'s `build_engine` dependency is pinned at `314f75a`** (2026-09-01,
  `pubspec.yaml` / `pubspec.lock`), **139 commits behind engine HEAD `1dc7e5d`**,
  predating **SP0a / SP1 / SP2 / SP3** entirely.
- The client still binds item affixes to `ItemInstance.statBonuses`
  (`reward_adapter.dart:249`, `item_adapter.dart`) — SP1 §9 migrated that path —
  and treats technique affixes as one-shot `healNow` / `bankPoint` boons
  (`reward_adapter.dart._applyTechniqueAffix`) — this *is* the original bug SP4
  is meant to close.
- `combat_adapter.dart:79` calls `_ctx.tome.resolve(_me)` — SP1 made
  `TomeService.resolve` require `ownedRefs:` → hard compile break on bump.
- The engine's `AlmanacRecorder` / a `TomeClientAlmanacAdapter` is **not wired in
  the client** at `314f75a` (the client's "Almanac" is a codex UI screen only).
- Engine-repo debt tagged "SP4" exists and is real but small: the in-engine
  `HeadlessGameAlmanacBridge` + `BuildDna` + `almanac_run_history_test.dart`
  replay-equivalence projection have no consumable-placement visibility (comment
  block added in `b0ee428`).

## 2. Decisions taken (2026-09-08, via clarifying questions)

| # | Question | Answer |
|---|----------|--------|
| D1 | SP4 spans engine repo (loaded) + `Tome_client` (not loaded). How to proceed? | **Full SP4: spec here, then both.** |
| D2 | Client is 139 commits / 4 sub-projects behind. Handle the bump vs. the surfacing? | **Split: SP4a = engine bump + engine-repo debt; SP4b = surfacing.** Each gets its own spec → plan → impl. |
| D3 | Bump strategy across SP0a / SP1 / SP2 / SP3? | **Staged, one sub-project per step**, re-greening the client gate at each stop. |
| D4 | Client fixture drift when the bump shifts a seed's combat outcome / the visual golden? | **Update fixtures to observed values**, provided determinism *properties* (same seed + same decisions → identical result) still hold. A property failure is a real bug — stop. |

**SP4b (deferred, not this doc):** tiered reward affixes via `EffectContributor`,
`component_detail_sheet` grouping effects by tier, client composition root
adopting `AuraBinder` + `ConsumableBinder` (honouring Combat-first init order),
a `TomeClientAlmanacAdapter` with a `consumable` occupant kind.

## 3. SP4a scope

The client runs on `build_engine` HEAD with a green test gate and no behavioural
regression beyond deliberate seed-outcome drift; and `build_engine`'s own Almanac
replay-equivalence coverage stops filtering consumable placements out.

**No new client UX. No reward-model change. No binder adoption.** If a bump stage
cannot re-green without one of those, that is the signal the SP4a/SP4b boundary
needs revisiting — stop and surface it.

Lands in two parts, **Part A first** (self-contained, no dependency on Part B, so
the engine surface Part B bumps *to* is already final):

## 4. Part A — consumable occupant kind in the Almanac (`build_engine`, this repo)

Three deterministic, RNG-free, no-new-gameplay changes:

### 4.1 `buildDna()` gains a consumable channel
`lib/src/plugins/almanac/almanac_build_dna.dart`

- New `required Iterable<String> consumableIds` parameter, tokenised through
  `_sortedUniqueUpper` at a **fixed, documented position — after `itemIds`,
  before `affixCategories`**.
- Zero-consumable builds emit no token → every existing build's `signature` is
  unchanged (backward compatible).
- Core public-surface change → `CHANGELOG.md`.

### 4.2 `HeadlessGameAlmanacBridge._buildSnapshot`
`lib/src/plugins/game/almanac_bridge.dart`

- `occupantKind` ternary gains a `consumableReferenceType → 'consumable'` arm
  (add `consumable_plugin.dart` import, sibling style).
- Build a `consumables` list from the placements loop — **minimal: `slotId` +
  `occupantRefId` (content id) only**. A consumable has no per-copy instanced
  entity (charges are a per-fight `ResourcePool` resource, not stored state).
- `buildDna(... consumableIds: [for (p in placements) if consumable → p.contentId])`.

### 4.3 `almanac_run_history_test.dart`
- `_occupants(b)` stops excluding `occupantKind == 'consumable'` (currently
  swept up by the `!= 'empty'` filter the `b0ee428` note flags).
- `_ForceItemReward` helper / projection assertions extended so a run that
  places a consumable is covered by the replay-equivalence check, not only by
  `consumable_combat_stage_test.dart`'s full-`RunResult` equality.
- Delete the "SP4 debt" comment block from `b0ee428`.

## 5. Part B — client staged engine bump (`Tome_client`)

Branch `sp4a-engine-bump` in `Tome_client` (add that repo as a working dir when
Part B starts). Four stages. **Each stage:** bump `pubspec.yaml` git `ref` to
that sub-project's merge commit → `flutter pub get` → `dart analyze` →
`flutter test` → fix breakage using that sub-project's `CHANGELOG.md` /
migration section as the guide → re-green → commit.

| Stage | Bump to | Expected breakage (from exploration) |
|-------|---------|-------------------------------------|
| 1 · SP0a | technique-instancing merge | `technique_adapter.dart`, `tome_adapter.dart` place/discover paths — techniques are now instanced (`TechniqueVariant`, `instanceEntityId`); likely must mint a variant on discover/place. |
| 2 · SP1 | tiered-effects merge | **Compile break:** `combat_adapter.dart:79` `_ctx.tome.resolve(_me)` needs `ownedRefs:`. `item_adapter.dart` / `reward_adapter.dart` `statBonuses` / `addItemStatBonuses` — migrated to the `supporting`-tier input path; reconcile read + write sites. |
| 3 · SP2 | per-active-auras merge | Additive / opt-in. Near-clean expected; risk is Combat-first init order in the client's `EngineSession` composition (SP2 CHANGELOG note). No aura content hung (SP4b) → behaviourally inert. |
| 4 · SP3 | per-fight-consumables merge | Additive. `ConsumablePlugin` not registered by the client → inert. Verify `EngineSession` plugin list still resolves; no consumables in the client reward pool yet. |

**Fixture policy (D4):** where a stage shifts a seed-stable combat outcome or the
`tome_visual_capture` golden *because the engine calculation changed*, update the
client fixture to the observed new value. A determinism-*property* failure is a
real bug — stop, do not paper over it.

**Out of scope for Part B:** `AuraBinder` / `ConsumableBinder` adoption, tiered
affix rolling, `component_detail_sheet` changes, any `TomeClientAlmanacAdapter`.

## 6. Open questions (block promotion to `-design.md`)

1. **`AlmanacBuildRecord` shape (§4.2):** slots-only (`occupantKind: 'consumable'`
   in `tome.slots` + the DNA channel) — recommended — **vs.** a typed
   `List<ConsumablePlacementSnapshot> consumables` field on the record. The typed
   field is dead weight until SP4b / a real client adapter needs it.
2. **One spec vs. two:** a single `2026-09-08-sp4a-engine-bump-design.md` covering
   Part A + Part B, **vs.** separate specs given they land in different repos with
   different test gates and review cycles.

## 7. Next step

Resolve §6 → write `docs/superpowers/specs/2026-09-08-sp4a-engine-bump-design.md`
(spec self-review, user review gate) → `superpowers:writing-plans` for the
implementation plan (Part A tasks in this repo; Part B tasks staged in the
client repo).
