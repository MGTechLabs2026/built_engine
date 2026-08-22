import '../component/component_store.dart';
import '../entity/entity_id.dart';
import '../query/query.dart';
import 'modifier.dart';
import 'modifier_source.dart';

class _ModifierEntry {
  _ModifierEntry(this.modifier) : remainingDuration = modifier.duration;

  final Modifier modifier;
  int? remainingDuration;
}

/// The repository of all registered [Modifier]s, across every entity and
/// stat. Not per-entity — [Modifier] already carries its own `target`.
class ModifierCollection {
  final List<_ModifierEntry> _entries = [];

  /// Registers [modifier]. Its `duration` (if any) starts counting down
  /// from the next [tick] call.
  void add(Modifier modifier) {
    _entries.add(_ModifierEntry(modifier));
  }

  /// Removes every modifier whose `source` equals [source].
  void removeBySource(ModifierSource source) {
    _entries.removeWhere((entry) => entry.modifier.source == source);
  }

  /// Modifiers currently applicable to [target]'s [stat]: matching
  /// target+stat, not yet expired, and whose `condition` (if any) currently
  /// matches via [components]. Returned in registration order — the order
  /// `ModifierResolver` relies on for deterministic tie-breaking.
  Iterable<Modifier> activeModifiersFor(
    EntityId target,
    String stat,
    ComponentStore components,
  ) {
    final scope = QueryScope(components: components);
    return _entries
        .where((entry) {
          final modifier = entry.modifier;
          if (modifier.target != target || modifier.stat != stat) {
            return false;
          }
          final remaining = entry.remainingDuration;
          if (remaining != null && remaining <= 0) {
            return false;
          }
          final condition = modifier.condition;
          if (condition != null && !condition.matches(target, scope)) {
            return false;
          }
          return true;
        })
        .map((entry) => entry.modifier);
  }

  /// Decrements every timed modifier's remaining duration by 1, removing
  /// any that reach 0. Permanent modifiers (`duration == null`) are
  /// untouched. The only mechanism for expiring temporary modifiers — no
  /// Scheduler, no event; a future Scheduler pass calls this, and for now
  /// callers (including tests) call it directly.
  void tick() {
    for (final entry in _entries) {
      final remaining = entry.remainingDuration;
      if (remaining != null) {
        entry.remainingDuration = remaining - 1;
      }
    }
    _entries.removeWhere((entry) {
      final remaining = entry.remainingDuration;
      return remaining != null && remaining <= 0;
    });
  }
}
