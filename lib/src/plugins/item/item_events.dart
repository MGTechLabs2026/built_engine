import 'package:build_engine/build_engine.dart';

/// Published by `addItemToTome` once an item has actually been inserted
/// into [owner]'s Tome. The one new event this plugin adds — everything
/// else ("discovered", "mastery changed", "became usable") already has a
/// generic equivalent (`SubjectDiscovered`/`MasteryChanged`/
/// `SubjectUnlocked`) fired with an `item:<id>` subject, and `TomeService`
/// has no `EventBus` of its own to hook a "was inserted" event onto
/// otherwise.
class ItemAddedToTome {
  const ItemAddedToTome(this.owner, this.definitionId, this.slot);

  final EntityId owner;
  final String definitionId;
  final SlotId slot;
}

/// Published by `combineItems` when a combine attempt succeeds — either
/// [CombineOutcome.tierUpgrade] (same [toDefinitionId] as
/// [fromDefinitionId], [newClass] = old class + 1) or
/// [CombineOutcome.branchUpgrade] ([toDefinitionId] is the chosen grade
/// target, [newClass] unchanged from the inputs' shared class).
class ItemCombineSucceeded {
  const ItemCombineSucceeded(
    this.owner,
    this.fromDefinitionId,
    this.outcome,
    this.toDefinitionId,
    this.newClass,
  );

  final EntityId owner;
  final String fromDefinitionId;
  final CombineOutcome outcome;
  final String toDefinitionId;
  final int newClass;
}

/// Published by `combineItems` when a combine attempt fails — the
/// survivor is left unchanged at [itemClass]; N-1 of the inputs were
/// destroyed regardless.
class ItemCombineFailed {
  const ItemCombineFailed(this.owner, this.definitionId, this.itemClass);

  final EntityId owner;
  final String definitionId;
  final int itemClass;
}
