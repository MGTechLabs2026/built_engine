import 'package:build_engine/build_engine.dart';

/// One recorded Tome state — captured after every rebuild, so
/// [RunResult.tomeHistory] shows the build's full evolution across the
/// run, not just its final shape.
class TomeSnapshot {
  const TomeSnapshot({required this.afterStep, required this.components});

  final String afterStep;
  final List<BuildComponentRef> components;
}

/// The outcome of one combat step.
class EncounterOutcome {
  const EncounterOutcome({
    required this.name,
    required this.enemyId,
    required this.won,
    required this.playerHealthAfter,
  });

  final String name;
  final String enemyId;
  final bool won;
  final num playerHealthAfter;
}

/// Everything the milestone asks `runGame` to record, in one immutable
/// snapshot — the complete history of one run.
class RunResult {
  const RunResult({
    required this.seed,
    required this.physiqueId,
    required this.styleId,
    required this.tomeHistory,
    required this.itemsDiscovered,
    required this.itemsMastered,
    required this.techniquesLearned,
    required this.techniquesEvolved,
    required this.encounters,
    required this.rewardsGranted,
    required this.finalBuild,
    required this.won,
  });

  final int seed;
  final String physiqueId;
  final String styleId;
  final List<TomeSnapshot> tomeHistory;
  final List<String> itemsDiscovered;
  final List<String> itemsMastered;
  final List<String> techniquesLearned;
  final List<String> techniquesEvolved;
  final List<EncounterOutcome> encounters;
  final List<String> rewardsGranted;
  final List<BuildComponentRef> finalBuild;
  final bool won;
}
