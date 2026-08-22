import '../entity/entity_id.dart';
import '../query/query.dart';
import 'modifier_source.dart';

/// How a [Modifier] combines with a stat's base value. See
/// `ModifierResolver` for the full calculation pipeline and how each
/// operation behaves.
enum ModifierOperation { add, multiply, override, min, max }

/// A single stat adjustment. Fields match claude.md's MODIFIER SYSTEM
/// section: source, target, stat, operation, value, priority, duration,
/// condition.
///
/// Deliberately has no custom `==`/`hashCode`: identity equality is
/// sufficient since instances aren't looked up by value, only by `source`
/// (via `ModifierCollection.removeBySource`) or by `target`/`stat` (via
/// `activeModifiersFor`).
class Modifier {
  const Modifier({
    required this.source,
    required this.target,
    required this.stat,
    required this.operation,
    required this.value,
    this.priority = 0,
    this.duration,
    this.condition,
  });

  final ModifierSource source;
  final EntityId target;

  /// An arbitrary, engine-agnostic string key — e.g. "damage", "armor".
  /// The engine never interprets this value.
  final String stat;

  final ModifierOperation operation;
  final num value;

  /// Orders this modifier relative to others of the SAME [operation] only
  /// — it does not affect which operation group runs first; that order
  /// (add, then multiply, then override, then min, then max) is always
  /// fixed. See `ModifierResolver`.
  final int priority;

  /// Remaining lifetime in `ModifierCollection.tick()` calls. `null` means
  /// permanent. Set once at construction — `ModifierCollection` tracks the
  /// actual countdown separately, since this field stays immutable.
  final int? duration;

  /// If non-null, this modifier only applies while [condition] matches its
  /// [target] — re-evaluated every time it's queried, not cached.
  final Query? condition;
}
