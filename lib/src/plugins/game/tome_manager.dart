import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'decision_log.dart';
import 'game_run.dart' show ownedComponentRefs;
import 'run_content.dart';
import 'run_events.dart';
import 'run_result.dart';

/// Owns everything about `runGame`'s Tome placement/upgrade-spend loop:
/// which slots are unlocked, the Tome-change history (`tomeHistory`),
/// which item ids have ever been unlocked (`itemsUnlocked`), and how
/// many upgrade points have been spent so far. Extracted from `runGame`
/// (previously 5 nested closures sharing that function's mutable scope —
/// see `ARCHITECTURE_AUDIT.md`'s god-function finding) so this piece of
/// the run is independently constructable and readable without the rest
/// of `runGame`'s 600+ lines. Every method here does exactly what the
/// closure it replaced did — no behavior change, only where the code
/// lives and what it closes over.
class TomeManager {
  TomeManager({
    required this.character,
    required this.context,
    required this.recordingPolicy,
    required this.events,
    required this.unlockedSlots,
  });

  final EntityId character;
  final PluginContext context;
  final RecordingDecisionPolicy recordingPolicy;
  final EventBus events;

  /// The slots currently open for placement — starts at
  /// `RunTomeSlots.startingUnlockedCount` and grows one at a time via
  /// [unlockNextSlot].
  final List<SlotId> unlockedSlots;
  var _nextLockedSlotIndex = RunTomeSlots.startingUnlockedCount;

  final tomeHistory = <TomeSnapshot>[];
  final itemsUnlocked = <String>[];
  var upgradeSpendCounter = 0;

  /// Whether a further slot remains to unlock — `RewardStage.rewardCandidates`
  /// only offers `RewardKind.unlockSlot` while this is true.
  bool get hasLockedSlot => _nextLockedSlotIndex < RunTomeSlots.all.length;

  void snapshot(String stepName) {
    final snapshotComponents = context.tome
        .resolve(character, ownedRefs: ownedComponentRefs(character, context))
        .active;
    tomeHistory.add(TomeSnapshot(afterStep: stepName, components: snapshotComponents));
    events.publish(TomeChanged(stepName: stepName, components: snapshotComponents));
  }

  List<SlotId> orderedUnlockedSlots() {
    final occupied = context.tome.inspect(character).map((p) => p.slot).toSet();
    return [
      for (final s in unlockedSlots)
        if (!occupied.contains(s)) s,
      for (final s in unlockedSlots)
        if (occupied.contains(s)) s,
    ];
  }

  void placeItem(ItemDefinition item, String stepName) {
    final ref = BuildComponentRef(referenceType: itemReferenceType, contentId: item.id);
    final slot = recordingPolicy.chooseSlot(ref, orderedUnlockedSlots());
    final existing = context.tome.inspect(character).where((p) => p.slot == slot);
    if (existing.isNotEmpty) {
      if (!recordingPolicy.chooseReplace(slot, existing.single.buildComponentRef, ref)) return;
      context.tome.remove(character, slot);
    }
    addItemToTome(character, slot, item, context);
    if (!itemsUnlocked.contains(item.id)) itemsUnlocked.add(item.id);
    snapshot(stepName);
  }

  void placeTechnique(TechniqueDefinition technique, String stepName) {
    final ref = BuildComponentRef(referenceType: techniqueReferenceType, contentId: technique.id);
    final slot = recordingPolicy.chooseSlot(ref, orderedUnlockedSlots());
    final existing = context.tome.inspect(character).where((p) => p.slot == slot);
    if (existing.isNotEmpty) {
      if (!recordingPolicy.chooseReplace(slot, existing.single.buildComponentRef, ref)) return;
      context.tome.remove(character, slot);
    }
    addTechniqueToTome(character, slot, technique, context);
    snapshot(stepName);
  }

  /// The slot holding the placement whose instance id is [instanceId], or
  /// `null` if that variant is not currently in the Tome.
  SlotId? slotOfTechniqueVariant(EntityId instanceId) {
    for (final p in context.tome.inspect(character)) {
      if (p.buildComponentRef.instanceEntityId == instanceId) return p.slot;
    }
    return null;
  }

