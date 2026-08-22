/// Thrown by `Container.place`/`Container.move` when the placement would
/// violate one or more `PlacementRule`s. `canPlace` never throws this —
/// it only returns `bool`.
class InvalidPlacementException implements Exception {
  const InvalidPlacementException(this.failedRules);

  /// The runtime type names of every `PlacementRule` that rejected the
  /// placement.
  final List<String> failedRules;

  @override
  String toString() =>
      'InvalidPlacementException: failed rules: ${failedRules.join(', ')}';
}
