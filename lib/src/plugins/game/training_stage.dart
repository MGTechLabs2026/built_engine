import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'decision_log.dart';
import 'run_content.dart';
import 'run_decision_policy.dart';
import 'run_events.dart';
import 'run_result.dart';
import 'tome_manager.dart';
import 'training_simulation.dart';

/// Owns `runGame`'s training resolution: which item/technique is due for
/// training, running one `TrainingSession`, and recording the result —
/// including the item-mastery and technique-learning/evolution side
/// effects that follow. Extracted from `runGame` (previously 2 nested
/// closures — see `ARCHITECTURE_AUDIT.md`'s god-function finding) so
/// this piece of the run is independently constructable. Delegates Tome
/// placement to the [TomeManager] it's given rather than reaching into
/// `runGame`'s shared closure scope directly.
class TrainingStage {
  TrainingStage({
    required this.character,
    required this.context,
    required this.recordingPolicy,
    required this.rng,
    required this.events,
    required this.tomeManager,
    required this.styleId,
  });

  final EntityId character;
  final PluginContext context;
  final RecordingDecisionPolicy recordingPolicy;
  final RngService rng;
  final EventBus events;
  final TomeManager tomeManager;
  final String styleId;

  final trainingRecords = <TrainingRecord>[];
  final itemsMastered = <String>[];
  final techniquesLearned = <String>[];
  final techniquesEvolved = <String>[];
  int? firstItemMasteryStep;
  int? firstTechniqueEvolutionStep;

  /// [ownedItemIds] is passed in rather than called as a free function
  /// from here, so this class has no dependency beyond what it already
  /// needs for the reward-pool technique roster.
  List<RunTrainingTarget> trainingCandidates(Set<String> Function() ownedItemIds) {
    final candidates = <RunTrainingTarget>[
      for (final id in ownedItemIds())
        if (!isItemUsable(character, itemDefinition(id, context), context)) TrainItemTarget(id),
    ];
    for (final id in rewardPoolTechniqueIds) {
      final technique = techniqueDefinition(id, context);
      if (isTechniqueDiscovered(character, technique, context) &&
          !isTechniqueLearned(character, technique, context)) {
        candidates.add(TrainTechniqueTarget(id));
      }
    }
    return candidates;
  }

