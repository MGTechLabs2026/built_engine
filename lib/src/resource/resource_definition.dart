/// Generic bounds for one named resource type (e.g. a content plugin's own
/// "stamina" or "focus"). The engine never hardcodes a resource name.
///
/// Not stored per-entity — [ResourceComponent] keeps storing only current
/// values. Registering a definition with [ResourcePool.define] is what
/// gives a resource an upper bound; an entity's actual current value still
/// lives in its own [ResourceComponent].
class ResourceDefinition {
  const ResourceDefinition({required this.id, this.min = 0, required this.max});

  final String id;
  final num min;
  final num max;
}
