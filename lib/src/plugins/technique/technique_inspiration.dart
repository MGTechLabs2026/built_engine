import 'dart:math' show sqrt;

import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart' show TechniqueDefinition;
import 'technique_descriptor.dart';
import 'technique_events.dart';
import 'technique_usage.dart' show techniqueVariantUsage;
import 'technique_variant_lifecycle.dart'
    show
        mintTechniqueVariant,
        ownedTechniqueVariants,
        requireTechniqueVariant,
        techniqueFamilyOf,
        techniqueVariantMasteryLevel;
import 'technique_vocabulary.dart';

/// One of an owner's technique-variant instances, offered to
/// [TechniqueInspirationResolver] as raw material. The caller does **not**
/// pre-filter — the resolver applies the eligibility test itself.
class Inspirer {
  const Inspirer({
    required this.instanceId,
    required this.axisProfile,
    required this.masteryLevel,
    required this.usage,
  });

  /// The variant entity — reported back in [InspirationResult] and the
  /// event, never used in the resolver's arithmetic.
  final EntityId instanceId;

  /// The variant's stored `TechniqueVariant.axisProfile` (signed).
  final Map<String, num> axisProfile;

  /// Per-instance mastery level, `0..3`.
  final int masteryLevel;

  /// Combat actions performed this run, `>= 0`.
  final int usage;
}

/// The outcome of one discovery roll. `discovered == false` ⇒ every other
/// field is empty ([none]).
class InspirationResult {
  const InspirationResult({
    required this.discovered,
    required this.familyId,
    required this.descriptorIds,
    required this.inspirerInstanceIds,
  });

  final bool discovered;

  /// `== trainedFamilyId` on a hit; `''` otherwise.
  final String familyId;

  /// `1..3` descriptor ids on a hit; empty otherwise.
  final Set<String> descriptorIds;

  /// The eligible inspirers the resolver actually used; `[]` on a miss.
  final List<EntityId> inspirerInstanceIds;

  static const none = InspirationResult(
    discovered: false,
    familyId: '',
    descriptorIds: {},
    inspirerInstanceIds: [],
  );
}

/// Whether descriptor [d] may be drawn for a variant of base family
/// [familyId]. A descriptor with no `family:` tag is universal; one with
/// any `family:` tag is compatible only if one of them names [familyId].
bool descriptorCompatibleWithFamily(TechniqueDescriptor d, String familyId) {
  final familyTags =
      d.tags.where((t) => t.startsWith(techniqueFamilyTagPrefix)).toList();
  if (familyTags.isEmpty) return true;
  return familyTags.contains('$techniqueFamilyTagPrefix$familyId');
}

/// Pure blend of an owner's high-mastery, heavily-used technique variants
/// into a descriptor set for a new variant on the trained family. A
/// `const` class with one method, drawing randomness only from the
/// injected [RngService] — mirrors `EvolutionResolver` / `RewardResolver`.
class TechniqueInspirationResolver {
  const TechniqueInspirationResolver();

  InspirationResult resolve({
    required String trainedFamilyId,
    required Iterable<Inspirer> inspirers,
    required Iterable<TechniqueDescriptor> descriptorPool,
    required RngService rng,
    Set<Set<String>> exclude = const {},
  }) {
    // Step 0 — eligibility (return before touching rng).
    final eligible = [
      for (final i in inspirers)
        if (i.masteryLevel >= kMinMasteryToInspire &&
            i.usage >= kMinUsageToInspire)
          i,
    ];
    if (eligible.isEmpty) return InspirationResult.none;

    // Step 1 — damped inspirer weights: w = mastery * sqrt(usage).
    final weights = [
      for (final i in eligible) i.masteryLevel * sqrt(i.usage),
    ];
    final totalWeight = weights.fold<double>(0, (s, w) => s + w);
    if (totalWeight <= 0) return InspirationResult.none;

    // Step 2 — emphasis E from positive axis contributions only.
    final emphasis = <String, double>{};
    for (var n = 0; n < eligible.length; n++) {
      final w = weights[n];
      eligible[n].axisProfile.forEach((axis, mag) {
        if (mag > 0) emphasis[axis] = (emphasis[axis] ?? 0) + w * mag;
      });
    }
    final emphasisTotal = emphasis.values.fold<double>(0, (s, v) => s + v);
    if (emphasisTotal <= 0) return InspirationResult.none;
    emphasis.updateAll((_, v) => v / emphasisTotal);

    // Step 3 — concentration c = max weight / total weight.
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    final concentration = maxWeight / totalWeight;

    // Step 4 — the single discovery roll (the one-per-training guarantee).
    final p = (kInspirationBaseChance +
            kInspirationConcentrationGain * concentration)
        .clamp(0.0, 1.0);
    if (rng.nextDouble() >= p) return InspirationResult.none;

    // Steps 5–8 — compatible pool, k, weighted draw, exclusion retry.
    return _draw(
      trainedFamilyId: trainedFamilyId,
      eligible: eligible,
      weights: weights,
      totalWeight: totalWeight,
      emphasis: emphasis,
      descriptorPool: descriptorPool,
      rng: rng,
      exclude: exclude,
    );
  }

