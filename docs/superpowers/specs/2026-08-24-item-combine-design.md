# Item Combine — Design Spec

**Date:** 2026-08-24
**Origin:** User request — "combine item rule": 2 or more items sharing the
same content id and the same `class` can be combined into a single
upgraded survivor, either advancing in `class` (numeric tier within the
same item id) or advancing in `grade` (becoming a qualitatively different,
better item id), at a cost of a new `upgrade_points` resource.
**Goal:** A reusable, data-driven Combine mechanic — Core provides a
generic N-inputs-into-1, odds-driven resolver; the Item plugin wires it to
`ItemInstance`/`ItemDefinition`; the existing `EvolutionDefinition`/
`EvolutionResolver` machinery is reused (not duplicated) for grade
branching, so any future plugin (Magic, Cultivation, ...) can adopt the
same mechanic for its own content without Core ever learning what a
"knife" is.

## Non-goals

- No design for *how* players earn `upgrade_points` — this spec only
  registers the resource and spends it. Sourcing (rewards/progression) is
  a separate future concern.
- No spatial/adjacency requirement — combining only requires common
  ownership, not placement proximity in the Tome/backpack grid.
- No change to Martial Arts or Elemental items/plugins. `ItemInstance`'s
  new `class` field and `BuildComponentRef`'s new `instanceEntityId`
  field are additive and unused by those plugins.
- No automatic stat rebalancing of existing item content beyond the new
  `classScalingPercent`/`maxClass`/`gradeEvolutionCandidates` fields items must
  now declare to participate in Combine at all. Items that don't declare
  them simply can't be combined (see Content authoring contract).

## Design

### 1. Core: `lib/src/combine/`

New module, mirroring `lib/src/evolution/`'s "pure resolver, no stored
state" shape.

**`combine_odds.dart`** — pure function computing the fail/normal/rare
split for one attempt:

```dart
class CombineOdds {
  const CombineOdds({required this.failPercent, required this.normalPercent, required this.rarePercent});
  final num failPercent;
  final num normalPercent;
  final num rarePercent;

  static CombineOdds forAttempt({required int tier, required int inputCount}) {
    // Baseline at inputCount == 2 (always sums to 100 by construction):
    final baseFail = (10 + (tier - 1) * 10).clamp(0, 60);
    final baseRare = (15 - (tier - 1) * 2).clamp(5, 100);
    final baseNormal = 100 - baseFail - baseRare;

    // Each input beyond 2 nominally shifts 6 points off fail, split 4
    // to normal / 2 to rare. Once fail would drop below its floor (5),
    // the shortfall is pulled back out of the normal/rare gains
    // proportionally (2:1) instead of just clamping fail alone -- this
    // is what keeps fail+normal+rare == 100 exactly at every input
    // count, instead of overshooting past 100 once fail bottoms out.
    final extra = (inputCount - 2).clamp(0, 1 << 30);
    final nominalFail = baseFail - extra * 6;
    final fail = nominalFail.clamp(5, 100);
    final deficit = fail - nominalFail; // 0 until the floor is hit
    final nominalNormal = baseNormal + extra * 4;
    final nominalRare = baseRare + extra * 2;
    final rare = nominalRare - (deficit / 3).round();
    final normal = 100 - fail - rare; // absorbs any rounding remainder

    return CombineOdds(failPercent: fail, normalPercent: normal, rarePercent: rare);
  }
}
```

Reference values this must reproduce (all sum to exactly 100):
tier 1/2 inputs → fail 10, normal 75, rare 15;
tier 1/4 inputs → fail 5, normal 78, rare 17 (deficit 7 pulled 2:1 out of the nominal 83/19);
tier 3/2 inputs → fail 30, normal 55, rare 15;
tier 6/2 inputs → fail 60, normal 35, rare 5 (corrected — `rare = max(15-(6-1)*2, 5) = 5`, not 15).

**`combine_outcome.dart`** — `enum CombineOutcome { fail, classUpgrade, gradeUpgrade }`

**`combine_input.dart`**:

```dart
class CombineInput {
  const CombineInput({required this.matchKey, required this.tier});
  final String matchKey;   // e.g. an ItemInstance's definitionId
  final int tier;          // e.g. an ItemInstance's class
}
```

