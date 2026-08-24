import 'package:build_engine/build_engine.dart';

/// Published by `addTechniqueToTome` once a technique has actually been
/// inserted into [owner]'s Tome — the one new event this plugin adds, for
/// the same reason `ItemAddedToTome` was: `TomeService` has no `EventBus`
/// of its own to hook a "was inserted" event onto otherwise.
class TechniqueAddedToTome {
  const TechniqueAddedToTome(this.owner, this.definitionId, this.slot);

  final EntityId owner;
  final String definitionId;
  final SlotId slot;
}
