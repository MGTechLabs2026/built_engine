import '../entity/entity_id.dart';

/// Published via the owning [EventBus] whenever [ResourcePool] actually
/// changes a stored resource value. Not published when a clamped
/// set/add/subtract would leave the value unchanged (e.g. adding to a
/// resource already at its maximum).
class ResourceChanged {
  const ResourceChanged(this.id, this.resource, this.delta, this.newCurrent);

  final EntityId id;
  final String resource;

  /// The actual change applied, after clamping — may differ from the
  /// amount requested (e.g. requesting +70 against a resource 30 below its
  /// maximum yields a [delta] of +30).
  final num delta;
  final num newCurrent;
}
