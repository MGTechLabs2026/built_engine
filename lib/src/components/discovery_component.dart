import '../discovery/discovery_state.dart';

/// An entity's discovery state for arbitrary named content subjects (e.g.
/// a content plugin's own "item:iron_sword" or "technique:jab"). The
/// engine never hardcodes a subject name.
///
/// Only ever holds `discovered`/`unlocked` entries — a missing entry
/// means `DiscoveryState.unknown`, never stored explicitly.
class DiscoveryComponent {
  DiscoveryComponent(Map<String, DiscoveryState> states)
      : states = Map.unmodifiable(states);

  final Map<String, DiscoveryState> states;
}
