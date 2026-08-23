import 'evolution_candidate.dart';

/// Named constants for four common tier labels — plain, generic
/// skill-progression vocabulary, not martial-arts terminology.
/// [EvolutionDefinition.tier] is a plain `String`, not an enum, and is
/// never consulted by any resolver logic — purely descriptive metadata
/// for whoever organizes content; a plugin may use any tier string it
/// likes, including ones not listed here.
abstract final class EvolutionTiers {
  static const basic = 'basic';
  static const intermediate = 'intermediate';
  static const advanced = 'advanced';
  static const master = 'master';
}

/// One node in a branching evolution tree (e.g. "Basic Punch"). Contains
/// no names/flavor of its own beyond an opaque [id] — those belong to
/// plugin content, never to Core.
class EvolutionDefinition {
  const EvolutionDefinition({
    required this.id,
    required this.tier,
    this.candidates = const [],
  });

  final String id;
  final String tier;

  /// The branches this definition could evolve into. Empty means this is
  /// a terminal node — `EvolutionResolver` no-ops for it, not an error.
  final List<EvolutionCandidate> candidates;
}
