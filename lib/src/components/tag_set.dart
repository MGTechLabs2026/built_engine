/// An entity's tags — a generic, engine-agnostic label set. The engine
/// never interprets tag values; it only stores and matches them.
class TagSet {
  TagSet(Set<String> tags) : tags = Set.unmodifiable(tags);

  final Set<String> tags;
}
