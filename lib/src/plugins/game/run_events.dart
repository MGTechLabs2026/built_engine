import 'package:build_engine/build_engine.dart';

/// Every game event published through `context.events` — the same
/// `EventBus` instance the rest of the engine already uses (per the
/// milestone's "use existing EventBus where possible. Do not introduce a
/// parallel event architecture"). Only 10 of the 19 requested telemetry
/// points needed a genuinely new event type; the other 9 already have a
/// generic Core/Combat event that fires naturally as `game_run.dart`
/// calls into the existing plugins — no duplicate event is published for
/// those, a telemetry consumer just subscribes to the existing type:
///
/// | Telemetry point | Event | Source |
/// |---|---|---|
/// | Run started | [RunStarted] | new (this file) |
/// | Physique selected | `PhysiqueAssigned` | existing (Physique plugin) |
/// | Starting Tome | [TomeChanged] | new — first entry, same event as every later rebuild |
/// | Encounter started | [EncounterStarted] | new |
/// | Encounter result | [EncounterResolved] | new |
/// | Reward offered | [RewardOffered] | new |
/// | Reward selected | [RewardSelected] | new |
/// | Item discovered | `SubjectDiscovered` (subject `item:<id>`) | existing (Discovery) |
/// | Item mastery changed | `MasteryChanged` (subject `item:<id>`) | existing (Mastery) |
/// | Technique discovered | `SubjectDiscovered` (subject `technique:<id>`) | existing (Discovery) |
/// | Technique learned | `ProgressionTierReached` (subject `technique:<id>:knowledge`, tier 1) | existing (Progression) |
/// | Training started | [TrainingStarted] | new |
/// | Training result | [TrainingResultRecorded] | new |
/// | Technique evolved | [TechniqueEvolved] | new |
/// | Tome changed | [TomeChanged] | new |
/// | Build resolved | [ActiveBuildResolved] | new |
/// | Combat action selected | `ActionStarted` | existing (Combat) |
/// | Combat result | `BattleWon`/`BattleLost` | existing (Combat) |
/// | Run ended | [RunEnded] | new |

class RunStarted {
  const RunStarted(this.seed);
  final int seed;
}

class RunEnded {
  const RunEnded({required this.won, required this.encounterCount});
  final bool won;
  final int encounterCount;
}

class EncounterStarted {
  const EncounterStarted({required this.name, required this.enemyId});
  final String name;
  final String enemyId;
}

class EncounterResolved {
  const EncounterResolved({
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

class RewardOffered {
  const RewardOffered(this.candidates);
  final List<BuildComponentRef> candidates;
}

class RewardSelected {
  const RewardSelected(this.chosen);
  final BuildComponentRef chosen;
}

class TrainingStarted {
  const TrainingStarted(this.subject);
  final String subject;
}

class TrainingResultRecorded {
  const TrainingResultRecorded({required this.subject, required this.profile, required this.gain});
  final String subject;
  final TrainingProfile profile;
  final num gain;
}

class TechniqueEvolved {
  const TechniqueEvolved({required this.fromId, required this.toId});
  final String fromId;
  final String toId;
}

/// Fires for every Tome rebuild, the starting Tome included (its
/// [stepName] is `'Starting Tome (item)'`/`'Starting Tome (technique)'`).
class TomeChanged {
  const TomeChanged({required this.stepName, required this.components});
  final String stepName;
  final List<BuildComponentRef> components;
}

class ActiveBuildResolved {
  const ActiveBuildResolved(this.components);
  final List<BuildComponentRef> components;
}
