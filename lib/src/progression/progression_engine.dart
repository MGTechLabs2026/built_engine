import '../component/component_store.dart';
import '../components/progression_component.dart';
import '../entity/entity_id.dart';
import '../event/event_bus.dart';
import 'progression_definition.dart';
import 'progression_events.dart';
import 'progression_state.dart';

/// The generic Progression layer — one engine for every arbitrary
/// progression subject a plugin cares about (item mastery, technique
/// learning, technique tier, a future cultivation breakthrough, ...), all
/// tracked the same way. Core never hardcodes what a subject means.
///
/// [ProgressionComponent] stays pure state (only accumulated experience,
/// keyed by subject id); this service is what gives a subject its tier
/// thresholds (via [define]) and what applies tier-crossing/eventing
/// consistently. A subject with no registered [ProgressionDefinition]
/// accumulates experience freely but never reaches a tier — the same
/// permissive-default convention `ResourcePool` uses for an undefined
/// resource.
///
/// No randomness anywhere in this class — every operation is pure
/// arithmetic, so progression stays deterministic without needing
/// `RngService` at all.
class ProgressionEngine {
  ProgressionEngine({required ComponentStore components, required EventBus events})
      : _components = components,
        _events = events;

  final ComponentStore _components;
  final EventBus _events;
  final Map<String, ProgressionDefinition> _definitions = {};

  /// Registers (or overwrites) [definition] as the tier thresholds for its
  /// [ProgressionDefinition.subject].
  void define(ProgressionDefinition definition) {
    _definitions[definition.subject] = definition;
  }

  /// The registered [ProgressionDefinition] for [subject], or `null` if
  /// none has been [define]d.
  ProgressionDefinition? definitionOf(String subject) => _definitions[subject];

  /// [id]'s accumulated experience for [subject]. Missing
  /// [ProgressionComponent] or missing entry reads as `0`.
  num experienceOf(EntityId id, String subject) =>
      _components.get<ProgressionComponent>(id)?.experience[subject] ?? 0;

  /// The tier [id]'s current experience for [subject] reaches, per the
  /// registered [ProgressionDefinition]'s thresholds — `0` if none is
  /// registered. Always computed, never stored, so it can't desync from
  /// the experience it's based on.
  int tierOf(EntityId id, String subject) {
    final definition = _definitions[subject];
    if (definition == null) return 0;
    final experience = experienceOf(id, subject);
    var tier = 0;
    for (final threshold in definition.thresholds) {
      if (experience < threshold) break;
      tier += 1;
    }
    return tier;
  }

  /// [id]'s experience and tier for [subject], together.
  ProgressionState stateOf(EntityId id, String subject) => ProgressionState(
        experience: experienceOf(id, subject),
        tier: tierOf(id, subject),
      );

  /// Adds [amount] (may be negative) to [id]'s experience for [subject],
  /// floored at `0`. Publishes [ProgressionChanged] with the actual delta
  /// applied — not at all if flooring leaves the stored value unchanged —
  /// then one [ProgressionTierReached] per tier newly crossed, in
  /// ascending order.
  void addExperience(EntityId id, String subject, num amount) {
    final oldTier = tierOf(id, subject);
    final oldExperience = experienceOf(id, subject);
    final raw = oldExperience + amount;
    final newExperience = raw < 0 ? 0 : raw;
    if (newExperience == oldExperience) return;
    final existing = _components.get<ProgressionComponent>(id);
    final updated = Map<String, num>.of(existing?.experience ?? const <String, num>{});
    updated[subject] = newExperience;
    _components.add(id, ProgressionComponent(updated));
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
    final definition = _definitions[subject];
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
