import '../entity/entity_id.dart';
import '../query/queries.dart';
import 'modifier.dart';
import 'modifier_operation_parsing.dart';
import 'modifier_source.dart';

/// Builds one [Modifier] per entry of [rawModifiers] — each entry a
/// JSON-shaped map with `'stat'`/`'operation'`/`'value'` and an optional
/// `'condition'` (a bare tag name, gated via [HasTagQuery]). Extracted
/// once (`ARCHITECTURE_AUDIT.md`'s category-12 finding) after
/// MartialArts, Elemental, and Physique each independently reimplemented
/// this exact loop over their own `extra['modifiers']` list — the
/// resulting [Modifier]s are byte-for-byte identical to what each of
/// those three copies produced, index-sourced as
/// `'<domain>:<contentId>:<index>:<target.value>'`.
///
/// Core-generic: [domain]/[contentId]/[rawModifiers]/[target] are all
/// supplied by the caller: this function has no idea what a "martial
/// item," an "elemental item," or a "physique" is.
List<Modifier> modifiersFromRawList({
  required String domain,
  required String contentId,
  required List<Map<String, dynamic>> rawModifiers,
  required EntityId target,
}) =>
    [
      for (var i = 0; i < rawModifiers.length; i++)
        Modifier(
          source: ModifierSource('$domain:$contentId:$i:${target.value}'),
          target: target,
          stat: rawModifiers[i]['stat'] as String,
          operation: modifierOperationFromString(rawModifiers[i]['operation'] as String),
          value: rawModifiers[i]['value'] as num,
          condition: rawModifiers[i].containsKey('condition')
              ? HasTagQuery(rawModifiers[i]['condition'] as String)
              : null,
        ),
    ];
