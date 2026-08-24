import 'package:build_engine/build_engine.dart';

/// Every meaningful choice a player makes between encounters — the
/// milestone's own minimum: reward, what to train, Tome arrangement,
/// whether to replace. Plugins/callers implement this directly, no
/// registry — the same "implement directly" pattern
/// `Condition`/`Effect`/`ActionSelector`/`TargetSelector`/
/// `BuildActionInterpreter` already use throughout this engine. A future
/// UI is just another `RunDecisionPolicy` implementation.
///
/// Must be a pure/deterministic function of its arguments (no randomness,
/// no wall-clock) — `runGame(seed, policy: ...)` is only reproducible if
/// [policy] itself is, the same determinism contract `TrainingExercise`
/// already requires of its own `evaluate`.
abstract class RunDecisionPolicy {
  /// Picks the starting martial style from [candidates] (always
  /// `[MartialStyles.boxing, MartialStyles.shaolin, MartialStyles.taiChi]`
  /// in this run).
  String chooseStartingStyle(List<String> candidates);

  /// Picks one of [candidates] (a small reward offer, 1-2 entries) to
  /// grant this encounter — an index into [candidates].
  int chooseReward(List<BuildComponentRef> candidates);

  /// Picks which subject to spend a Training Opportunity on, from
  /// [candidates] — each entry an `item:<id>`/`technique:<id>` subject
  /// string (`itemSubject`/`techniqueSubject`), naming something already
  /// owned/discovered but not yet usable/learned.
  String chooseTrainingTarget(List<String> candidates);

  /// Picks which Tome slot [component] should occupy, from
  /// [candidateSlots] (already narrowed to the slots valid for
  /// [component]'s own category/type, empty slots ordered first).
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots);

  /// Whether [incoming] should replace [current], already occupying
  /// [slot] — only ever asked when [slot] is occupied. `false` leaves
  /// [current] in place and discards [incoming]'s Tome placement (it
  /// stays owned/discovered/learned either way, just not active).
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming);
}

/// The simplest possible deterministic policy — always the first option,
/// always replace. Lets `runGame(seed)` produce a complete run with zero
/// caller-supplied decisions; every method is trivially pure.
class DefaultRunDecisionPolicy implements RunDecisionPolicy {
  const DefaultRunDecisionPolicy();

  @override
  String chooseStartingStyle(List<String> candidates) => candidates.first;

  @override
  int chooseReward(List<BuildComponentRef> candidates) => 0;

  @override
  String chooseTrainingTarget(List<String> candidates) => candidates.first;

  @override
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots) => candidateSlots.first;

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) => true;
}
