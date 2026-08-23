import '../component/component_store.dart';
import '../components/mastery_component.dart';
import '../entity/entity_id.dart';
import '../event/event_bus.dart';
import 'mastery_definition.dart';
import 'mastery_events.dart';
import 'mastery_record.dart';

/// The generic Mastery system — one tracker for every arbitrary mastery
/// subject a plugin cares about (item mastery, technique tier, style
/// mastery, a future crafting recipe, ...), all tracked the same way. Core
/// never hardcodes what a subject means, and no per-domain system class
/// (no `SwordMastery`, no `TechniqueMastery`) exists — a single
/// `MasteryTracker` instance serves every unrelated subject a game
/// registers, distinguished only by the subject id string each plugin
/// chooses for its own namespace.
///
/// [MasteryComponent] stays pure state (only accumulated progress, keyed
/// by subject id); this tracker is what gives a subject its level
/// thresholds (via [define]) and what applies level-crossing/eventing
/// consistently. A subject with no registered [MasteryDefinition]
/// accumulates progress freely but never reaches a level — the same
/// permissive-default convention `ResourcePool`/`ProgressionEngine` use
/// for an undefined resource/subject.
///
/// Deliberately independent of `ProgressionEngine`'s own storage — the two
/// systems are kept separately evolvable rather than sharing one engine
/// (see `ARCHITECTURE.md`'s Mastery section for the tradeoff). No
/// randomness anywhere in this class — every operation is pure
/// arithmetic, so mastery stays deterministic without needing
/// `RngService` at all.
class MasteryTracker {
  MasteryTracker({required ComponentStore components, required EventBus events})
      : _components = components,
        _events = events;

  final ComponentStore _components;
  final EventBus _events;
  final Map<String, MasteryDefinition> _definitions = {};

  /// Registers (or overwrites) [definition] as the level thresholds for
  /// its [MasteryDefinition.subject].
  void define(MasteryDefinition definition) {
    _definitions[definition.subject] = definition;
  }

  /// The registered [MasteryDefinition] for [subject], or `null` if none
  /// has been [define]d.
  MasteryDefinition? definitionOf(String subject) => _definitions[subject];

  /// [owner]'s accumulated progress for [subject]. Missing
  /// [MasteryComponent] or missing entry reads as `0`.
  num progressOf(EntityId owner, String subject) =>
      _components.get<MasteryComponent>(owner)?.progress[subject] ?? 0;

  /// The level [owner]'s current progress for [subject] reaches, per the
  /// registered [MasteryDefinition]'s thresholds — `0` if none is
  /// registered. Always computed, never stored.
  int levelOf(EntityId owner, String subject) {
    final definition = _definitions[subject];
    if (definition == null) return 0;
    final progress = progressOf(owner, subject);
    var level = 0;
    for (final threshold in definition.thresholds) {
      if (progress < threshold) break;
      level += 1;
    }
    return level;
  }

  /// [owner]'s full mastery record for [subject] — owner, subject, level,
  /// and progress together.
  MasteryRecord recordOf(EntityId owner, String subject) => MasteryRecord(
        owner: owner,
        subject: subject,
        level: levelOf(owner, subject),
        progress: progressOf(owner, subject),
      );

  /// Adds [amount] (may be negative) to [owner]'s progress for [subject],
  /// floored at `0`. Publishes [MasteryChanged] with the actual delta
  /// applied — not at all if flooring leaves the stored value unchanged —
  /// then one [MasteryLevelReached] per level newly crossed, in ascending
  /// order.
  void increase(EntityId owner, String subject, num amount) {
    final oldLevel = levelOf(owner, subject);
    final oldProgress = progressOf(owner, subject);
    final raw = oldProgress + amount;
    final newProgress = raw < 0 ? 0 : raw;
    if (newProgress == oldProgress) return;
    final existing = _components.get<MasteryComponent>(owner);
    final updated = Map<String, num>.of(existing?.progress ?? const <String, num>{});
    updated[subject] = newProgress;
    _components.add(owner, MasteryComponent(updated));
    _events.publish(
      MasteryChanged(owner, subject, newProgress - oldProgress, newProgress),
    );
    final newLevel = levelOf(owner, subject);
    for (var level = oldLevel + 1; level <= newLevel; level++) {
      _events.publish(MasteryLevelReached(owner, subject, level));
    }
  }
}