  InspirationResult _draw({
    required String trainedFamilyId,
    required List<Inspirer> eligible,
    required List<double> weights,
    required double totalWeight,
    required Map<String, double> emphasis,
    required Iterable<TechniqueDescriptor> descriptorPool,
    required RngService rng,
    required Set<Set<String>> exclude,
  }) {
    // Step 5 — compatible descriptor pool.
    final compatible = [
      for (final d in descriptorPool)
        if (descriptorCompatibleWithFamily(d, trainedFamilyId)) d,
    ];
    if (compatible.isEmpty) return InspirationResult.none;

    // Step 6 — descriptor count k (before the weighted draw). Single
    // source → 1; multi-source → 2; strong multi-source blend → 3.
    // NO `eligible.length == 1` concentration special-case anywhere — c
    // already came out 1.0 in step 3 by construction.
    final meanMastery =
        eligible.map((i) => i.masteryLevel).reduce((a, b) => a + b) /
            eligible.length;
    final strong = eligible.length >= 2 &&
        meanMastery >= kInspirationStrongMasteryBar &&
        totalWeight >= kInspirationStrongWeightBar;
    var k = eligible.length >= 2 ? 2 : 1;
    if (strong) k = 3;
    if (k > 3) k = 3;
    if (k > compatible.length) k = compatible.length;

    // Steps 7–8 — weighted draw without replacement, exclusion retry.
    for (var attempt = 0; attempt <= kInspirationExcludeRetries; attempt++) {
      final remaining = [...compatible];
      final pickedDescriptors = <TechniqueDescriptor>[];
      final pickedIds = <String>{};
      for (var d = 0; d < k; d++) {
        final chosen = weightedPick(
          remaining,
          (cand) => _overlap(emphasis, cand),
          rng,
        );
        if (chosen == null) break; // no positive-overlap candidate left
        pickedDescriptors.add(chosen);
        pickedIds.add(chosen.id);
        remaining.remove(chosen);
      }
      if (pickedIds.isEmpty) return InspirationResult.none;
      final isExcluded = exclude.any((s) => _setEquals(s, pickedIds));
      if (!isExcluded) {
        return InspirationResult(
          discovered: true,
          familyId: trainedFamilyId,
          descriptorIds: Set.unmodifiable(pickedIds),
          // Step 9 — attribution: only the inspirers that actually shaped
          // a drawn descriptor, NOT the whole eligible set.
          inspirerInstanceIds:
              _attribute(eligible, weights, pickedDescriptors),
        );
      }
      // excluded → loop, redrawing with the already-advanced rng.
    }
    return InspirationResult.none;
  }
}

double _overlap(Map<String, double> emphasis, TechniqueDescriptor d) {
  var sum = 0.0;
  d.axes.forEach((axis, mag) {
    if (mag > 0) sum += (emphasis[axis] ?? 0) * mag;
  });
  return sum;
}

