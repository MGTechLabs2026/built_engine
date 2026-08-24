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
