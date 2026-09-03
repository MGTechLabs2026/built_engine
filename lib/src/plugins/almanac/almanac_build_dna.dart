import 'almanac_models.dart';

/// Computes a deterministic, RNG-free build-DNA signature.
///
/// [BuildDna.tokens] is a canonical, order-independent projection of a build's
/// defining ids (lineage, physique, sorted-unique technique families / item ids
/// / affix categories, then up to three dominant axis names). Their `|`-joined
/// form is hashed with FNV-1a (32-bit) into [BuildDna.signature], lowercase
/// 8-char hex. A derived projection only — never an identity or dedup key.
BuildDna buildDna({
  required String lineageId,
  required String physiqueId,
  required Iterable<String> techniqueFamilies,
  required Iterable<String> itemIds,
  required Iterable<String> affixCategories,
  required Iterable<Map<String, num>> axisProfiles,
}) {
  final List<String> tokens = <String>[
    lineageId.toUpperCase(),
    physiqueId.toUpperCase(),
    ..._sortedUniqueUpper(techniqueFamilies),
    ..._sortedUniqueUpper(itemIds),
    ..._sortedUniqueUpper(affixCategories),
    ..._topAxisTokens(axisProfiles),
  ];
  return BuildDna(tokens: tokens, signature: _fnv1a32Hex(tokens.join('|')));
}

/// Dedupes [values], sorts ascending, then upper-cases each entry.
List<String> _sortedUniqueUpper(Iterable<String> values) {
  final List<String> unique = values.toSet().toList()..sort();
  return <String>[for (final String v in unique) v.toUpperCase()];
}

/// Sums `value.abs()` per axis name across every map, orders names by
/// `(summed magnitude DESC, name ASC)`, keeps the first three, re-sorts those
/// `name ASC`, and upper-cases them.
List<String> _topAxisTokens(Iterable<Map<String, num>> axisProfiles) {
  final Map<String, num> summedAbs = <String, num>{};
  for (final Map<String, num> profile in axisProfiles) {
    profile.forEach((String name, num value) {
      summedAbs[name] = (summedAbs[name] ?? 0) + value.abs();
    });
  }
  final List<String> names =
      summedAbs.keys.toList()..sort((String a, String b) {
        final int byMagnitude = summedAbs[b]!.compareTo(summedAbs[a]!);
        return byMagnitude != 0 ? byMagnitude : a.compareTo(b);
      });
  final List<String> top = names.take(3).toList()..sort();
  return <String>[for (final String v in top) v.toUpperCase()];
}

/// FNV-1a 32-bit hash of [s] over its UTF-16 code units, as lowercase 8-char hex.
String _fnv1a32Hex(String s) {
  int hash = 0x811c9dc5;
  for (final int unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