/// Spec §6.2 step 9 — pure, no RNG. For each drawn descriptor, the
/// eligible inspirer with the greatest positive-axis support wins (strict
/// `>` keeps the lowest index on a tie — the documented tie-break). Union
/// of winners, ascending `eligible` index.
List<EntityId> _attribute(
  List<Inspirer> eligible,
  List<double> weights,
  Iterable<TechniqueDescriptor> drawn,
) {
  final chosen = <int>{};
  for (final d in drawn) {
    final positiveAxes = [
      for (final e in d.axes.entries)
        if (e.value > 0) e.key,
    ];
    var bestIdx = -1;
    var bestSupport = double.negativeInfinity;
    for (var i = 0; i < eligible.length; i++) {
      var support = 0.0;
      for (final axis in positiveAxes) {
        final mag = eligible[i].axisProfile[axis] ?? 0;
        if (mag > 0) support += weights[i] * mag;
      }
      if (support > bestSupport) {
        bestSupport = support;
        bestIdx = i; // strict `>` → earliest max index survives ties
      }
    }
    // Every drawn descriptor has weight(d) > 0 (step 7), so some inspirer
    // has support > 0 — this is always satisfied on a real discovery.
    if (bestIdx >= 0 && bestSupport > 0) chosen.add(bestIdx);
  }
  final ordered = chosen.toList()..sort();
  return [for (final i in ordered) eligible[i].instanceId];
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.every(b.contains);

/// The one authoritative "did this training session inspire a new
/// variant?" step — call once after a training session, parallel to
/// `resolveTechniqueEvolutionAfterTraining`. [styleCentre] is the trained
/// family's axis nudge for the character's style; the caller supplies it
/// (the technique plugin never imports `martial_arts`).
///
/// Gathers [owner]'s variant instances as [Inspirer]s (mastery + usage
/// from this plugin's own trackers — a newly minted variant has
/// `masteryLevel 0` / `usage 0` and so cannot inspire), runs
/// [TechniqueInspirationResolver] exactly once, and on a hit:
///   * `mintTechniqueVariant(owner, familyId, descriptorIds, context,
///      styleId: styleId, styleCentre: styleCentre)` — owned but loose,
///   * publishes [TechniqueVariantInspired] exactly once, carrying the
///     result's `descriptorIds` and `inspirerInstanceIds` verbatim (the
///     latter is already narrowed to the actually-contributing sources by
///     spec §6.2 step 9 — the hook does no further filtering).
/// One call → one discovery-probability roll → at most one mint and one
/// event. No cooldown, no discovery-lock component, no mutable state.
/// Returns the [InspirationResult]; the caller owns telemetry / UI. The
/// inspirers are never touched.
InspirationResult resolveTechniqueInspirationAfterTraining(
  EntityId owner,
  TechniqueDefinition trainedTechnique,
  Map<String, num> styleCentre,
  PluginContext context, {
  String? styleId,
}) {
  final familyId = techniqueFamilyOf(trainedTechnique.id, context);

  final inspirers = <Inspirer>[];
  final exclude = <Set<String>>{};
  for (final e in ownedTechniqueVariants(owner, context)) {
    final v = requireTechniqueVariant(e, context);
    inspirers.add(Inspirer(
      instanceId: e,
      axisProfile: v.axisProfile,
      masteryLevel: techniqueVariantMasteryLevel(e, context),
      usage: techniqueVariantUsage(e, context),
    ));
    if (v.baseFamilyId == familyId) exclude.add(v.descriptorIds);
  }

  if (inspirers.isEmpty) return InspirationResult.none;

  final pool = [
    for (final def in context.content.allOfType('technique_descriptor'))
      techniqueDescriptorFromContent(def),
  ];

  final result = const TechniqueInspirationResolver().resolve(
    trainedFamilyId: familyId,
    inspirers: inspirers,
    descriptorPool: pool,
    rng: context.rng,
    exclude: exclude,
  );
  if (!result.discovered) return result;

  final instance = mintTechniqueVariant(
    owner,
    familyId,
    result.descriptorIds,
    context,
    styleId: styleId,
    styleCentre: styleCentre,
  );
  context.events.publish(TechniqueVariantInspired(
    owner: owner,
    instanceId: instance,
    familyId: familyId,
    descriptorIds: result.descriptorIds,
    inspirerInstanceIds: result.inspirerInstanceIds,
  ));
  return result;
}
