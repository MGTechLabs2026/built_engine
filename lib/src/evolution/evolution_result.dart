import 'evolution_candidate.dart';

/// The outcome of one `EvolutionResolver.resolve` call — pure data, no
/// decision beyond "which candidate, if any, was chosen." Applying the
/// result (updating a Mastery/Progression record, unlocking content, ...)
/// is deliberately left to whatever calls the resolver.
class EvolutionResult {
  const EvolutionResult({
    required this.fromId,
    required this.chosenCandidate,
    required this.eligibleCandidates,
  });

  final String fromId;

  /// `null` means evolution failed/no-op'd — either [fromId] had no
  /// candidates at all, or none of its candidates' conditions passed.
  final EvolutionCandidate? chosenCandidate;

  /// Every candidate whose conditions passed, before weighted selection —
  /// kept for auditability even when [chosenCandidate] is non-null.
  final List<EvolutionCandidate> eligibleCandidates;

  bool get evolved => chosenCandidate != null;
}
