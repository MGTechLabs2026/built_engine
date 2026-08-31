import 'package:build_engine/build_engine.dart';

import 'run_decision_policy.dart';

/// **Run-scoped telemetry events** published through `context.events` —
/// the same `EventBus` instance the rest of the engine already uses
/// ("use existing EventBus where possible, do not introduce a parallel
/// event architecture"). Every type here describes *a run doing
/// something* (a cycle started, an encounter resolved, a training
/// session recorded); each is meaningless outside a `runGame` call and
/// so belongs to this composition layer.
///
/// Domain *facts* that outlive a run — e.g. `TechniqueEvolved`, a
/// lineage relationship between two technique ids — do **not** live here;
/// they belong to their plugin's public surface (`technique_events.dart`)
/// and are merely *published* by the run when they occur.
///
/// Several telemetry points already have a generic
/// Core/Combat/Discovery/Mastery/Progression event that fires naturally
/// as `game_run.dart` calls into the existing plugins — no duplicate
/// event is published for those, a telemetry consumer just subscribes to
/// the existing type:
///
/// | Telemetry point | Event | Source |
/// |---|---|---|
/// | Run started | [RunStarted] | new (this file) |
/// | Physique selected | `PhysiqueAssigned` | existing (Physique plugin) |
/// | Starting Tome / Tome changed | [TomeChanged] | new — every rebuild, starting kit included |
/// | Cycle started | [CycleStarted] | new |
/// | Encounter started | [EncounterStarted] | new |
/// | Encounter result | [EncounterResolved] | new |
/// | Reward offered | [RewardOffered] | new |
/// | Reward selected | [RewardSelected] | new |
/// | Slot unlocked | [SlotUnlocked] | new |
/// | Upgrade point spent | [UpgradePointSpent] | new |
/// | Status snapshot (health/slots/inventory) | [RunStatus] | new — published once per cycle |
/// | Item discovered | `SubjectDiscovered` (subject `item:<id>`) | existing (Discovery) |
/// | Item mastery changed | `MasteryChanged` (subject `item:<id>`) | existing (Mastery) |
/// | Technique discovered | `SubjectDiscovered` (subject `technique:<id>`) | existing (Discovery) |
/// | Technique learned | `ProgressionTierReached` (subject `technique:<id>:knowledge`, tier 1) | existing (Progression) |
/// | Training started | [TrainingStarted] | new |
/// | Training result | [TrainingResultRecorded] | new |
/// | Technique evolved | `TechniqueEvolved` | existing (Technique plugin — `technique_events.dart`); published here by [TrainingStage] |
/// | Build resolved | [ActiveBuildResolved] | new |
/// | Combat action selected | `ActionStarted` | existing (Combat) |
/// | Combat result | `BattleWon`/`BattleLost` | existing (Combat) |
/// | Run ended | [RunEnded] | new |

class RunStarted {
  const RunStarted({required this.seed, required this.characterName});
  final int seed;
  final String characterName;
}

class RunEnded {
  const RunEnded({required this.won, required this.encounterCount});
  final bool won;
  final int encounterCount;
}

class CycleStarted {
  const CycleStarted(this.cycleNumber);
  final int cycleNumber;
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
  final List<RewardKind> candidates;
}

class RewardSelected {
  const RewardSelected(this.chosen);
  final RewardKind chosen;
}

class SlotUnlocked {
  const SlotUnlocked(this.slot);
  final SlotId slot;
}

class UpgradePointSpent {
  const UpgradePointSpent({required this.target, required this.amount});

  /// The chosen `chooseUpgradeSpend` candidate string, e.g.
  /// `'stat:attack'`/`'item:knife'`/`'technique:basic_slash'`.
  final String target;
  final num amount;
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

/// Fires for every Tome rebuild, the starting Tome included.
class TomeChanged {
  const TomeChanged({required this.stepName, required this.components});
  final String stepName;
  final List<BuildComponentRef> components;
}

class ActiveBuildResolved {
  const ActiveBuildResolved(this.components);
  final List<BuildComponentRef> components;
}

/// One Tome slot's status — whether it's unlocked yet, and what (if
/// anything) currently occupies it. `occupant` is `null` for an empty
/// unlocked slot; a locked slot is always also empty.
/// One currently-*unlocked* Tome slot's occupancy — `occupant` is `null`
/// for an empty slot. Locked slots aren't represented at all (the Tome's
/// total slot ceiling is a large fixed number, not worth enumerating —
/// see [RunStatus.totalSlotCapacity]).
typedef SlotStatus = ({SlotId slot, BuildComponentRef? occupant});

/// A full status snapshot — health, banked upgrade points, every
/// currently-unlocked Tome slot's occupancy, and the player's full
/// inventory (owned items and known techniques, including ones not
/// currently placed). Published once per cycle (right after
/// [CycleStarted]) so a human/LLM playing interactively has everything
/// needed to make the next decision without having to reconstruct it
/// from earlier events.
class RunStatus {
  const RunStatus({
    required this.health,
    required this.maxHealth,
    required this.initiative,
    required this.upgradePoints,
    required this.slots,
    required this.totalSlotCapacity,
    required this.ownedItemIds,
    required this.knownTechniqueIds,
  });

  final num health;
  final num maxHealth;
  final num initiative;
  final num upgradePoints;

  /// Only the currently-unlocked slots, in order.
  final List<SlotStatus> slots;

  /// The Tome's total slot ceiling (`RunTomeSlots.all.length`) — for
  /// context on how much room `slots.length` represents against, without
  /// enumerating locked slots individually.
  final int totalSlotCapacity;
  final List<String> ownedItemIds;
  final List<String> knownTechniqueIds;
}
