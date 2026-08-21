import '../event/event_bus.dart';

/// Tallies how many times specific event types have been published.
/// Counting for a type only begins once [trackType] is called for it —
/// there is no retroactive counting.
class EventCounter {
  EventCounter(this._events);

  final EventBus _events;
  final Map<Type, int> _counts = {};

  /// Starts counting occurrences of [type]. A no-op if already tracking
  /// [type].
  void trackType(Type type) {
    if (_counts.containsKey(type)) return;
    _counts[type] = 0;
    _events.subscribeDynamic(
      type,
      (_) => _counts[type] = (_counts[type] ?? 0) + 1,
    );
  }

  /// How many times [type] has been published since [trackType] was
  /// called for it. `0` if [type] was never tracked.
  int countOfType(Type type) => _counts[type] ?? 0;
}
