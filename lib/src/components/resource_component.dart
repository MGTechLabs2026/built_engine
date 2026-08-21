/// An entity's named numeric resource pools (e.g. a content plugin's own
/// "stamina" or "focus"). The engine never hardcodes a resource name.
class ResourceComponent {
  ResourceComponent(Map<String, num> resources)
      : resources = Map.unmodifiable(resources);

  final Map<String, num> resources;
}