  /// Hangs owned technique-variant [instanceId] in the Tome — the
  /// instance-identity replacement for [placeTechnique]. Mirrors
  /// [placeItem]'s slot/replace flow; `hangTechniqueVariant` itself writes
  /// the `BuildComponentRef` (with `instanceEntityId`) and publishes
  /// `TechniqueAddedToTome`.
  void placeTechniqueVariant(EntityId instanceId, String stepName) {
    final variant = context.components.get<TechniqueVariant>(instanceId)!;
    final ref = BuildComponentRef(
      referenceType: techniqueReferenceType,
      contentId: variant.baseFamilyId,
      instanceEntityId: instanceId,
    );
    final slot = recordingPolicy.chooseSlot(ref, orderedUnlockedSlots());
    final existing = context.tome.inspect(character).where((p) => p.slot == slot);
    if (existing.isNotEmpty) {
      if (!recordingPolicy.chooseReplace(
          slot, existing.single.buildComponentRef, ref)) {
        return;
      }
      context.tome.remove(character, slot);
    }
    hangTechniqueVariant(slot, instanceId, context);
    snapshot(stepName);
  }

  /// Drops whatever is in [slot] and hangs variant [instanceId] there —
  /// the evolution/unlock entry point (an evolved branch enters at the
  /// exact slot its base occupied).
  void replaceWithTechniqueVariant(
      SlotId slot, EntityId instanceId, String stepName) {
    context.tome.remove(character, slot);
    hangTechniqueVariant(slot, instanceId, context);
    snapshot(stepName);
  }

  /// Unlocks the next slot in `RunTomeSlots.all`'s fixed order — the
  /// `RewardKind.unlockSlot` reward's mutation, called from `RewardStage`
  /// rather than reached into directly, since slot-unlocking is this
  /// manager's own state. Returns the newly-unlocked slot.
  SlotId unlockNextSlot() {
    final slot = RunTomeSlots.all[_nextLockedSlotIndex];
    unlockedSlots.add(slot);
    _nextLockedSlotIndex++;
    return slot;
  }

  void applyUpgrade(String choice) {
    if (choice == 'stat:health') {
      final health = context.components.get<HealthComponent>(character)!;
      context.components
          .add(character, HealthComponent(current: health.current + 15, max: health.max + 15));
      return;
    }
    if (choice == 'stat:speed') {
      final combatant = context.components.get<CombatantComponent>(character)!;
      context.components.add(
          character, CombatantComponent(team: combatant.team, initiative: combatant.initiative + 2));
      return;
    }
    if (choice == 'stat:attack') {
      for (final tag in WeaponStatTags.values) {
        context.modifiers.add(Modifier(
          source: ModifierSource('upgrade:stat:attack:${character.value}:$upgradeSpendCounter:$tag'),
          target: character,
          stat: tag,
          operation: ModifierOperation.add,
          value: 2,
        ));
      }
      return;
    }
    if (choice.startsWith('item:')) {
      final id = choice.substring('item:'.length);
      final item = itemDefinition(id, context);
      final stat = WeaponStatTags.matchOrFallback(item.tags, 'item:$id');
      context.modifiers.add(Modifier(
        source: ModifierSource('upgrade:item:$id:${character.value}:$upgradeSpendCounter'),
        target: character,
        stat: stat,
        operation: ModifierOperation.add,
        value: 2,
      ));
      return;
    }
    if (choice.startsWith('technique:')) {
      final id = choice.substring('technique:'.length);
      final technique = techniqueDefinition(id, context);
      final stat = WeaponStatTags.matchOrFallback(technique.tags, techniqueSubject(id));
      context.modifiers.add(Modifier(
        source: ModifierSource('upgrade:technique:$id:${character.value}:$upgradeSpendCounter'),
        target: character,
        stat: stat,
        operation: ModifierOperation.add,
        value: 2,
      ));
    }
  }

