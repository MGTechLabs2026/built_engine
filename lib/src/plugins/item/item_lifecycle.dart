import 'package:build_engine/build_engine.dart';

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

