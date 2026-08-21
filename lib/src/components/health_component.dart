/// An entity's health pool. Effects that mutate [current] ([Damage],
/// [Heal]) keep it within `[0, max]` — this component itself stores
/// whatever values it's given without enforcing that.
class HealthComponent {
  const HealthComponent({required this.current, required this.max});

  final num current;
  final num max;
}
