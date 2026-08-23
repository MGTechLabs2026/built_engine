import 'reward_candidate.dart';

/// A named table of weighted [RewardCandidate]s — reward *generation*, not
/// a specific loot table: this class represents the shape any reward
/// source (a chest, an enemy, a quest, a training opportunity, ...) uses,
/// never a particular game's content. There is no separate `LootTable`
/// class — this *is* the loot table the task's "LootTable / weighted
/// candidates" alternative already describes.
class RewardDefinition {
  const RewardDefinition({required this.id, required this.candidates});

  final String id;
  final List<RewardCandidate> candidates;
}
