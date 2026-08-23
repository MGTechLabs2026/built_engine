import '../entity/entity_id.dart';

/// Published via the owning [EventBus] whenever [CharacterService.create]
/// attaches a [CharacterComponent] to a new entity.
class CharacterCreated {
  const CharacterCreated(this.id);
  final EntityId id;
}