  void runTraining(Set<String> Function() ownedItemIds, int cycleIndex) {
    final candidates = trainingCandidates(ownedItemIds);
    if (candidates.isEmpty) return;
    final target = recordingPolicy.chooseTrainingTarget(candidates);
    events.publish(TrainingStarted(target.encode()));
    final attempts = generateTrainingAttempts(rng);

    switch (target) {
      case TrainItemTarget(:final itemId):
        final item = itemDefinition(itemId, context);
        final wasUsable = isItemUsable(character, item, context);
        final exercise = itemTrainingExerciseFor(item, const TimingExercise());
        final session = TrainingSession(trainee: character, subject: itemSubject(itemId), exercise: exercise);
        for (final attempt in attempts) {
          session.submitAttempt(attempt);
        }
        final result = session.complete();
        final gain = trainingGain(result.profile);
        events.publish(
            TrainingResultRecorded(subject: target.encode(), profile: result.profile, gain: gain));
        trainingRecords.add(TrainingRecord(
          subject: target.encode(),
          attemptCount: attempts.length,
          averageQuality: result.profile.dimensions.isEmpty
              ? 0
              : TrainingStatistics.average(result.profile.dimensions.values.toList()),
          gain: gain,
        ));
        context.mastery.increase(character, itemSubject(itemId), gain);
        final nowUsable = isItemUsable(character, item, context);
        if (!wasUsable && nowUsable) {
          itemsMastered.add(itemId);
          firstItemMasteryStep ??= cycleIndex;
          tomeManager.placeItem(item, 'Training (item mastered)');
        }
      case TrainTechniqueTarget(:final familyId):
        final technique = techniqueDefinition(familyId, context);
        final exercise = techniqueTrainingExerciseFor(technique, const TimingExercise());
        final session =
            TrainingSession(trainee: character, subject: techniqueSubject(familyId), exercise: exercise);
        for (final attempt in attempts) {
          session.submitAttempt(attempt);
        }
        final result = session.complete();
        final gain = trainingGain(result.profile);
        events.publish(
            TrainingResultRecorded(subject: target.encode(), profile: result.profile, gain: gain));
        trainingRecords.add(TrainingRecord(
          subject: target.encode(),
          attemptCount: attempts.length,
          averageQuality: result.profile.dimensions.isEmpty
              ? 0
              : TrainingStatistics.average(result.profile.dimensions.values.toList()),
          gain: gain,
        ));
        final learning = attemptToLearnTechnique(character, technique, gain, context);
        if (learning.learned) {
          techniquesLearned.add(familyId);
          final baseInstance = _ownedBaseVariantFor(familyId) ??
              mintTechniqueVariant(character, familyId, const {}, context);
          if (tomeManager.slotOfTechniqueVariant(baseInstance) == null) {
            tomeManager.placeTechniqueVariant(
                baseInstance, 'Training (technique learned)');
          }

          // Evolution replaces base -> evolved exactly once per family per
          // run: only roll while the family's Tome occupant is still the
          // descriptor-less base variant (SP1 decision C). Once evolved,
          // this family's occupant stops being "the base variant" so
          // subsequent training sessions on it won't re-roll.
          final baseSlot = tomeManager.slotOfTechniqueVariant(baseInstance);
          if (baseSlot != null && _occupantIsBaseVariant(baseSlot)) {
            final evolution = resolveTechniqueEvolutionAfterTraining(
                character, technique, result.profile, context);
            if (evolution.evolved) {
              final evolvedId = evolution.chosenCandidate!.targetId;
              final evolvedInstance = mintVariantForLegacyEvolvedId(
                  character, evolvedId, context, styleId: styleId);
              tomeManager.replaceWithTechniqueVariant(
                  baseSlot, evolvedInstance, 'Training (evolved)');
              removeTechniqueVariant(baseInstance, context);
              techniquesEvolved.add(evolvedId);
              firstTechniqueEvolutionStep ??= cycleIndex;
            }
          }

          // SP0b: a training session may also *inspire* a brand-new loose
          // variant, seeded by the player's high-mastery / high-usage
          // variants. Parallel to evolution, never a replacement. In this
          // harness the player holds no TechniqueVariant instances yet
          // (the legacy learn/evolve path is still used), so this is inert
          // until a later pass migrates the harness — the call is here to
          // keep the one-authoritative-post-training-step shape visible and
          // compiled.
          final family = techniqueFamilyOf(technique.id, context);
          resolveTechniqueInspirationAfterTraining(
            character,
            technique,
            styleCentre(styleId, family),
            context,
            styleId: styleId,
          );
        }
    }
  }

  /// Whether the Tome occupant at [slot] is a descriptor-less, style-less
  /// base `TechniqueVariant` — the only state in which evolution may still
  /// roll for that family (SP1 decision C).
  bool _occupantIsBaseVariant(SlotId slot) {
    final placements =
        context.tome.inspect(character).where((p) => p.slot == slot);
    final instanceId = placements.isEmpty
        ? null
        : placements.first.buildComponentRef.instanceEntityId;
    if (instanceId == null) return false;
    final v = context.components.get<TechniqueVariant>(instanceId);
    return v != null && v.descriptorIds.isEmpty && v.styleId == null;
  }

  /// The owner's existing descriptor-less, style-less base variant for
  /// [familyId], if one is already owned (SP1 §5 — never mint a duplicate).
  EntityId? _ownedBaseVariantFor(String familyId) {
    for (final e in ownedTechniqueVariants(character, context)) {
      final v = context.components.get<TechniqueVariant>(e)!;
      if (v.baseFamilyId == familyId &&
          v.descriptorIds.isEmpty &&
          v.styleId == null) {
        return e;
      }
    }
    return null;
  }
}
