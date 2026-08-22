import 'dart:math' as math;

import 'modifier.dart';

/// Computes a stat's derived value from a base value plus a set of
/// modifiers, via a fixed, deterministic pipeline:
///
/// ```
/// base -> ADD (sum) -> MULTIPLY (product) -> OVERRIDE (highest priority
/// wins) -> MIN (ceiling) -> MAX (floor) -> final value
/// ```
///
/// This macro order is always fixed regardless of any modifier's
/// [Modifier.priority] — priority only orders modifiers within their own
/// operation group. Ties (equal priority, same operation) break by each
/// modifier's position in the `modifiers` iterable passed in — callers
/// (typically `ModifierCollection.activeModifiersFor`) are responsible for
/// providing a stable, meaningful order.
class ModifierResolver {
  const ModifierResolver();

  /// Applies every modifier in [modifiers] to [base], following the fixed
  /// pipeline above. Does not filter by target/stat/condition/expiry —
  /// callers pass in an already-filtered set (see `ModifierCollection`).
  num resolve(num base, Iterable<Modifier> modifiers) {
    final all = modifiers.toList(growable: false);
    var value = base;

    for (final modifier
        in _stableSortByPriority(all.where((m) => m.operation == ModifierOperation.add))) {
      value += modifier.value;
    }

    for (final modifier in _stableSortByPriority(
        all.where((m) => m.operation == ModifierOperation.multiply))) {
      value *= modifier.value;
    }

    for (final modifier in _stableSortByPriority(
        all.where((m) => m.operation == ModifierOperation.override))) {
      value = modifier.value;
    }

    for (final modifier
        in _stableSortByPriority(all.where((m) => m.operation == ModifierOperation.min))) {
      value = math.min(value, modifier.value);
    }

    for (final modifier
        in _stableSortByPriority(all.where((m) => m.operation == ModifierOperation.max))) {
      value = math.max(value, modifier.value);
    }

    return value;
  }

  /// Sorts by ascending [Modifier.priority], breaking ties by each
  /// modifier's original position in [modifiers] — a manual stable sort,
  /// since `List.sort` does not guarantee stability.
  List<Modifier> _stableSortByPriority(Iterable<Modifier> modifiers) {
    final indexed = modifiers.toList(growable: false).asMap().entries.toList();
    indexed.sort((a, b) {
      final priorityCompare = a.value.priority.compareTo(b.value.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }
}
