import 'package:build_engine/build_engine.dart';

import 'item_content.dart';
import 'item_definition.dart';
import 'item_events.dart';
import 'item_instance.dart';
import 'item_vocabulary.dart';

/// Thrown by [addItemToTome] when [ItemDefinition] fails
/// [isItemUsable] for the given owner — the Item plugin's own rejection
/// at its call boundary into the Tome, since `PlacementRule.isSatisfied`
/// has no owner parameter to check owner-scoped Discovery/Mastery state
/// against (see `item_plugin.dart`'s doc comment for the full reasoning).
class ItemNotUsableException implements Exception {
  const ItemNotUsableException(this.definitionId);

  final String definitionId;

  @override
  String toString() => 'Item not usable: $definitionId';
}

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

/// Creates a fresh entity representing one physical copy of [definitionId]
/// owned by [owner], attaches an [ItemInstance] to it, and returns the new
/// entity — the OWNED state. Independent of DISCOVERED: an owner can hold
/// an [ItemInstance] for an item it hasn't discovered yet (e.g. an unread
/// magic item), and can discover an item's existence before ever owning a
/// copy — see `item_plugin.dart`'s doc comment for why these two states
/// are deliberately never collapsed into one boolean.
EntityId ownItem(EntityId owner, String definitionId, PluginContext context) {
  final instance = context.entities.create();
  context.components.add(
    instance,
    ItemInstance(definitionId: definitionId, owner: owner),
  );
  return instance;
}

/// Whether [owner] holds at least one [ItemInstance] of [definitionId] —
/// queries live ECS state rather than storing a second "owned" flag
/// anywhere.
bool isItemOwned(EntityId owner, String definitionId, PluginContext context) {
  for (final entity in context.components.entitiesWith<ItemInstance>()) {
    final instance = context.components.get<ItemInstance>(entity)!;
    if (instance.owner == owner && instance.definitionId == definitionId) {
      return true;
    }
  }
  return false;
}

/// Moves [owner]'s discovery state for [item] forward — the DISCOVERED
/// state. An item with no mastery requirement (or `minimumLevel <= 0`,
/// i.e. nothing to train) is promoted straight to `unlocked` (USABLE) in
/// the same call, via `DiscoveryTracker.unlock`'s auto-promotion through
/// `discovered` — there is no mastery threshold left to cross later for
/// `buildItemUsabilityRules` to react to. An item with a real requirement
/// only reaches `discovered` (LOCKED) here; [buildItemUsabilityRules]'s
/// rule promotes it to `unlocked` once mastery training crosses the
/// threshold.
void discoverItem(EntityId owner, ItemDefinition item, PluginContext context) {
  final subject = itemSubject(item.id);
  final requirement = item.requirement;
  if (requirement == null || requirement.minimumLevel <= 0) {
    context.discovery.unlock(owner, subject);
  } else {
    context.discovery.discover(owner, subject);
  }
}

/// The generic eligibility check `ItemUsable(item, character)` from the
/// milestone brief, built entirely from existing `Condition`s: discovered
/// (or better) AND, if [item] has a requirement, mastery at least its
/// minimum level. No `if item == sword` special-casing anywhere.
List<Condition> usabilityConditionsFor(ItemDefinition item) => [
      IsDiscovered(itemSubject(item.id)),
      if (item.requirement != null)
        MasteryAtLeast(
          item.requirement!.masterySubject,
          item.requirement!.minimumLevel,
        ),
    ];

/// Evaluates [usabilityConditionsFor] against [owner] right now — the
/// USABLE state. Never stored; always recomputed from the live
/// Discovery/Mastery trackers via `PluginContext.ruleContextFor`.
bool isItemUsable(EntityId owner, ItemDefinition item, PluginContext context) {
  final ruleContext = context.ruleContextFor(owner);
  return usabilityConditionsFor(item).every((c) => c.evaluate(ruleContext));
}