**`combine_resolver.dart`**:

```dart
class CombineResolver {
  const CombineResolver();

  CombineResult resolve({
    required List<CombineInput> inputs,
    required bool atMaxTierForGrade,
    required RuleContext gradeContext,
    required EvolutionDefinition gradeEvolution, // empty candidates == no grade path
    required TrainingProfile gradeProfile,
    required RngService rng,
  }) {
    if (inputs.length < 2) {
      throw ArgumentError('Combine requires at least 2 inputs');
    }
    final first = inputs.first;
    for (final input in inputs.skip(1)) {
      if (input.matchKey != first.matchKey || input.tier != first.tier) {
        throw CombineMismatchException(first, input);
      }
    }

    final odds = CombineOdds.forAttempt(tier: first.tier, inputCount: inputs.length);
    final roll = rng.nextDouble() * 100; // 0-100
    var outcome = roll < odds.failPercent
        ? CombineOutcome.fail
        : roll < odds.failPercent + odds.normalPercent
            ? CombineOutcome.classUpgrade
            : CombineOutcome.gradeUpgrade;

    EvolutionResult? evolutionResult;
    if (outcome == CombineOutcome.gradeUpgrade) {
      evolutionResult = const EvolutionResolver().resolve(
          context: gradeContext, current: gradeEvolution, profile: gradeProfile);
      if (!evolutionResult.evolved) {
        // no eligible grade branch right now -> falls back to a class upgrade
        outcome = CombineOutcome.classUpgrade;
      }
    }
    if (outcome == CombineOutcome.classUpgrade && atMaxTierForGrade) {
      // nothing left to gain within this grade -> escalate to a grade
      // attempt (caller guarantees this branch is only reachable when a
      // grade evolution IS available, via the upfront terminal-item check)
      evolutionResult = const EvolutionResolver().resolve(
          context: gradeContext, current: gradeEvolution, profile: gradeProfile);
      outcome = CombineOutcome.gradeUpgrade;
    }

    final survivorIndex = outcome == CombineOutcome.fail
        ? rng.nextInt(inputs.length)
        : rng.nextInt(inputs.length); // any index is equivalent; RNG for determinism/audit only

    return CombineResult(
      outcome: outcome,
      survivorIndex: survivorIndex,
      chosenGradeTargetId: evolutionResult?.chosenCandidate?.targetId,
    );
  }
}
```

**`combine_result.dart`**:

```dart
class CombineResult {
  const CombineResult({required this.outcome, required this.survivorIndex, this.chosenGradeTargetId});
  final CombineOutcome outcome;
  final int survivorIndex;
  final String? chosenGradeTargetId; // set only when outcome == gradeUpgrade
}
```

**`combine_exceptions.dart`**:

```dart
class CombineMismatchException implements Exception {
  const CombineMismatchException(this.first, this.mismatched);
  final CombineInput first;
  final CombineInput mismatched;
}
```

`CombineResolver` knows nothing about resources, "which plugin," or Tome
placements — it is purely: given N same-id/same-tier inputs, an optional
grade-evolution target, and an RNG, produce one outcome. This mirrors
`EvolutionResolver`'s own "pure function of its inputs" shape and is
reusable as-is by any future plugin with its own combinable content, as
long as that plugin supplies a `CombineInput` list, an optional
`EvolutionDefinition` for grade branching, and a `TrainingProfile`.

### 2. Item plugin: data model changes

**`ItemInstance`** (`item_instance.dart`) gains one new field:

```dart
class ItemInstance {
  const ItemInstance({required this.definitionId, required this.owner, this.itemClass = 1});
  final String definitionId;
  final EntityId owner;
  final int itemClass; // starts at 1; the only mutable-over-time field this class has
}
```

Updating it after a combine still goes through `ComponentStore.add`'s
existing overwrite semantics — no new mutation primitive needed.

**`ItemDefinition`** (`item_definition.dart`) gains three new fields, all
optional/defaulted so every existing item definition keeps compiling
unchanged and stays non-combinable until a content author opts in:

