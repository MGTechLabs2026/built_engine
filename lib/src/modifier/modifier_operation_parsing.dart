import 'modifier.dart';

/// Parses a content-authored operation name (`'add'`/`'multiply'`/
/// `'override'`/`'min'`/`'max'`) into a [ModifierOperation] — extracted
/// once (`ARCHITECTURE_AUDIT.md`'s category-12 finding) after
/// MartialArts, Elemental, and Physique each independently declared the
/// identical private `_operationFor` switch. Throws [ArgumentError] for
/// an unrecognized name, matching every prior copy's behavior exactly.
ModifierOperation modifierOperationFromString(String name) => switch (name) {
      'add' => ModifierOperation.add,
      'multiply' => ModifierOperation.multiply,
      'override' => ModifierOperation.override,
      'min' => ModifierOperation.min,
      'max' => ModifierOperation.max,
      _ => throw ArgumentError('unknown modifier operation: $name'),
    };
