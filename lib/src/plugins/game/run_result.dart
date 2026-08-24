import 'package:build_engine/build_engine.dart';

import 'decision_log.dart';

/// One recorded Tome state — captured after every rebuild, so
/// [RunResult.tomeHistory] shows the build's full evolution across the
/// run, not just its final shape.
class TomeSnapshot {
  const TomeSnapshot({required this.afterStep, required this.components});

  final String afterStep;
  final List<BuildComponentRef> components;
}

/// The outcome of one combat step. [turnsUsed] is the number of actions
/// executed (either side) before the battle ended — the "combat
/// duration" balance signal.
class EncounterOutcome {
  const EncounterOutcome({
    required this.name,
    required this.enemyId,
    required this.won,
    required this.playerHealthAfter,
    required this.turnsUsed,
  });

  final String name;
  final String enemyId;
  final bool won;
  final num playerHealthAfter;
  final int turnsUsed;
}

/// One training session's raw outcome — enough to compute "training
/// attempts" and "training performance" without re-deriving them from
/// the Tome history.
class TrainingRecord {
  const TrainingRecord({
    required this.subject,
    required this.attemptCount,
    required this.averageQuality,
    required this.gain,
  });

  final String subject;
  final int attemptCount;

  /// The mean of every scored `TrainingProfile` dimension across the
  /// session's attempts — the same quantity `trainingGain` scales up,
  /// kept here at its natural 0.0-1.0-ish scale for reporting.
  final double averageQuality;
  final num gain;
}

/// Everything `runGame` records, in one immutable snapshot — the
/// complete history of one run, sufficient on its own to build both the
/// Playtest Report and (across several of these) the multi-seed Balance
/// Signals.
class RunResult {
  const RunResult({
    required this.seed,
    required this.characterName,
    required this.runDuration,
    required this.decisionLog,
    required this.physiqueId,
    required this.martialTradition,
    required this.styleId,
    required this.tomeHistory,
    required this.itemsDiscovered,
    required this.itemsMastered,
    required this.itemsUnlocked,
    required this.techniquesLearned,
    required this.techniquesEvolved,
    required this.encounters,
    required this.rewardsGranted,
    required this.trainingRecords,
    required this.finalBuild,
    required this.won,
    required this.cyclesCompleted,
    this.firstRewardStep,
    this.firstItemMasteryStep,
    this.firstTechniqueEvolutionStep,
  });

  final int seed;

  /// Cosmetic only — has no effect on gameplay or determinism, purely
  /// for identifying whose run this was in a report.
  final String characterName;

  /// Wall-clock time `runGame` itself took to compute the whole run — an
  /// engineering measurement (how expensive is one simulated run), not a
  /// gameplay-pacing one; this is a headless prototype with no real time
  /// passing in it.
  final Duration runDuration;

  /// Every decision actually made during this run, in order — replay via
  /// `runGame(result.seed, policy: ReplayDecisionPolicy(result.decisionLog))`.
  final DecisionLog decisionLog;

  final String physiqueId;
  final String martialTradition;
  final String styleId;
  final List<TomeSnapshot> tomeHistory;
  final List<String> itemsDiscovered;

  /// Items that became usable specifically *through training* this run
  /// (crossed a real mastery requirement) — a subset of [itemsUnlocked],
  /// which also includes items usable immediately at 0 requirement.
  final List<String> itemsMastered;

  /// Every item that reached the USABLE state at any point this run,
  /// regardless of how (immediately at 0 requirement, or via training).
  final List<String> itemsUnlocked;
  final List<String> techniquesLearned;
  final List<String> techniquesEvolved;

  /// Every fight this run, across every completed cycle — up to 3 per
  /// cycle, in order fought.
  final List<EncounterOutcome> encounters;

  /// One entry per reward actually granted, e.g. `'slot:slot_3'`,
  /// `'upgrade_point'`, `'item:iron_sword'`, `'technique:basic_slash'`.
  final List<String> rewardsGranted;
  final List<TrainingRecord> trainingRecords;
  final List<BuildComponentRef> finalBuild;

  /// `true` if the run survived to the 200-cycle safety cap; `false` if
  /// the player died first. This is an endless-until-death run — the cap
  /// exists purely so the headless simulation can't loop forever, not as
  /// a game-design "win."
  final bool won;

  /// How many full combat-or-training cycles were completed before the
  /// run ended (death, or the safety cap) — the natural "how far did you
  /// get" score for an endless run.
  final int cyclesCompleted;

  /// The 0-based cycle index of the first reward/item-mastery/technique-
  /// evolution this run produced — `null` if it never happened. The
  /// "time to first X" balance signals.
  final int? firstRewardStep;
  final int? firstItemMasteryStep;
  final int? firstTechniqueEvolutionStep;
}
