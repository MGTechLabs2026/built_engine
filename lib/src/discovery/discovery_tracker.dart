import '../component/component_store.dart';
import '../components/discovery_component.dart';
import '../entity/entity_id.dart';
import '../event/event_bus.dart';
import 'discovery_events.dart';
import 'discovery_state.dart';

/// The generic Discovery system — one tracker for every arbitrary content
/// subject a plugin cares about (item, technique, style, weapon, spell,
/// crafting recipe, ...), all tracked the same way through the same
/// `unknown` -> `discovered` -> `unlocked` progression. Core never
/// hardcodes what a subject means, and no per-domain system class exists.
///
/// [DiscoveryComponent] stays pure state (only `discovered`/`unlocked`
/// entries, keyed by subject id — a missing entry means `unknown`); this
/// tracker is what applies the state transitions and eventing
/// consistently. No randomness anywhere in this class, so discovery stays
/// deterministic without needing `RngService` at all.
class DiscoveryTracker {
  DiscoveryTracker({required ComponentStore components, required EventBus events})
      : _components = components,
        _events = events;

  final ComponentStore _components;
  final EventBus _events;

  /// [id]'s discovery state for [subject]. Missing [DiscoveryComponent] or
  /// missing entry reads as [DiscoveryState.unknown].
  DiscoveryState stateOf(EntityId id, String subject) =>
      _components.get<DiscoveryComponent>(id)?.states[subject] ??
      DiscoveryState.unknown;

  /// Moves [id]'s [subject] from `unknown` to `discovered`. A no-op — no
  /// mutation, no event — if [subject] is already `discovered` or
  /// `unlocked`; discovery never regresses.
  void discover(EntityId id, String subject) {
    if (stateOf(id, subject) != DiscoveryState.unknown) return;
    _setState(id, subject, DiscoveryState.discovered);
    _events.publish(SubjectDiscovered(id, subject));
  }

  /// Moves [id]'s [subject] to `unlocked`. If [subject] is still `unknown`,
  /// auto-promotes through `discovered` first (publishing
  /// [SubjectDiscovered] then [SubjectUnlocked]) — an entity can never end
  /// up `unlocked` without ever having been `discovered`. A no-op if
  /// [subject] is already `unlocked`.
  void unlock(EntityId id, String subject) {
    final current = stateOf(id, subject);
    if (current == DiscoveryState.unlocked) return;
    if (current == DiscoveryState.unknown) {
      _setState(id, subject, DiscoveryState.discovered);
      _events.publish(SubjectDiscovered(id, subject));
    }
    _setState(id, subject, DiscoveryState.unlocked);
    _events.publish(SubjectUnlocked(id, subject));
  }

  void _setState(EntityId id, String subject, DiscoveryState state) {
    final existing = _components.get<DiscoveryComponent>(id);
    final updated =
        Map<String, DiscoveryState>.of(existing?.states ?? const <String, DiscoveryState>{});
    updated[subject] = state;
    _components.add(id, DiscoveryComponent(updated));
  }
}
