import 'package:build_engine/build_engine.dart';

/// The three ways a "reward" choice can resolve, offered by name (not by
/// pre-computed content) — `game_run.dart` resolves whichever kind is
/// chosen: [unlockSlot] unlocks the next locked Tome slot in fixed order,
/// [itemOrTechnique] draws the next entry from the seeded reward pool,
/// [upgradePoint] banks one spendable upgrade point. `unlockSlot` is
/// omitted from the offered candidates once all 9 slots are unlocked.
enum RewardKind { unlockSlot, itemOrTechnique, upgradePoint }

/// Every meaningful choice a player makes across a run — the endless
/// combat/training loop's own minimum: martial tradition/style, combat
/// vs. training, reward, what to train, Tome arrangement, whether to
/// replace, how to spend a banked upgrade point. Plugins/callers
/// implement this directly, no registry — the same "implement directly"
/// pattern `Condition`/`Effect`/`ActionSelector`/`TargetSelector`/
/// `BuildActionInterpreter` already use throughout this engine. A future
/// UI is just another `RunDecisionPolicy` implementation.
///
/// Must be a pure/deterministic function of its arguments (no randomness,
/// no wall-clock) — `runGame(seed, policy: ...)` is only reproducible if
/// [policy] itself is, the same determinism contract `TrainingExercise`
/// already requires of its own `evaluate`.
abstract class RunDecisionPolicy {
  /// Picks the martial tradition from [candidates] (always
  /// `[MartialTraditions.western, MartialTraditions.eastern]`) — the
  /// first of the two-step style choice.
  String chooseMartialTradition(List<String> candidates);

  /// Picks the starting martial style from [candidates] — the chosen
  /// tradition's 3 styles (e.g. `[boxing, wrestling, fencing]` for
  /// western).
  String chooseStartingStyle(List<String> candidates);

  /// Picks combat or training for this loop cycle, from [candidates]
  /// (always `['combat', 'training']`).
  String chooseCombatOrTraining(List<String> candidates);

  /// Picks one of [candidates] — an index into a small, fixed list of
  /// [RewardKind]s (2 or 3 entries; `unlockSlot` omitted once all 9 Tome
  /// slots are unlocked).
  int chooseReward(List<RewardKind> candidates);

  /// Picks which subject to spend a training session on, from
  /// [candidates] — each entry an `item:<id>`/`technique:<id>` subject
  /// string (`itemSubject`/`techniqueSubject`), naming something already
  /// owned/discovered but not yet usable/learned.
  String chooseTrainingTarget(List<String> candidates);

  /// Picks which Tome slot [component] should occupy, from
  /// [candidateSlots] (already narrowed to the currently-unlocked slots,
  /// empty ones ordered first — any category fits any slot).
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots);

  /// Whether [incoming] should replace [current], already occupying
  /// [slot] — only ever asked when [slot] is occupied. `false` leaves
  /// [current] in place and discards [incoming]'s Tome placement (it
  /// stays owned/discovered/learned either way, just not active).
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming);

  /// Called once per banked upgrade point still available during a
  /// Manage Tome step, offering to spend it now or bank it for later.
  /// [candidates] is always `['stat:health', 'stat:attack', 'stat:speed',
  /// ...'item:&lt;id&gt;' for every owned item, ...'technique:&lt;id&gt;'
  /// for every known technique, 'skip']` — picking `'skip'` stops the
  /// spend loop for this visit, leaving any remaining points banked.
  String chooseUpgradeSpend(List<String> candidates);
}

/// The simplest possible deterministic policy — always the first option,
/// always replace. Lets `runGame(seed)` produce a complete run with zero
/// caller-supplied decisions; every method is trivially pure.
class DefaultRunDecisionPolicy implements RunDecisionPolicy {
  const DefaultRunDecisionPolicy();

  @override
  String chooseMartialTradition(List<String> candidates) => candidates.first;

  @override
  String chooseStartingStyle(List<String> candidates) => candidates.first;

  @override
  String chooseCombatOrTraining(List<String> candidates) => candidates.first;

  @override
  int chooseReward(List<RewardKind> candidates) => 0;

  @override
  String chooseTrainingTarget(List<String> candidates) => candidates.first;

  @override
  SlotId chooseSlot(BuildComponentRef component, List<SlotId> candidateSlots) => candidateSlots.first;

  @override
  bool chooseReplace(SlotId slot, BuildComponentRef current, BuildComponentRef incoming) => true;

  @override
  String chooseUpgradeSpend(List<String> candidates) => candidates.first;
}