```dart
class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.category,
    required this.tags,
    required this.properties,
    this.requirement,
    this.trainingWeights = const {},
    this.modifiersFor = _noModifiers,
    this.maxClass,                        // null = not combinable (no class ceiling declared)
    this.gradeEvolutionCandidates = const [], // empty = terminal grade, no further grade to reach
    this.classScalingPercent = 15,        // % added to each property per class above 1
  });
  final int? maxClass;
  final List<EvolutionCandidate> gradeEvolutionCandidates;
  final num classScalingPercent;
  // ...existing fields unchanged

  /// Builds the `EvolutionDefinition` this item's grade branches
  /// represent, for `EvolutionResolver.resolve` to consume — exactly
  /// mirrors `TechniqueDefinition.toEvolutionDefinition()`
  /// (`technique_definition.dart`), which already proved this "candidates
  /// embedded in the content definition, built into an EvolutionDefinition
  /// on demand" pattern. No separate evolution-definition registry is
  /// introduced; `tier` is passed through as this item's `category`
  /// (`EvolutionDefinition.tier` is descriptive-only, never read by the
  /// resolver).
  EvolutionDefinition toGradeEvolutionDefinition() =>
      EvolutionDefinition(id: id, tier: category, candidates: gradeEvolutionCandidates);

  /// Pure per-class stat scaling: `base * (1 + classScalingPercent/100 *
  /// (itemClass-1))` per property. `modifiersFor` itself is left
  /// unscaled/unchanged (it already has zero production call sites —
  /// `ItemActionInterpreter` reads `properties` directly, not
  /// `modifiersFor`); this method is what `ItemActionInterpreter` calls
  /// instead, once it knows a placement's live `itemClass` (see Section 4).
  Map<String, num> scaledProperties(int itemClass) => {
        for (final entry in properties.entries)
          entry.key: entry.value * (1 + classScalingPercent / 100 * (itemClass - 1)),
      };
}
```

**`item_content.dart`** parsing gains: `maxClass` read straight from
`extra['maxClass']` (absent by default); `gradeEvolutionCandidates`
parsed from `extra['gradeEvolution']` using the exact same shape/loop
`technique_content.dart` already uses for `extra['evolution']` (a list of
`{'targetId': ..., 'tags': [...]}` maps); `classScalingPercent` from
`extra['classScalingPercent']`, defaulting to 15.

**Content authoring contract:** a grade chain (e.g. `simple_knife` →
`sharp_knife` → `masterwork_knife`) is 2+ separate `ItemDefinition`s, each
its own `maxClass` (the spec's example: 3 / 6 / 9), linked by
`simple_knife`'s `gradeEvolutionCandidates` containing an
`EvolutionCandidate(targetId: 'sharp_knife', ...)`. A definition with
multiple candidates (multiple next-grade items from one source item) is
exactly the "one content type derived into multiple grade items" case —
already fully supported by `EvolutionCandidate`'s existing list shape, no
new Core concept required, and no registry lookup needed since the
candidates travel with the item's own content definition.

### 3. Item plugin: `combineItems`

New function in `item_lifecycle.dart`:

```dart
EntityId combineItems(
  EntityId owner,
  List<EntityId> instanceEntities,
  PluginContext context,
) {
  final instances = [for (final e in instanceEntities) context.components.get<ItemInstance>(e)!];
  final first = instances.first;
  for (final i in instances.skip(1)) {
    if (i.definitionId != first.definitionId || i.itemClass != first.itemClass) {
      throw CombineMismatchException(/* ... */);
    }
  }

  final definition = itemDefinition(first.definitionId, context);
  if (definition.maxClass == null) {
    throw CombineNotAvailableException(first.definitionId); // never opted in
  }
  final atMax = first.itemClass >= definition.maxClass!;
  final gradeEvolution = definition.toGradeEvolutionDefinition(); // candidates travel with the item's own content

  final ruleContext = context.ruleContextFor(owner);
  final hasGradePath = const EvolutionResolver()
      .resolve(context: ruleContext, current: gradeEvolution, profile: TrainingProfile(definition.trainingWeights))
      .evolved;
  if (atMax && !hasGradePath) {
    throw CombineNotAvailableException(first.definitionId); // true terminal item
  }

  final cost = first.itemClass; // flat per attempt
  context.resources.consume(owner, ItemResources.upgradePoints, cost); // throws InsufficientResourceException

  final result = const CombineResolver().resolve(
    inputs: [for (final i in instances) CombineInput(matchKey: i.definitionId, tier: i.itemClass)],
    atMaxTierForGrade: atMax,
    gradeContext: ruleContext,
    gradeEvolution: gradeEvolution,
    gradeProfile: TrainingProfile(definition.trainingWeights),
    rng: context.rng,
  );

  final survivor = instanceEntities[result.survivorIndex];
  for (final e in instanceEntities) {
    if (e != survivor) context.entities.destroy(e);
  }

  switch (result.outcome) {
    case CombineOutcome.fail:
      context.events.publish(ItemCombineFailed(owner, first.definitionId, first.itemClass));
    case CombineOutcome.classUpgrade:
      context.components.add(survivor, ItemInstance(
          definitionId: first.definitionId, owner: owner, itemClass: first.itemClass + 1));
      _reflectInTome(owner, first.definitionId, first.definitionId, context);
      context.events.publish(ItemCombineSucceeded(
          owner, first.definitionId, CombineOutcome.classUpgrade, first.definitionId, first.itemClass + 1));
    case CombineOutcome.gradeUpgrade:
      final newId = result.chosenGradeTargetId!;
      context.components.add(survivor, ItemInstance(definitionId: newId, owner: owner, itemClass: first.itemClass));
      _reflectInTome(owner, first.definitionId, newId, context);
      context.events.publish(ItemCombineSucceeded(
          owner, first.definitionId, CombineOutcome.gradeUpgrade, newId, first.itemClass));
  }
  return survivor;
}
```

`_reflectInTome` mirrors `game_run.dart`'s existing `replaceWithEvolved`
pattern exactly: find the placement whose `buildComponentRef.contentId ==
oldId` (if any — a no-op if the survivor isn't currently placed), then
`context.tome.replace(owner, placement.slot, BuildComponentRef(referenceType:
itemReferenceType, contentId: newId, instanceEntityId: survivor))`.

`ItemResources.upgradePoints = 'upgrade_points'` — new constant in
`item_vocabulary.dart`. The Item plugin registers a `ResourceDefinition`
for it in `ItemPlugin.initialize` (unbounded max, or a sane default cap —
implementation detail, not gameplay-critical per this spec's non-goals).

### 4. `BuildComponentRef` extension

One new nullable field, additive, defaulting to `null` for every existing
call site (technique placements, martial/elemental — untouched):

```dart
class BuildComponentRef {
  const BuildComponentRef({required this.referenceType, required this.contentId, this.instanceEntityId});
  final String referenceType;
  final String contentId;
  final EntityId? instanceEntityId; // set only by Item plugin placements
}
```

`addItemToTome` (`item_lifecycle.dart`) is updated to pass the owning
`ItemInstance`'s entity id as `instanceEntityId` when constructing its
`BuildComponentRef`.

`item_action_interpreter.dart` (`lib/src/plugins/build_interpretation/`)
changes: it already resolves `item = itemDefinitionFromContent(definition)`
and reads `item.properties['attack']` directly (it has never called
`modifiersFor`, which has zero production call sites today and is left
unscaled/unchanged by this spec). The one-line change: read
`item.scaledProperties(itemClass)['attack']` instead of
`item.properties['attack']`, where `itemClass` comes from looking up
`ref.instanceEntityId`'s live `ItemInstance.itemClass` when
`instanceEntityId != null`, else falls back to class 1 (covers any
placement that doesn't carry one, e.g. if content is ever placed without
going through `addItemToTome`).
`technique_action_interpreter.dart` is untouched — technique refs never
set `instanceEntityId`.

### 5. Events (`item_events.dart`)

```dart
class ItemCombineSucceeded {
  const ItemCombineSucceeded(this.owner, this.fromDefinitionId, this.outcome, this.toDefinitionId, this.newClass);
  final EntityId owner;
  final String fromDefinitionId;
  final CombineOutcome outcome; // classUpgrade | gradeUpgrade
  final String toDefinitionId;
  final int newClass;
}

