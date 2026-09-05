# Changelog

`build_engine` is consumed as a pinned git dependency, so this file
tracks **public-surface changes** a consumer must know about when
bumping the pin. Newest first.

## Unreleased

### Added — Tiered Component Effects (SP1)

- **`package:build_engine/build_engine.dart`** exports five new Core
  types from `src/effect_profile/`:
  - **`EffectTier`** — a fixed, Core-owned enum (`permanent` /
    `active` / `supporting`). A plugin cannot add tiers: each tier's
    inclusion rule is calculation logic, not content.
  - **`EffectProfile`** — a component's numeric contributions grouped
    by tier, `{EffectTier → {stat → num}}`. Recursively immutable —
    build one from computed maps with `EffectProfile.of(...)`; the
    bare `const` constructor is for const literals only
    (`EffectProfile.empty`). `tier(t)`, `amount(t, stat)`, and
    `merge(other)` (additive union) are the read/compose surface.
  - **`EffectContributor`** — an abstract interface a plugin's own
    definition/instance type implements to declare its tiered effects.
    "Implement the interface, no registry" — the same pattern
    `Condition` / `Effect` / `CombatAction` / `TrainingExercise` use.
  - **`EffectProfileResolver`** — pure, storage-free (mirrors
    `ModifierResolver` / `BuildResolver`). `resolve({owned, hung,
    usedThisCalculation, stat})` sums `permanent` over `owned` +
    `supporting` over `hung` + the `active` amount of the used
    component.
  - **`ResolvedBuild`** (from `src/tome/build_resolver.dart`) —
    `{owner, active, owned}`. `active` is the hung set (what
    `ActiveBuild` alone used to mean); `owned` is every owned
    component instance, hung or loose. `active ⊆ owned` holds by
    construction — `owned` is the union of the caller's `ownedRefs`
    and every hung ref, not an assert. `asActiveBuild` projects back
    to the old `ActiveBuild` shape.
- **`BuildComponentRef` gained value equality** — `operator==` /
  `hashCode` over `referenceType` / `contentId` / `instanceEntityId`
  (previously identity-only). Needed so `ResolvedBuild`'s owned-set
  union deduplicates a hung-and-owned ref correctly.

### Changed — Tiered Component Effects (SP1)

- **`ItemInstance.statBonuses` and `TechniqueVariant.axisProfile['power']`
  now flow through `EffectProfile`** instead of being turned into
  `Modifier`s / read as direct arithmetic. `ItemEffectContributor`
  (new, `package:build_engine/item_plugin.dart`) composes an item's
  scaled `attack` + per-copy `statBonuses` into the `supporting` tier;
  `TechniqueVariant` implements `EffectContributor`, reporting
  `axisProfile['power']` under the generic `'power'` key in the
  `active` tier. There is now a single numeric-effect path — the
  `affix:*` `Modifier` source and the direct `axisProfile['power']`
  arithmetic in the interpreters are both gone.
- **`WeaponStatTags` relocated** from `src/plugins/build_interpretation/`
  to `src/plugins/item/`, now exported by
  `package:build_engine/item_plugin.dart`.
  `package:build_engine/build_interpretation.dart` keeps a compat
  re-export, so existing imports are unaffected.
