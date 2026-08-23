import 'reward_candidate.dart';

/// The outcome of one `RewardResolver.resolve` call — pure data. Empty
/// [rewards] means no candidates were available to draw from (an empty
/// table, or every candidate had zero weight) or `rollCount` was `0`; not
/// an error.
class RewardResult {
  const RewardResult({required this.definitionId, required this.rewards});

  final String definitionId;
  final List<RewardCandidate> rewards;
}
