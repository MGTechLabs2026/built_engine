/// An entity's named numeric stats/attributes, stored as raw values.
///
/// This is a stopgap: `claude.md`'s Modifier System says derived stats
/// should be `base + modifiers`, computed by a future Modifier Engine.
/// Until that exists, [ModifyStat] mutates the raw value stored here
/// directly. Expect this component's role to change once Modifier Engine
/// lands.
class StatComponent {
  StatComponent(Map<String, num> stats) : stats = Map.unmodifiable(stats);

  final Map<String, num> stats;
}