- **`TomeService.resolve` now requires `ownedRefs`** (a
  `List<BuildComponentRef>` the caller derives from each owned
  instance entity's `owner` field) and **returns `ResolvedBuild`**,
  not `ActiveBuild`. Call `.asActiveBuild` for the previous shape.
- **`BuildActionInterpreter.interpret` takes a `ResolvedBuild`**
  (was `ActiveBuild`) — it reads `.active` for hung components and the
  owned/used tiers via each contributor's `EffectProfile`.
- **`TomeManager.placeItem` now carries `instanceEntityId`** into the
  Tome placement (`addItemToTome`), so a placed item's per-copy
  `ItemInstance` state is reachable from the resolved build. Legacy
  placements with a null `instanceEntityId` still resolve — scaling
  falls back to item class 1 and contributes no `statBonuses`.

### Added — Almanac (persistent player history)

- **`package:build_engine/almanac.dart`** — new platform-neutral public
  barrel for the Almanac (persistent cross-run player history): the domain
  model value objects + JSON, `AlmanacSerialization` (schema v1), the
  `AlmanacRepository` interface + `InMemoryAlmanacRepository`,
  `AlmanacRecorder` (identity-keyed, monotonic, hydrating), `AlmanacQueries`
  (pure read view), and `buildDna(...)` / `BuildDna`. Safe to import from
  web targets — no `dart:io`.
- **`package:build_engine/almanac_file.dart`** — new `dart:io` barrel
  exporting `JsonFileAlmanacRepository` (atomic temp-file + rename
  whole-state persistence). Kept separate so the neutral barrel stays
  web-safe.
- **`runGame(almanac:, runId:, runNumber:)`** — new optional, default-off
  parameters on `runGame`. With `almanac == null` (the default) behaviour
  is byte-identical: no history recording, no repository IO. When supplied,
  a `HeadlessGameAlmanacBridge` observes the run and feeds the recorder;
  the caller owns persistence. `runId` / `runNumber` are caller-supplied
  opaque values, validated with `ArgumentError`.

### Added — public API (audit A1/A2/A4 refactor)

- **`resolveTechniqueEvolutionAfterTraining(owner, technique, profile, context)`**
  on `package:build_engine/technique_plugin.dart` — the one authoritative
  post-training evolution step. It no-ops unless the technique is learned
  and has candidates, runs the pure `evolveTechnique` resolver (one
  `context.rng` draw when eligible), and **publishes `TechniqueEvolved`
  exactly once** on success. It is now the *sole* publisher of that
  event: `TrainingStage` and any embedding client must call this instead
  of open-coding the resolver + publish. `evolveTechnique` stays public
  for callers wanting the raw draw without the gate or the event.
- **`StyleCombatRules(fighterTags)` + `BurstChainState`** on
  `package:build_engine/martial_arts_plugin.dart` — the engine-owned
  style-scoped combat rules (off-specialty damage penalty, Shaolin
  Conditioning, Kunlun Burst Chain), previously implemented only in the
  client. Pure, deterministic, no RNG/PluginContext/Flutter. Keys off
  `spec:*` tags + `styleAlignedFamilies`, never a style-id switch.
- **`package:build_engine/game.dart` is documented as a headless
  reference / balance-simulation harness**, not the authoritative run.
  No API change — the docstrings now state that a consuming client owns
  run composition/sequencing/presentation and the engine owns the domain
  rules both consume.

### Added — Technique instancing (SP0a)

- `TechniqueDescriptor` content type (`type: 'technique_descriptor'`) with a
  multi-axis `axes: {axisKey → magnitude}` map; launch descriptor set;
  `TechniqueAxes` (`power`/`speed`/`endurance`/`precision`).
- `TechniqueVariant` component: `owner`, `baseFamilyId`, `descriptorIds`,
  composed `axisProfile`, `styleId`.
- `TechniqueVariantResolver.resolve(descriptors)` — pure, descriptors only;
  `composeAxisProfile(base, contribution)` — pure additive merge (style-centre
  composition, kept out of the resolver).
- `mintTechniqueVariant(owner, baseFamilyId, descriptorIds, context,
  {styleId, styleCentre})`; `hangTechniqueVariant(slot, instanceId, context)`;
  `removeTechniqueVariant(instanceId, context)`; `ownedTechniqueVariants(owner,
  context)`; `trainTechniqueVariantMastery(instanceId, amount, context)` /
  `techniqueVariantMasteryLevel(instanceId, context)`;
  `mintVariantForLegacyEvolvedId`.
- `mintVariantForLegacyEvolvedId` rejects an **unmapped evolved** technique
  id with the new `LegacyTechniqueMigrationException` rather than silently
  minting a descriptor-less, basic-like variant. A base technique id still
  mints a plain variant; a completely unknown id still fails with
  `ContentNotFoundException`.
- `techniqueInstanceSubject(EntityId)` — per-instance Mastery subject.
- Events: `TechniqueVariantMinted`, `TechniqueVariantRemoved`; optional
  `instanceId` on `TechniqueAddedToTome`.

#### Notes

- Ownership is authoritative on `TechniqueVariant.owner` (like
  `ItemInstance.owner`); "hung" is derived from Tome placements. Lifecycle
  functions other than `mint` read the owner off the component.
- Every `BuildComponentRef` written by **`hangTechniqueVariant`** carries a
  non-null `instanceEntityId`; `addTechniqueToTome` remains the legacy path and
  writes null, as do pre-SP0a saves — readers tolerate null as the bare base.
- `addTechniqueToTome` is now the documented **legacy** Tome path — new code
  hangs a variant instance via `hangTechniqueVariant`.
- Additive: `EvolutionResolver` and the hand-authored evolved ids are
  unchanged; per-instance `MasteryDefinition`s are not unregistered on removal
  (no `MasteryTracker.undefine`) — a run's fresh `PluginContext` resets them.
- Spec open-question #6 (per-instance `MasteryDefinition` accumulation) is
  closed: `MasteryTracker` has no `undefine`, so per-instance definitions are
  never removed; the reference harness (`runGame`) builds a fresh
  `PluginContext`/`MasteryTracker` per run, so accumulation is strictly
  per-run and bounded by the variants minted that run. A client holding one
  long-lived `PluginContext` across runs accumulates one small definition per
  variant — correctness is unaffected, since entity ids are never recycled.

### Added — Technique inspiration / discovery (SP0b)

- `CombatAction.sourceRef: BuildComponentRef?` — optional, default `null`,
  behaviour-neutral. Set by `TechniqueActionInterpreter` on every action
  it builds so a performed action can be attributed to a technique-variant
  instance. `AttackAction` / `SelfEffectAction` gain the matching
  constructor parameter. Also the SP1 active-tier seam.
- `TechniqueUsageComponent` + `recordTechniqueVariantUsage` /
  `techniqueVariantUsage` on
  `package:build_engine/technique_plugin.dart` — per-run, per-variant
  count of performed combat actions. Fed by the composition layer's
  `ActionCompleted` subscription (the Technique plugin itself stays
  Combat-free). Dropped by `removeTechniqueVariant`.
- `TechniqueInspirationResolver.resolve({trainedFamilyId, inspirers,
  descriptorPool, rng, exclude})` — pure: eligibility filter
  (`masteryLevel >= 1 && usage >= 3`), damped weights
  (`mastery * sqrt(usage)`), positive-axis emphasis, usage concentration
  → discovery probability, family-compatibility filter, behaviour-driven
  descriptor count (1–3), weighted draw without replacement, bounded
  exact-duplicate exclusion retry. `Inspirer` / `InspirationResult`
  (`InspirationResult.none`) value types.
- `resolveTechniqueInspirationAfterTraining(owner, trainedTechnique,
  styleCentre, context, {styleId})` — the one authoritative post-training
  discovery step, parallel to `resolveTechniqueEvolutionAfterTraining`.
  One roll → at most one minted (owned, loose) variant on the **trained**
  family (cross-pollination preserved) → publishes `TechniqueVariantInspired`
  exactly once. Inspirers are never mutated.
- `TechniqueVariantInspired {owner, instanceId, familyId, descriptorIds,
  inspirerInstanceIds}` event.
- Tuning constants in `technique_vocabulary.dart` (`kInspirationBaseChance`
  … `kInspirationStrongWeightBar`) + `techniqueFamilyTagPrefix`.
- `styleCentre(styleId, familyId)` on
  `package:build_engine/martial_arts_plugin.dart` — per-style, per-base-family
  axis nudge for a minted variant.
- SP0a's `_familyOf` / `_requireVariant` promoted to public
  `techniqueFamilyOf` / `requireTechniqueVariant` (visibility only).
- The post-training hook is **wired but inert in the headless `game_run`
  harness**: that harness still uses the legacy learn/evolve path and mints
  no `TechniqueVariant`s, so `resolveTechniqueInspirationAfterTraining`
  always returns `InspirationResult.none` without drawing from
  `context.rng` — existing `game_run` seed/golden/replay expectations are
  unchanged. A future pass that migrates the harness to mint variants will
  make the hook live and require regenerating those expectations.
- A successful discovery also publishes `TechniqueVariantMinted` (from
  `mintTechniqueVariant`, SP0a) in addition to `TechniqueVariantInspired`
  — a consumer counting mints will now see inspired variants.

### Changed — public barrels

- **`TechniqueEvolved` moved to the Technique plugin.** It was defined in
  the internal `src/plugins/game/run_events.dart` and reachable only via
  an `implementation_imports` path or the `dart:io`-tainted `game.dart`.
  It now lives in `src/plugins/technique/technique_events.dart` and is
  exported by `package:build_engine/technique_plugin.dart`. Same class,
  same `fromId` / `toId`. **Migration:** import it from
  `technique_plugin.dart`.
- **`ConsoleDecisionPolicy` removed from `package:build_engine/game.dart`.**
  It is the only `dart:io` import in `lib/`, so `game.dart` is now
  web-safe. **Migration:** stdio entrypoints import
  `package:build_engine/console_policy.dart`.

### Changed — behaviour-neutral

- Every technique — base **and** evolved — now gets a MASTERY rank axis
  at `TechniquePlugin.initialize` (previously only the three base forms).
  The LEARNING axis stays base-only. Thresholds are unchanged and now
  named in `technique_vocabulary.dart` (`techniqueMasteryThresholds`,
  `techniqueLearningThresholds`) as the single source of truth.