/// Whether [owner]'s Tome currently contains [definitionId] as an
/// `'item'`-typed placement — the ACTIVE state. Delegates entirely to
/// `TomeService.inspect`; no separate "active" flag is stored anywhere.
bool isItemActive(EntityId owner, String definitionId, PluginContext context) {
  return context.tome.inspect(owner).any((placement) =>
      placement.buildComponentRef.referenceType == itemReferenceType &&
      placement.buildComponentRef.contentId == definitionId);
}

/// Inserts [item] into [owner]'s Tome at [slot] — but only if
/// [isItemUsable] first. Throws [ItemNotUsableException] (leaving the
/// Tome untouched) rather than calling `TomeService.insert` for an
/// unusable item; on success, publishes [ItemAddedToTome] and returns
/// normally exactly like `TomeService.insert` would (including
/// propagating its own `InvalidPlacementException`/`StateError` for a
/// bad slot/missing Tome). [instanceEntityId], when supplied, is the
/// specific owned [ItemInstance] this placement represents — carried
/// through to `BuildComponentRef.instanceEntityId` so `ItemActionInterpreter`
/// can read its live `itemClass` for stat scaling; omitted, placement
/// still works exactly as before (no per-copy state to resolve).
void addItemToTome(
  EntityId owner,
  SlotId slot,
  ItemDefinition item,
  PluginContext context, {
  EntityId? instanceEntityId,
}) {
  if (!isItemUsable(owner, item, context)) {
    throw ItemNotUsableException(item.id);
  }
  context.tome.insert(
    owner,
    slot,
    BuildComponentRef(
      referenceType: itemReferenceType,
      contentId: item.id,
      instanceEntityId: instanceEntityId,
    ),
  );
  context.events.publish(ItemAddedToTome(owner, item.id, slot));
}

/// Combines [instanceEntities] — 2+ owned copies sharing the same
/// `definitionId`/`itemClass` — into one surviving, upgraded copy. Costs
/// `ItemResources.upgradePoints` flat per attempt (= the shared
/// `itemClass`), consumed via the generic `ResourcePool` *before* rolling
/// (an `InsufficientResourceException` leaves nothing mutated). One
/// `CombineResolver` roll then decides fail/classUpgrade/gradeUpgrade;
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
/// makes (the fail/classUpgrade/gradeUpgrade roll itself, and the grade
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
    atMaxTierForGrade: atMax,
    gradeContext: ruleContext,
    gradeEvolution: gradeEvolution,
    gradeProfile: gradeProfile,
    rng: context.rng,
  );

  final survivor = instanceEntities[result.survivorIndex];
  for (final e in instanceEntities) {
    if (e != survivor) {
      context.components.remove<ItemInstance>(e);
      context.entities.destroy(e);
    }
  }

  switch (result.outcome) {
    case CombineOutcome.fail:
      context.events.publish(
        ItemCombineFailed(owner, first.definitionId, first.itemClass),
      );
    case CombineOutcome.classUpgrade:
      final newClass = first.itemClass + 1;
      context.components.add(
        survivor,
        ItemInstance(definitionId: first.definitionId, owner: owner, itemClass: newClass),
      );
      _reflectCombineInTome(owner, first.definitionId, first.definitionId, survivor, context);
      context.events.publish(ItemCombineSucceeded(
        owner, first.definitionId, CombineOutcome.classUpgrade, first.definitionId, newClass,
      ));
    case CombineOutcome.gradeUpgrade:
      final newId = result.chosenGradeTargetId!;
      context.components.add(
        survivor,
        ItemInstance(definitionId: newId, owner: owner, itemClass: first.itemClass),
      );
      _reflectCombineInTome(owner, first.definitionId, newId, survivor, context);
      context.events.publish(ItemCombineSucceeded(
        owner, first.definitionId, CombineOutcome.gradeUpgrade, newId, first.itemClass,
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
/// destroyed *non-survivor* input that was separately Tome-placed
/// elsewhere is deliberately not handled — out of scope; that placement
/// goes stale exactly like any other case `ItemActionInterpreter` already
/// tolerates.
void _reflectCombineInTome(
  EntityId owner,
  String oldId,
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
