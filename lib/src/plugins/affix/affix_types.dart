/// An affix's affinity lean. Maps to physique tradition in the resolver:
/// `western → force` favoured, `eastern → flow` favoured; `neutral` is
/// always mid-weight.
enum AffixLean { neutral, force, flow }

/// Which reward domain an affix slot belongs to.
enum AffixDomain { item, technique }

/// The canonical `category` string stored on every affix definition and
/// carried into the Almanac. Not a tag — display / history data.
abstract final class AffixCategories {
  static const itemPrefix = 'item_prefix';
  static const itemSuffix = 'item_suffix';
  static const techniquePrefix = 'technique_prefix';
  static const techniqueSuffix = 'technique_suffix';
  static const all = [itemPrefix, itemSuffix, techniquePrefix, techniqueSuffix];
}

/// The `affix_pool:*` tags the resolver enumerates. `category` and the
/// pool tag's suffix are deliberately the same four strings.
abstract final class AffixPoolTags {
  static const itemPrefix = 'affix_pool:item_prefix';
  static const itemSuffix = 'affix_pool:item_suffix';
  static const techniquePrefix = 'affix_pool:technique_prefix';
  static const techniqueSuffix = 'affix_pool:technique_suffix';

  static String forSlot(AffixDomain domain, String slotKind) =>
      'affix_pool:${domain == AffixDomain.item ? 'item' : 'technique'}_$slotKind';
}
