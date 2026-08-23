/// An entity's elemental affinities — how strongly attuned it is to each
/// element it has been attuned to (see `attuneToElement`). Plain state,
/// no gameplay logic, matching every other component in this engine.
class ElementalAffinityComponent {
  const ElementalAffinityComponent(this.affinities);

  /// Element id (see `Elements`) -> affinity level.
  final Map<String, num> affinities;
}
