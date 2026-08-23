/// Thrown by [ResourcePool.consume] when the entity cannot afford the
/// requested amount. Mirrors `InvalidPlacementException`'s "operation
/// refused, nothing mutated" pattern — [ResourcePool.canAfford] never
/// throws, exactly like `Container.canPlace`.
class InsufficientResourceException implements Exception {
  const InsufficientResourceException(
    this.resource, {
    required this.requested,
    required this.available,
  });

  final String resource;
  final num requested;
  final num available;

  @override
  String toString() =>
      'InsufficientResourceException: requested $requested of '
      '"$resource", only $available available';
}
