/// A read-model pairing an entity's current value for a resource with that
/// resource's registered maximum — computed on demand by [ResourcePool],
/// never itself stored. [ResourceComponent] holds only the current value.
class ResourceState {
  const ResourceState({required this.current, required this.max});

  final num current;
  final num max;
}
