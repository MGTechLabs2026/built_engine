import '../entity/entity_id.dart';
import 'modifier.dart';
import 'modifier_source.dart';

/// Builds one unconditional `add` [Modifier] per entry of [properties] —
/// extracted once (`ARCHITECTURE_AUDIT.md`'s category-12 finding) after
/// the Item and Technique plugins each independently reimplemented this
/// exact loop over their own `extra['properties']` map. Sourced as
/// `'<domain>:<contentId>:<propertyKey>:<target.value>'`, byte-for-byte
/// identical to what each of those two copies produced.
///
/// Core-generic: [domain]/[contentId]/[properties]/[target] are all
/// supplied by the caller — this function has no idea what an "item" or
/// a "technique" is.
List<Modifier> modifiersFromProperties({
  required String domain,
  required String contentId,
  required Map<String, num> properties,
  required EntityId target,
}) =>
    [
      for (final entry in properties.entries)
        Modifier(
          source: ModifierSource('$domain:$contentId:${entry.key}:${target.value}'),
          target: target,
          stat: entry.key,
          operation: ModifierOperation.add,
          value: entry.value,
        ),
    ];
