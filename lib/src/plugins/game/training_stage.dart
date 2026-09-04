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

    // Base-family LEARNING candidates (reward roster, discovered, not learned).
    for (final id in rewardPoolTechniqueIds) {
      final technique = techniqueDefinition(id, context);
      if (isTechniqueDiscovered(character, technique, context) &&
          !isTechniqueLearned(character, technique, context)) {
        candidates.add(TrainTechniqueTarget(id));
      }
    }

    // Per-instance variant-MASTERY candidates: any owned variant below the
    // top rank, on any family (SP1 decision B — owned variants stay
    // trainable after their base family is learned).
    final topRank = techniqueMasteryThresholds.length;
    for (final e in ownedTechniqueVariants(character, context)) {
      if (techniqueVariantMasteryLevel(e, context) < topRank) {
        final v = context.components.get<TechniqueVariant>(e)!;
        candidates.add(TrainTechniqueTarget(v.baseFamilyId, variantInstanceId: e));
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

    String? trainedFamilyId;

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
      case TrainTechniqueTarget(:final familyId, :final variantInstanceId):
        trainedFamilyId = familyId;
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

        if (variantInstanceId == null) {
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
          }
        } else {
          // Per-instance MASTERY only — never the base family's own axes
          // (SP1 decision G: base-family LEARNING/MASTERY and per-instance
          // variant MASTERY are never collapsed together).
          trainTechniqueVariantMastery(variantInstanceId, gain, context);
        }
    }

    // Inspiration — one roll per training session, EVERY target type,
    // at the true post-training boundary (SP1 decision D). No longer
    // nested under first-time learning.
    final familyForInspiration = trainedFamilyId ?? _topOwnedVariantFamily();
    if (familyForInspiration != null) {
      final familyDef = techniqueDefinition(familyForInspiration, context);
      resolveTechniqueInspirationAfterTraining(
        character,
        familyDef,
        styleCentre(styleId, familyForInspiration),
        context,
        styleId: styleId,
      );
    }
  }

  /// Whether the Tome occupant at [slot] is a descriptor-less, style-less
  /// base `TechniqueVariant` — the only state in which evolution may still
  /// roll for that family (SP1 decision C).
  ///
  /// SP1 scope note: the spec's decision C also describes a retry path
  /// from a variant-MASTERY session (train an already-owned base variant
  /// again before it evolves) — this guard is only actually consulted
  /// from the LEARNING sub-case today, because `EvolutionResolver`'s
  /// candidates in shipped content carry no `conditions`, so evolution
  /// always succeeds in the same session that crosses the learning
  /// threshold; the "trained again before it evolved" case cannot arise
  /// with current content. If a future evolution candidate ever gains a
  /// condition that can make a roll miss, this guard would need to be
  /// consulted from the variant-mastery branch too, or a near-miss family
  /// could become permanently un-evolvable.
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

  /// The family of the owner's "best" owned variant — highest per-instance
  /// mastery, then highest usage this run, then lowest instance id — or
  /// `null` if the owner holds no variants. Used to seed inspiration for
  /// an item-training session, which has no technique family of its own
  /// (SP1 decision D).
  String? _topOwnedVariantFamily() {
    final owned = ownedTechniqueVariants(character, context);
    if (owned.isEmpty) return null;
    owned.sort((a, b) {
      final byMastery = techniqueVariantMasteryLevel(b, context)
          .compareTo(techniqueVariantMasteryLevel(a, context));
      if (byMastery != 0) return byMastery;
      final byUsage = techniqueVariantUsage(b, context)
          .compareTo(techniqueVariantUsage(a, context));
      if (byUsage != 0) return byUsage;
      return a.value.compareTo(b.value);
    });
    return context.components.get<TechniqueVariant>(owned.first)!.baseFamilyId;
  }
}
