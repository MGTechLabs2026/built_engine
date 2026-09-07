import 'package:build_engine/build_engine.dart';

/// Who a consumable's effect acts on. Fixed per effect variant
/// (SP3 §5.1.2): `heal` / `grant` / `removeAllStatuses` are `self`;
/// `attack` is `enemy`.
enum ConsumableTarget { self, enemy }

/// A consumable's effect — a closed set, one variant per
/// `ConsumableDefinition`. Parsing yields exactly one of these or throws
/// (SP3 §5.1.3). The interpreter maps each to a fixed `CombatAction`.
sealed class ConsumableEffectSpec {
  const ConsumableEffectSpec();
}

class ConsumableHeal extends ConsumableEffectSpec {
  const ConsumableHeal(this.amount);
  final num amount;
}

class ConsumableAttack extends ConsumableEffectSpec {
  const ConsumableAttack(this.damage, this.stat);
  final num damage;
  final String stat;
}

class ConsumableGrantModifier extends ConsumableEffectSpec {
  const ConsumableGrantModifier(this.stat, this.operation, this.value);
  final String stat;
  final ModifierOperation operation;
  final num value;
}

class ConsumableRemoveAllStatuses extends ConsumableEffectSpec {
  const ConsumableRemoveAllStatuses();
}

/// Immutable, content-derived — mirrors `ItemDefinition`'s shape.
/// [charges] is PER-COPY capacity (SP3 §5.1.1). [target] is always
/// consistent with [effect] — the parser guarantees it, and there is no
/// blanket default.
class ConsumableDefinition {
  const ConsumableDefinition({
    required this.id,
    required this.tags,
    this.charges = 1,
    this.priority = 0,
    required this.target,
    required this.effect,
  });

  final String id;
  final Set<String> tags;
  final int charges;
  final num priority;
  final ConsumableTarget target;
  final ConsumableEffectSpec effect;
}
