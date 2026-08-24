import 'package:build_engine/build_engine.dart';

/// The three ways a "reward" choice can resolve, offered by name (not by
/// pre-computed content) — `game_run.dart` resolves whichever kind is
/// chosen: [unlockSlot] unlocks the next locked Tome slot in fixed order,
/// [itemOrTechnique] draws the next entry from the seeded reward pool,
/// [upgradePoint] banks one spendable upgrade point. `unlockSlot` is
/// omitted from the offered candidates once every Tome slot
/// (`RunTomeSlots.all`, a high fixed ceiling) is unlocked.
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

  /// Picks combat or training for this loop cycle, from [candidates] —
  /// always includes `'combat'`; `'training'` is included only if there is
  /// currently something trainable (an owned-but-not-usable item or a
  /// discovered-but-not-learned technique), so this never offers a choice
  /// that would silently do nothing.
  String chooseCombatOrTraining(List<String> candidates);

  /// Picks one of [candidates] — an index into a small, fixed list of
  /// [RewardKind]s (2 or 3 entries; `unlockSlot` omitted once every Tome
  /// slot is unlocked).
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

  /// Called repeatedly during Manage Tome (after upgrade-point spending),
  /// offering to equip something benched (owned/known but not currently
  /// in the Tome) or unequip something currently placed. [candidates] is
  /// `[...'equip:item:&lt;id&gt;' for every usable benched item,
  /// ...'equip:technique:&lt;id&gt;' for every benched known technique,
  /// 'done', ...'unequip:&lt;slotId&gt;:&lt;referenceType&gt;:&lt;contentId&gt;'
  /// for every currently-occupied slot]` — deliberately ordered with
  /// every `equip:` option before `'done'` and every `unequip:` option
  /// after it, so `DefaultRunDecisionPolicy`'s "always take the first
  /// option" always means "equip whatever's benched, never gratuitously
  /// unequip your own gear." An `equip:` choice reuses the same
  /// `chooseSlot`/`chooseReplace` flow a reward grant already uses;
  /// `unequip:` frees that slot without discarding ownership — the
  /// component goes back to being benched, not lost. This method isn't
  /// called at all if nothing is currently benched or placed (nothing
  /// to manage).
  String chooseTomeAction(List<String> candidates);
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

  @override
  String chooseTomeAction(List<String> candidates) => candidates.first;
}
