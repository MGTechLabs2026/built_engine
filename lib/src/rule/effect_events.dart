import '../entity/entity_id.dart';

/// Published by [Damage] whenever it's applied to an entity with a
/// `HealthComponent`. `amount` is the actual change in health after
/// clamping to `[0, max]` — it may be less than what [Damage] was
/// constructed with, or `0` if the entity was already at the clamp
/// boundary.
class EntityDamaged {
  const EntityDamaged(this.id, this.amount);

  final EntityId id;
  final num amount;
}

/// Published by [Heal] whenever it's applied to an entity with a
/// `HealthComponent`. `amount` is the actual change in health after
/// clamping to `[0, max]` — it may be less than what [Heal] was
/// constructed with, or `0` if the entity was already at the clamp
/// boundary.
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
