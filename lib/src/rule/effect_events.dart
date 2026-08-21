import '../entity/entity_id.dart';

/// Published by [Damage] whenever it reduces an entity's health.
class EntityDamaged {
  const EntityDamaged(this.id, this.amount);

  final EntityId id;
  final num amount;
}

/// Published by [Heal] whenever it increases an entity's health.
class EntityHealed {
  const EntityHealed(this.id, this.amount);

  final EntityId id;
  final num amount;
}

/// Published by [Damage] when an entity's health reaches exactly 0.
class EntityKilled {
  const EntityKilled(this.id);

  final EntityId id;
}