class ItemCombineFailed {
  const ItemCombineFailed(this.owner, this.definitionId, this.itemClass);
  final EntityId owner;
  final String definitionId;
  final int itemClass;
}
```

## Rule summary (for quick reference)

- Combine requires ≥2 owned `ItemInstance`s sharing `definitionId` +
  `itemClass`.
- Cost: flat `upgrade_points` = current `itemClass` (not multiplied by
  input count).
- One roll per attempt: `fail` / `classUpgrade` (survivor's `itemClass`
  +1, same `definitionId`) / `gradeUpgrade` (survivor's `definitionId`
  becomes an `EvolutionResolver`-chosen target, `itemClass` unchanged).
- Base odds (2 inputs): `fail = min(10 + (class-1)*10, 60)`,
  `rare = max(15 - (class-1)*2, 5)`, `normal = 100 - fail - rare`.
- Each input beyond 2: nominally `fail -6`, `normal +4`, `rare +2`; once
  `fail` would drop below its floor (5), the shortfall is pulled back out
  of the normal/rare gains proportionally (2:1) so the three always sum
  to exactly 100% — see `CombineOdds.forAttempt` in Section 1.
- At current grade's `maxClass`: a `normal` roll is treated as `rare`
  instead (only meaningful if a grade path exists — see terminal rule).
- A `rare` roll with no eligible grade candidate right now falls back to
  `normal` instead.
- Terminal (Combine blocked entirely, checked before spending anything):
  `itemClass >= maxClass` **and** no eligible `gradeEvolutionCandidates`
  entry.
- On `fail`: exactly 1 input survives unchanged (RNG-picked), the rest
  are destroyed. On success: exactly 1 input survives, upgraded in
  place; the rest are destroyed.
- Stat scaling: each property scales
  `base * (1 + classScalingPercent/100 * (itemClass-1))`,
  `classScalingPercent` defaults to 15, is per-item-definition data.
- Works identically whether the survivor is currently Tome-placed or not
  (placement, if any, is transparently updated).

## Dependency/architecture properties preserved

- `lib/src/combine/` depends only on `lib/src/evolution/`,
  `lib/src/rng/`, `lib/src/rule/`, `lib/src/training/` — all Core, no
  plugin knowledge, matching the "Combat must never know Magic exists"
  dependency direction rule.
- No martial-arts/magic/cultivation vocabulary anywhere in Core; `class`,
  `grade`, `upgrade_points` are Item-plugin-local naming choices layered
  on top of generic `CombineInput.tier`/`EvolutionCandidate.targetId`/
  `ResourcePool` primitives.
- Grade branching reuses `EvolutionDefinition`/`EvolutionCandidate`
  exactly as-is — no changes to `evolution_definition.dart`,
  `evolution_candidate.dart`, `evolution_resolver.dart`, or
  `evolution_result.dart`. Any plugin can register its own
  `EvolutionDefinition`s for its own combinable content and get
  multi-branch grade combining for free.
- `BuildComponentRef`'s new field is additive and optional — Technique/
  Martial/Elemental placements are byte-for-byte unaffected.

## Test plan

- **Core** (`test/combine/`): `CombineOdds.forAttempt` boundary cases
  (class 1/2 inputs, class 6 cap, extra-input floor at fail=5%, sum
  always 100); `CombineResolver.resolve` — mismatch throws, deterministic
  RNG reproducibility (same seed → same outcome/survivor), max-tier
  normal→rare escalation, no-grade-path rare→normal fallback.
- **Item plugin** (`test/plugins/item/`): `combineItems` — cost
  deduction, `InsufficientResourceException` when unaffordable,
  `CombineNotAvailableException` for a non-opted-in item and for a true
  terminal item, class-upgrade mutates survivor in place (others
  destroyed), grade-upgrade swaps `definitionId` (others destroyed),
  fail destroys N-1/keeps 1 unchanged, events published with correct
  payloads, Tome-placed survivor's placement is transparently updated
  (slot/size/rotation preserved), unplaced survivor leaves the Tome
  untouched.
- **Integration** (`test/integration/`): combine a Tome-placed item
  end-to-end and confirm `ActiveBuild` resolution / `item_action_interpreter`
  output reflects the new class/grade's scaled stats afterward; a
  multi-candidate `EvolutionDefinition` grade branch picks among 2+
  target items according to `trainingWeights` weighting across repeated
  seeded runs.
