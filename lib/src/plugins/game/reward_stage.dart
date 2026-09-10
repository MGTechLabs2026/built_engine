import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';

import 'decision_log.dart';
import 'run_decision_policy.dart';
import 'run_events.dart';
import 'tome_manager.dart';

/// Owns `runGame`'s reward-pool progression: which item/technique ids are
/// still available to grant, and the trail of what's been granted so
/// far. Extracted from `runGame` (previously 3 nested closures — see
/// `ARCHITECTURE_AUDIT.md`'s god-function finding) so this piece of the
/// run is independently constructable. Delegates slot-unlocking and
/// Tome placement to the [TomeManager] it's given rather than reaching
/// into `runGame`'s shared closure scope directly.
class RewardStage {
  RewardStage({
    required this.character,
    required this.context,
    required this.recordingPolicy,
    required this.events,
    required this.tomeManager,
    required this.itemsDiscovered,
    required this.rewardPool,
    required this.physiqueTradition,
    required this.runId,
    required this.runNumber,
    required this.affixIdSource,
  });

  final EntityId character;
  final PluginContext context;
  final RecordingDecisionPolicy recordingPolicy;
  final EventBus events;
  final TomeManager tomeManager;

  /// `'western'` / `'eastern'` / null — the fighter's tradition, used
  /// only to weight the affix draw.
  final String? physiqueTradition;
  final String runId;
  final int runNumber;
  final AffixAcquisitionIdSource affixIdSource;

  /// Shared with `runGame`'s own starting-kit grant — the same list
  /// object, so both sides' appends are visible to each other and to
  /// whatever assembles the final `RunResult`.
  final List<String> itemsDiscovered;

  final List<({String referenceType, String contentId})> rewardPool;
  var rewardIndex = 0;

  final rewardsGranted = <String>[];
  int? firstRewardStep;

  List<RewardKind> rewardCandidates() => [
        if (tomeManager.hasLockedSlot) RewardKind.unlockSlot,
        if (rewardIndex < rewardPool.length) RewardKind.itemOrTechnique,
        RewardKind.upgradePoint,
      ];

  String resolveReward(RewardKind kind, String stepName) {
    switch (kind) {
      case RewardKind.unlockSlot:
        final slot = tomeManager.unlockNextSlot();
        events.publish(SlotUnlocked(slot));
        return 'slot:${slot.id}';
      case RewardKind.itemOrTechnique:
        final entry = rewardPool[rewardIndex];
        rewardIndex++;
        if (entry.referenceType == itemReferenceType) {
          final item = itemDefinition(entry.contentId, context);
          final instance = ownItem(character, item.id, context);
          discoverItem(character, item, context);
          itemsDiscovered.add(item.id);
          if (isItemUsable(character, item, context)) tomeManager.placeItem(item, '$stepName reward');
          return 'item:${item.id}${_acquireRewardAffixes(
            AffixDomain.item,
            ItemInstanceTarget(instance: instance, itemId: item.id),
            'item:${item.id}',
          )}';
        } else if (entry.referenceType == consumableReferenceType) {
          final consumable = consumableDefinition(entry.contentId, context);
          tomeManager.placeConsumable(consumable, '$stepName reward');
          return 'consumable:${consumable.id}';
        } else {
          final technique = techniqueDefinition(entry.contentId, context);
          discoverTechnique(character, technique, context);
          return 'technique:${technique.id}${_acquireRewardAffixes(
            AffixDomain.technique,
            CharacterTarget(character: character),
            'technique:${technique.id}',
          )}';
        }
      case RewardKind.upgradePoint:
        context.resources.add(character, ItemResources.upgradePoints, 1);
        return 'upgrade_point';
    }
  }

  /// Resolve the reward's affix slots (engine RNG), apply their canonical
  /// mechanics, mint acquisition identity, publish one [AffixAcquired]
  /// per acquired affix, and return the `+<affixId>` suffix for the
  /// reward string. Empty when no affix rolls.
  String _acquireRewardAffixes(
    AffixDomain domain,
    AffixApplicationTarget target,
    String rewardBaseId,
  ) {
    final resolution = resolveRewardAffixes(
      ctx: AffixRewardContext(domain: domain, physiqueTradition: physiqueTradition),
      rng: context.rng,
      content: context.content,
    );
    final acquisitions = acquireAffixes(
      resolution: resolution,
      target: target,
      idSource: affixIdSource,
      run: RunRef(runId: runId, runNumber: runNumber),
      context: context,
    );
    final suffix = StringBuffer();
    for (final acquisition in acquisitions) {
      events.publish(AffixAcquired(acquisition: acquisition, rewardBaseId: rewardBaseId));
      suffix.write('+${acquisition.affixId}');
    }
    return suffix.toString();
  }

  void grantReward(String stepName, int cycleIndex) {
    final candidates = rewardCandidates();
    events.publish(RewardOffered(candidates));
    final chosenKind = candidates[recordingPolicy.chooseReward(candidates)];
    events.publish(RewardSelected(chosenKind));
    firstRewardStep ??= cycleIndex;
    rewardsGranted.add(resolveReward(chosenKind, stepName));
  }
}
