import 'package:build_engine/build_engine.dart';

import 'item_content.dart';
import 'item_events.dart';
import 'item_instance.dart';
import 'item_vocabulary.dart';

/// Thrown when Combine is attempted on an item that either never opted
/// in (`ItemDefinition.maxClass == null`) or has genuinely nowhere left
/// to go (already at its grade's `maxClass`, with no eligible grade
/// candidate right now) — the true-terminal case
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`).
class CombineNotAvailableException implements Exception {
  const CombineNotAvailableException(this.definitionId);

  final String definitionId;

  @override
  String toString() => 'Combine not available for: $definitionId';
}

/// A pure, non-throwing preview of whether [combineItems] would even
/// attempt a roll for [instanceEntities] right now — mirrors
/// `TomeService.validate`'s "never mutates, never throws" contract.
/// Does NOT check `ItemResources.upgradePoints` sufficiency — that's a
/// simpler, separate concern a caller can check directly via
/// `context.resources.currentOf`; this function only answers "are these
/// structurally eligible to combine" (same definitionId/itemClass,
/// same owner, and somewhere left to go).
bool canCombine(
  EntityId owner,
  List<EntityId> instanceEntities,
  PluginContext context,
) {
  if (instanceEntities.length < 2) return false;
  if (instanceEntities.toSet().length != instanceEntities.length) return false;

  final instances = [
    for (final e in instanceEntities) context.components.get<ItemInstance>(e),
  ];
  if (instances.any((i) => i == null)) return false;
  final resolved = instances.cast<ItemInstance>();

  final first = resolved.first;
  for (var i = 1; i < resolved.length; i++) {
    if (resolved[i].definitionId != first.definitionId ||
        resolved[i].itemClass != first.itemClass) {
      return false;
    }
  }
  if (resolved.any((i) => i.owner != owner)) return false;

  final definition = itemDefinition(first.definitionId, context);
  if (definition.maxClass == null) return false;
  final atMax = first.itemClass >= definition.maxClass!;
  final gradeEvolution = definition.toGradeEvolutionDefinition();
  final ruleContext = context.ruleContextFor(owner);
  final hasGradePath = gradeEvolution.candidates.any(
    (candidate) => candidate.conditions.every((c) => c.evaluate(ruleContext)),
  );
  return !(atMax && !hasGradePath);
}

/// Combines [instanceEntities] — 2+ owned copies sharing the same
/// `definitionId`/`itemClass` — into one surviving, upgraded copy. Costs
/// `ItemResources.upgradePoints` flat per attempt (= the shared
/// `itemClass`), consumed via the generic `ResourcePool` *before* rolling
/// (an `InsufficientResourceException` leaves nothing mutated). One
/// `CombineResolver` roll then decides fail/tierUpgrade/branchUpgrade;
/// exactly one input entity survives (the rest destroyed), mutated in
/// place. If the survivor is currently Tome-placed, its placement is
/// transparently updated to the new definitionId via `TomeService.replace`
/// — mirrors `game_run.dart`'s `replaceWithEvolved` pattern exactly.
/// Returns the surviving instance's entity id. See
/// `docs/superpowers/specs/2026-08-24-item-combine-design.md`.
///
/// The upfront "is there anywhere left to go" terminal check
/// ([hasGradePath] below) deliberately does NOT call
/// `EvolutionResolver.resolve` — that call draws from `context.rng`
/// (via `weightedPick`) whenever at least one candidate is eligible, which
/// would silently shift every subsequent roll `CombineResolver.resolve`
/// makes (the fail/tierUpgrade/branchUpgrade roll itself, and the branch
/// pick within it) by one draw, breaking reproducibility from a given
/// seed. So eligibility is checked directly against
/// [EvolutionCandidate.conditions] instead — the same eligibility test
/// `EvolutionResolver.resolve` runs internally before it ever touches
/// `rng`.
EntityId combineItems(
  EntityId owner,
  List<EntityId> instanceEntities,
  PluginContext context,
) {
  if (instanceEntities.length < 2) {
    throw ArgumentError.value(
      instanceEntities.length, 'instanceEntities', 'Combine requires at least 2 items');
  }
  if (instanceEntities.toSet().length != instanceEntities.length) {
    throw ArgumentError.value(
      instanceEntities, 'instanceEntities', 'Combine requires distinct instance entities');
  }

  final instances = [
    for (final e in instanceEntities) context.components.get<ItemInstance>(e)!,
  ];
  final first = instances.first;
  for (var i = 1; i < instances.length; i++) {
    if (instances[i].definitionId != first.definitionId ||
        instances[i].itemClass != first.itemClass) {
      throw CombineMismatchException(
        CombineInput(matchKey: first.definitionId, tier: first.itemClass),
        CombineInput(matchKey: instances[i].definitionId, tier: instances[i].itemClass),
      );
    }
  }
  if (instances.any((i) => i.owner != owner)) {
    throw ArgumentError.value(
      owner, 'owner', 'Combine requires all instances to be owned by owner');
  }

  final definition = itemDefinition(first.definitionId, context);
  if (definition.maxClass == null) {
    throw CombineNotAvailableException(first.definitionId);
  }
  final atMax = first.itemClass >= definition.maxClass!;
  final gradeEvolution = definition.toGradeEvolutionDefinition();
  final ruleContext = context.ruleContextFor(owner);
  final gradeProfile = TrainingProfile(definition.trainingWeights);
  final hasGradePath = gradeEvolution.candidates.any(
    (candidate) => candidate.conditions.every((c) => c.evaluate(ruleContext)),
  );
  if (atMax && !hasGradePath) {
    throw CombineNotAvailableException(first.definitionId);
  }

  context.resources.consume(owner, ItemResources.upgradePoints, first.itemClass);

  final result = const CombineResolver().resolve(
    inputs: [
      for (final i in instances) CombineInput(matchKey: i.definitionId, tier: i.itemClass),
    ],
    atMaxTierForBranch: atMax,
    branchContext: ruleContext,
    branchDefinition: gradeEvolution,
    branchProfile: gradeProfile,
    rng: context.rng,
  );

  // CombineResolver's survivorIndex is uniform-random over all inputs —
  // correctly so, since Core has no concept of Tome placement and every
  // input is otherwise interchangeable to it. But the Item plugin DOES
  // know about Tome placement, and a currently-placed input surviving
  // unplaced (or vice versa) is a real, everyday outcome difference: if
  // exactly one of the original inputs is Tome-placed, that one must
  // survive, or its slot goes stale pointing at a destroyed entity. Only
  // this plugin-level override reaches into that decision — Core/
  // CombineResolver itself is untouched.
  final itemPlacements = context.tome
      .inspect(owner)
      .where((p) => p.buildComponentRef.referenceType == itemReferenceType)
      .toList();
  final placedIds = itemPlacements.map((p) => p.buildComponentRef.instanceEntityId).toSet();
  final survivor = instanceEntities.firstWhere(
    placedIds.contains,
    orElse: () => instanceEntities[result.survivorIndex],
  );
  for (final e in instanceEntities) {
    if (e != survivor) {
      // A non-survivor that was itself separately Tome-placed (distinct
      // from the survivor's own placement, handled by
      // `_reflectCombineInTome` below) would otherwise leave that slot's
      // `BuildComponentRef` pointing at a destroyed entity —
      // `ItemActionInterpreter`'s `?? 1` fallback then treats the stale
      // placement as a live class-1 item and grants a phantom stat
      // modifier for it. Remove any such placement before destroying.
      for (final placement in itemPlacements) {
        if (placement.buildComponentRef.instanceEntityId == e) {
          context.tome.remove(owner, placement.slot);
        }
      }
      context.components.remove<ItemInstance>(e);
      context.entities.destroy(e);
    }
  }

  switch (result.outcome) {
    case CombineOutcome.fail:
      context.events.publish(
        ItemCombineFailed(owner, first.definitionId, first.itemClass),
      );
    case CombineOutcome.tierUpgrade:
      final newClass = first.itemClass + 1;
      context.components.add(
        survivor,
        ItemInstance(definitionId: first.definitionId, owner: owner, itemClass: newClass),
      );
      _reflectCombineInTome(owner, first.definitionId, survivor, context);
      context.events.publish(ItemCombineSucceeded(
        owner, first.definitionId, CombineOutcome.tierUpgrade, first.definitionId, newClass,
      ));
    case CombineOutcome.branchUpgrade:
      final newId = result.chosenBranchTargetId!;
      context.components.add(
        survivor,
        ItemInstance(definitionId: newId, owner: owner, itemClass: first.itemClass),
      );
      _reflectCombineInTome(owner, newId, survivor, context);
      context.events.publish(ItemCombineSucceeded(
        owner, first.definitionId, CombineOutcome.branchUpgrade, newId, first.itemClass,
      ));
  }
  return survivor;
}

/// Updates [owner]'s Tome placement for [survivorInstance] (if any) to
/// point at [newId] instead — a no-op if the survivor wasn't placed.
/// Adapted from `game_run.dart`'s `replaceWithEvolved` pattern, but
/// matches by [instanceEntityId] rather than `contentId`: Combine's own
/// precondition is owning 2+ copies of the *same* `definitionId`, so
/// matching by `contentId` alone (as `replaceWithEvolved` does for
/// techniques, which have no per-copy instances) risks either hitting
/// `.single`'s `StateError` when more than one of the combined copies is
/// currently placed, or silently reassigning some unrelated third
/// placement of the same `definitionId` that was never part of this
/// combine. Matching on [survivorInstance]'s own entity id is unique
/// under normal single-placement usage and scopes the update to exactly
/// the survivor's own slot, if any. Uses `.first` rather than `.single`
/// so a pathological multi-placement of the very same instance entity
/// still degrades to "update the first one found" instead of crashing —
/// this helper's whole purpose is to never throw here, since it runs
/// after resources are already consumed and inputs already destroyed. A
/// non-survivor input that was separately Tome-placed elsewhere has
/// already had that placement removed by `combineItems`'s destroy loop
/// before this helper runs, so no stale placement is left for it to
/// worry about here.
void _reflectCombineInTome(
  EntityId owner,
  String newId,
  EntityId survivorInstance,
  PluginContext context,
) {
  final placement = context.tome.inspect(owner).where((p) =>
      p.buildComponentRef.referenceType == itemReferenceType &&
      p.buildComponentRef.instanceEntityId == survivorInstance).toList();
  if (placement.isEmpty) return;
  context.tome.replace(
    owner,
    placement.first.slot,
    BuildComponentRef(
      referenceType: itemReferenceType,
      contentId: newId,
      instanceEntityId: survivorInstance,
    ),
  );
}