  /// Spends banked upgrade points, then offers equip/unequip choices
  /// until the policy is done — the same two-phase loop `runGame`'s own
  /// `manageTome` closure ran, unchanged. [ownedItemIds]/[knownTechniqueIds]
  /// are passed in rather than called as free functions from here, so
  /// this class has no dependency on `run_content.dart`'s reward-pool
  /// constant beyond what it already needs for slot data.
  void manageTome({
    required Set<String> Function() ownedItemIds,
    required Set<String> Function() knownTechniqueIds,
  }) {
    while (context.resources.currentOf(character, ItemResources.upgradePoints) > 0) {
      final candidates = <String>[
        'stat:health',
        'stat:attack',
        'stat:speed',
        for (final id in ownedItemIds()) 'item:$id',
        for (final id in knownTechniqueIds()) 'technique:$id',
        'skip',
      ];
      final choice = recordingPolicy.chooseUpgradeSpend(candidates);
      if (choice == 'skip') break;
      context.resources.subtract(character, ItemResources.upgradePoints, 1);
      upgradeSpendCounter++;
      applyUpgrade(choice);
      events.publish(UpgradePointSpent(target: choice, amount: 1));
    }

    // A chosen `equip:` candidate can still end up doing nothing (the
    // target slot is occupied and `chooseReplace` declines it) — track
    // those so a declined attempt isn't offered again this visit. Without
    // this, a policy that deterministically re-picks the same candidate
    // every time (any `DefaultRunDecisionPolicy`-derived one, by
    // construction) would loop forever re-offering-and-declining the
    // exact same equip. A 500-iteration cap is a pure safety net on top
    // (mirrors the run's own 200-cycle cap), never meant to be hit.
    final rejectedThisVisit = <String>{};
    for (var i = 0; i < 500; i++) {
      final placements = context.tome.inspect(character);
      final placedRefs = {
        for (final p in placements) (p.buildComponentRef.referenceType, p.buildComponentRef.contentId),
      };
      // Auto-equip only ever fills an EMPTY unlocked slot on its own
      // initiative — it never forces an eviction. With no empty slot
      // left, no `equip:` candidate is offered at all (regardless of
      // what's benched); freeing a slot via `unequip:` first is the only
      // way to make room. Without this, a "replace: always true" policy
      // (like `DefaultRunDecisionPolicy`) would keep swapping benched
      // items into already-occupied slots, evicting whatever was there
      // (including a hard-won evolved technique) purely because it
      // happened to be the first candidate this iteration.
      final hasEmptySlot = unlockedSlots.length > placements.length;
      final benchedItemIds = [
        if (hasEmptySlot)
          for (final id in ownedItemIds())
            if (!placedRefs.contains((itemReferenceType, id)) &&
                isItemUsable(character, itemDefinition(id, context), context) &&
                !rejectedThisVisit.contains('equip:item:$id'))
              id,
      ];
      // Benched technique-variant instances: owned variants not currently
      // hung anywhere — instance-keyed, not family-keyed, since two
      // variants of the same family share a contentId (SP1 Task 10).
      final placedVariantInstances = {
        for (final p in placements)
          if (p.buildComponentRef.referenceType == techniqueReferenceType &&
              p.buildComponentRef.instanceEntityId != null)
            p.buildComponentRef.instanceEntityId!,
      };
      final benchedVariantIds = [
        if (hasEmptySlot)
          for (final e in ownedTechniqueVariants(character, context))
            if (!placedVariantInstances.contains(e) &&
                !rejectedThisVisit.contains('equip:techniqueVariant:${e.value}'))
              e,
      ];
      // `'done'` sits between the equip/unequip options — every equip:
      // option before it, every unequip: option after — so
      // `DefaultRunDecisionPolicy`'s "always take the first option"
      // always means "equip whatever's benched," never "unequip your
      // own gear for no reason."
      final candidates = <String>[
        for (final id in benchedItemIds) 'equip:item:$id',
        for (final e in benchedVariantIds) 'equip:techniqueVariant:${e.value}',
        'done',
        for (final p in placements)
          'unequip:${p.slot.id}:${p.buildComponentRef.referenceType}:${p.buildComponentRef.contentId}',
      ];
      if (candidates.length == 1) break; // nothing benched or placed to manage
      final choice = recordingPolicy.chooseTomeAction(candidates);
      if (choice == 'done') break;
      if (choice.startsWith('equip:item:')) {
        final id = choice.substring('equip:item:'.length);
        placeItem(itemDefinition(id, context), 'Manage Tome (equip)');
        if (!context.tome.inspect(character).any(
            (p) => p.buildComponentRef.referenceType == itemReferenceType && p.buildComponentRef.contentId == id)) {
          rejectedThisVisit.add(choice);
        }
      } else if (choice.startsWith('equip:techniqueVariant:')) {
        final value =
            int.parse(choice.substring('equip:techniqueVariant:'.length));
        final instanceId = EntityId(value);
        placeTechniqueVariant(instanceId, 'Manage Tome (equip)');
        final placed = context.tome
            .inspect(character)
            .any((p) => p.buildComponentRef.instanceEntityId == instanceId);
        if (!placed) rejectedThisVisit.add(choice);
      } else if (choice.startsWith('unequip:')) {
        final slotId = choice.substring('unequip:'.length).split(':').first;
        context.tome.remove(character, SlotId(slotId));
        snapshot('Manage Tome (unequip)');
      }
    }
  }
}
