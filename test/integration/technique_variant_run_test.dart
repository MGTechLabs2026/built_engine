/// SP1 §17 / §18 — a real runGame drives the TechniqueVariant path end to
/// end: acquisition, instance-identity Tome placement, combat usage
/// attribution, and Almanac observation. No lifecycle mocking.
library;

import 'package:build_engine/almanac.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/game.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

/// Fights the first two cycles (seeding reward-pool discoveries so there
/// is something to train), then alternates training and combat every
/// other cycle for the rest of the run. Unlike
/// `test/support/policies.dart`'s `TrainAfterFirstCombatPolicy` (which
/// trains every cycle after the first and so never returns to combat once
/// training becomes available), this keeps *both* halves of the pipeline
/// live for the whole run: training cycles drive learning / mastery /
/// inspiration, and the combat cycles interleaved between them are what
/// let a placed `TechniqueVariant` actually act and accrue usage — Test 1
/// needs a real `ActionCompleted` sourced from a minted instance, not just
/// a technique sitting unused in the Tome.
class _TrainHard extends DefaultRunDecisionPolicy {
  var _c = 0;

  @override
  String chooseCombatOrTraining(List<String> candidates) {
    _c++;
    if (_c <= 2) return 'combat';
    if (_c.isOdd) {
      return candidates.contains('training') ? 'training' : 'combat';
    }
    return 'combat';
  }

  @override
  int chooseReward(List<RewardKind> candidates) {
    final i = candidates.indexOf(RewardKind.itemOrTechnique);
    return i == -1 ? 0 : i;
  }

  /// Prefers, in order: (1) an owned variant's own per-instance mastery
  /// (so a just-learned variant's `masteryLevel` climbs to
  /// `kMinMasteryToInspire` quickly instead of being left at 0 while
  /// training chases other base families); (2) a not-yet-learned base
  /// family (so there is always a fresh variant to place/use); (3)
  /// whatever `DefaultRunDecisionPolicy` would pick (item training).
  /// `TrainingStage.trainingCandidates`'s fixed order puts item targets
  /// first, so without this override a run can spend a long time
  /// training gear and never reach technique training at all.
  @override
  RunTrainingTarget chooseTrainingTarget(List<RunTrainingTarget> candidates) {
    for (final c in candidates) {
      if (c is TrainTechniqueTarget && c.variantInstanceId != null) return c;
    }
    for (final c in candidates) {
      if (c is TrainTechniqueTarget && c.variantInstanceId == null) return c;
    }
    return candidates.first;
  }
}

/// Scans seeds `start..start+count-1` for one whose `_TrainHard` run
/// publishes at least one `TechniqueVariantInspired` — mirrors the
/// seed-sweep convention `test/plugins/game/training_stage_variant_test.dart`
/// (Tasks 7-9) already established for a resolver whose discovery roll has
/// no other lever to pin deterministically.
int? _seedThatInspires({int start = 1, int count = 40}) {
  for (var seed = start; seed < start + count; seed++) {
    final events = EventBus();
    var hit = false;
    events.subscribe<TechniqueVariantInspired>((_) => hit = true);
    runGame(seed, policy: _TrainHard(), eventBus: events);
    if (hit) return seed;
  }
  return null;
}

void main() {
  test('combat action from a placed variant increments that variant\'s usage',
      () {
    // Observe TechniqueVariantMinted to learn instance ids; observe
    // ActionCompleted to see which instance acted; the run itself records
    // usage via CombatStage's existing bridge (combat_stage.dart:104-108).
    final events = EventBus();
    final minted = <TechniqueVariantMinted>[];
    final techniqueActions = <EntityId>[];
    events.subscribe<TechniqueVariantMinted>(minted.add);
    events.subscribe<ActionCompleted>((e) {
      final ref = e.action.sourceRef;
      if (ref != null &&
          ref.referenceType == techniqueReferenceType &&
          ref.instanceEntityId != null) {
        techniqueActions.add(ref.instanceEntityId!);
      }
    });

    // Seed 6 itself dies before ever training (no technique reaches the
    // Tome) — per the brief's own fallback instruction, swept 1..20 for
    // one where a technique is learned and used in combat before the run
    // ends; seed 9 is the first hit and is pinned here.
    final result = runGame(9, policy: _TrainHard(), eventBus: events);

    expect(result.techniquesLearned, isNotEmpty);
    // Once a variant is in the Tome, the run's fights produce technique
    // actions carrying that instance id.
    expect(techniqueActions, isNotEmpty);
    // Every acting instance id was one that was minted this run.
    final mintedIds = minted.map((m) => m.instanceId).toSet();
    expect(techniqueActions.every(mintedIds.contains), isTrue);
  });

  test('the Almanac records variant discovery, usage, and (when it happens) '
      'inspiration ancestry for a real run', () {
    // Prefer a seed that reliably inspires (the stronger, unconditional
    // assertion) — swept live here rather than pinned blind, mirroring
    // training_stage_variant_test.dart's `_seedThatInspires` convention.
    // Seed 25 is the first hit within the swept range (confirmed via a
    // standalone sweep of seeds 1..60 during development: seeds 25, 32
    // and 48 all inspire under this policy — kMinMasteryToInspire == 1
    // and kMinUsageToInspire == 3 are both easily reached organically
    // once `chooseTrainingTarget` keeps pushing a learned variant's own
    // mastery up). Falls back to seed 9 (and a conditional inspiration
    // assertion) only if the sweep somehow finds nothing.
    final inspiringSeed = _seedThatInspires() ?? 9;

    final recorder = AlmanacRecorder();
    final events = EventBus();
    final inspired = <TechniqueVariantInspired>[];
    events.subscribe<TechniqueVariantInspired>(inspired.add);

    runGame(inspiringSeed,
        policy: _TrainHard(),
        eventBus: events,
        almanac: recorder,
        runId: 'sp1-e2e',
        runNumber: 1);

    final state = recorder.state;

    // Discovery: at least one technique-instance discovery recorded, one
    // entry per technique-variant instance ever discovered/used.
    expect(state.techniques, isNotEmpty);
    for (final t in state.techniques) {
      expect(t.instanceId, isNotEmpty);
      expect(TechniqueIds.bases, contains(t.baseFamilyId));
    }

    // Usage: at least one variant with real recorded usage, whose
    // observations carry this run's id.
    final usedTechniques =
        state.techniques.where((t) => t.totalUsage > 0).toList();
    expect(usedTechniques, isNotEmpty);
    for (final t in usedTechniques) {
      expect(t.usageObservations, isNotEmpty);
      for (final u in t.usageObservations) {
        expect(u.runId, 'sp1-e2e');
      }
    }

    // Inspiration ancestry — asserted unconditionally when the swept seed
    // actually inspired; otherwise (fallback path only) conditional on the
    // observed event, per the task's guidance.
    if (inspired.isNotEmpty) {
      expect(state.inspirations, isNotEmpty);
      for (final ins in state.inspirations) {
        expect(ins.inspirerInstanceIds, isNotEmpty);
      }
    }

    // Queries expose it too.
    final queries = AlmanacQueries(state);
    expect(queries.getRunHistory().map((r) => r.runId), contains('sp1-e2e'));
  });
}
