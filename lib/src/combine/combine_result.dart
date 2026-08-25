// lib/src/combine/combine_result.dart
import 'combine_outcome.dart';

/// The outcome of one [CombineResolver.resolve] call — pure data, no
/// side effects of its own. [survivorIndex] is an index into the
/// caller's own input list (whichever position [RngService] happened to
/// pick, for determinism/audit — the inputs are interchangeable, so it
/// never matters *which* index wins). [chosenBranchTargetId] is set only
/// when [outcome] is [CombineOutcome.branchUpgrade].
class CombineResult {
  const CombineResult({
    required this.outcome,
    required this.survivorIndex,
    this.chosenBranchTargetId,
  });

  final CombineOutcome outcome;
  final int survivorIndex;
  final String? chosenBranchTargetId;
}
