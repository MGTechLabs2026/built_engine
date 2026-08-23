import '../component/component_store.dart';
import '../entity/entity_id.dart';
import '../event/event_bus.dart';
import '../mastery/mastery_definition.dart';
import '../mastery/mastery_tracker.dart';
import 'progression_definition.dart';
import 'progression_events.dart';
import 'progression_state.dart';

/// The generic Progression layer — one engine for every arbitrary
/// progression subject a plugin cares about (item mastery, technique
/// learning, technique tier, a future cultivation breakthrough, ...), all
/// tracked the same way. Core never hardcodes what a subject means.
///
/// Reads and writes through a [MasteryTracker] rather than owning its own
/// storage — Mastery is the authoritative engine; Progression is a thin
/// adapter preserving its own event vocabulary
/// ([ProgressionChanged]/[ProgressionTierReached]) and `tier`/`experience`
/// naming on top of Mastery's `level`/`progress`. This is a deliberate
/// choice (see `ARCHITECTURE.md`'s Mastery section): the two systems share
/// one store rather than each keeping independent state that could drift.
///
/// A subject with no registered [ProgressionDefinition] (really, no
/// registered `MasteryDefinition` — `define` forwards to
/// `MasteryTracker.define`) accumulates experience freely but never
/// reaches a tier — the same permissive-default convention `ResourcePool`
/// uses for an undefined resource.
///
/// No randomness anywhere in this class — every operation is pure
/// arithmetic, so progression stays deterministic without needing
/// `RngService` at all.
class ProgressionEngine {
  ProgressionEngine({
    required ComponentStore components,
    required EventBus events,
    MasteryTracker? mastery,
  })  : _mastery = mastery ?? MasteryTracker(components: components, events: events),
        _events = events;

  final MasteryTracker _mastery;
  final EventBus _events;

  /// Registers (or overwrites) [definition] as the tier thresholds for its
  /// [ProgressionDefinition.subject] — forwards to the shared
  /// [MasteryTracker.define].
  void define(ProgressionDefinition definition) {
    _mastery.define(
      MasteryDefinition(subject: definition.subject, thresholds: definition.thresholds),
    );
  }

  /// The registered [ProgressionDefinition] for [subject], projected from
  /// the shared `MasteryTracker`'s registered `MasteryDefinition` — `null`
  /// if none has been [define]d.
  ProgressionDefinition? definitionOf(String subject) {
    final definition = _mastery.definitionOf(subject);
    if (definition == null) return null;
    return ProgressionDefinition(
      subject: definition.subject,
      thresholds: definition.thresholds,
    );
  }

  /// [id]'s accumulated experience for [subject] — reads through
  /// `MasteryTracker.progressOf`. Missing entry reads as `0`.
  num experienceOf(EntityId id, String subject) => _mastery.progressOf(id, subject);

  /// The tier [id]'s current experience for [subject] reaches — reads
  /// through `MasteryTracker.levelOf`. `0` if no definition is registered.
  /// Always computed, never stored, so it can't desync from the
  /// experience it's based on.
  int tierOf(EntityId id, String subject) => _mastery.levelOf(id, subject);

  /// [id]'s experience and tier for [subject], together.
  ProgressionState stateOf(EntityId id, String subject) => ProgressionState(
        experience: experienceOf(id, subject),
        tier: tierOf(id, subject),
      );

  /// Adds [amount] (may be negative) to [id]'s experience for [subject],
  /// via the shared `MasteryTracker.increase` (floored at `0`, publishing
  /// `MasteryChanged`/`MasteryLevelReached`). Additionally publishes
  /// [ProgressionChanged] with the actual delta applied — not at all if
  /// flooring leaves the stored value unchanged — then one
  /// [ProgressionTierReached] per tier newly crossed, in ascending order,
  /// preserving Progression's own event vocabulary alongside Mastery's.
  void addExperience(EntityId id, String subject, num amount) {
    final oldTier = tierOf(id, subject);
    final oldExperience = experienceOf(id, subject);
    _mastery.increase(id, subject, amount);
    final newExperience = experienceOf(id, subject);
    if (newExperience == oldExperience) return;
    _events.publish(
      ProgressionChanged(id, subject, newExperience - oldExperience, newExperience),
    );
    final newTier = tierOf(id, subject);
    for (var tier = oldTier + 1; tier <= newTier; tier++) {
      _events.publish(ProgressionTierReached(id, subject, tier));
    }
  }

  /// Sets [id]'s experience for [subject] to at least [tier]'s threshold —
  /// covers "learning" a subject outright (`tier: 1`) without the caller
  /// doing threshold math. Never regresses progress already beyond that
  /// tier. Throws [ArgumentError] if [tier] is below `1` or beyond
  /// [subject]'s registered thresholds.
  void unlock(EntityId id, String subject, int tier) {
    if (tier < 1) {
      throw ArgumentError.value(tier, 'tier', 'must be at least 1');
    }
    final definition = _mastery.definitionOf(subject);
    if (definition == null || tier > definition.thresholds.length) {
      throw ArgumentError.value(
        tier,
        'tier',
        'no threshold registered for tier $tier of "$subject"',
      );
    }
    final required = definition.thresholds[tier - 1];
    final current = experienceOf(id, subject);
    if (current >= required) return;
    addExperience(id, subject, required - current);
  }
}
