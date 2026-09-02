import 'package:build_engine/build_engine.dart';

import 'technique_content.dart' show techniqueDefinition;
import 'technique_descriptor.dart';
import 'technique_events.dart';
import 'technique_lifecycle.dart' show isTechniqueLearned, TechniqueNotLearnedException;
import 'technique_variant.dart';
import 'technique_variant_resolver.dart';
import 'technique_vocabulary.dart'
    show
        TechniqueIds,
        techniqueMasteryThresholds,
        techniqueInstanceSubject,
        techniqueReferenceType;

/// Mints one technique-variant instance for [owner]: a fresh entity
/// carrying a [TechniqueVariant] whose `axisProfile` is
/// `composeAxisProfile(styleCentre, resolver.resolve(descriptors))` —
/// computed once, now (rules 2 + 3). Stamps [owner] on the component
/// (rule 5), registers a per-instance `MasteryDefinition` on the shared
/// [techniqueMasteryThresholds] curve, and publishes
/// [TechniqueVariantMinted].
///
/// SP0a does not decide *which* descriptors or *what* style centre —
/// callers (style seeding, SP0b's inspiration path, tests) pass them.
/// Throws [UnknownTechniqueDescriptorException] if any id in
/// [descriptorIds] is not loaded descriptor content.
EntityId mintTechniqueVariant(
  EntityId owner,
  String baseFamilyId,
  Set<String> descriptorIds,
  PluginContext context, {
  String? styleId,
  Map<String, num> styleCentre = const {},
}) {
  // Fail fast on a typo'd family: resolve the base definition now (throws a
  // clean content-not-found error) rather than letting it surface later at
  // hang time, and only for basics.
  techniqueDefinition(baseFamilyId, context);

  final descriptors = [
    for (final id in descriptorIds) techniqueDescriptor(id, context),
  ];
  // rule 2: resolver sees descriptors only. rule 3: compose style centre
  // outside the resolver.
  final axisProfile = composeAxisProfile(
    styleCentre,
    const TechniqueVariantResolver().resolve(descriptors),
  );

  final instance = context.entities.create();
  context.components.add<TechniqueVariant>(
    instance,
    TechniqueVariant(
      owner: owner,              // rule 5: authoritative ownership
      baseFamilyId: baseFamilyId,
      // Freeze the caller's set: a later mutation of it must not desync the
      // stored `descriptorIds` from the never-recomputed `axisProfile`.
      descriptorIds: Set.unmodifiable(descriptorIds),
      axisProfile: axisProfile,
      styleId: styleId,
    ),
  );
  context.mastery.define(
    MasteryDefinition(
      subject: techniqueInstanceSubject(instance),
      thresholds: techniqueMasteryThresholds,
    ),
  );
  context.events.publish(
    TechniqueVariantMinted(owner, instance, baseFamilyId),
  );
  return instance;
}

/// Thrown by [hangTechniqueVariant] / [removeTechniqueVariant] when
/// [instanceId] has no [TechniqueVariant] component.
class TechniqueVariantNotFoundException implements Exception {
  const TechniqueVariantNotFoundException(this.instanceId);
  final EntityId instanceId;
  @override
  String toString() => 'No technique variant for instance $instanceId';
}

/// The [TechniqueVariant] component on [instanceId], or a
/// [TechniqueVariantNotFoundException] if the entity carries none — the
/// single lookup every post-`mint` lifecycle function shares, so a bad
/// instance id always fails the same clean way.
TechniqueVariant _requireVariant(EntityId instanceId, PluginContext context) {
  final v = context.components.get<TechniqueVariant>(instanceId);
  if (v == null) throw TechniqueVariantNotFoundException(instanceId);
  return v;
}

/// Hangs the variant instance [instanceId] in its owner's Tome [slot].
/// The owner is read from `TechniqueVariant.owner` (rule 5) — not passed,
/// so a mismatched owner is impossible by construction.
///
/// A **basic** variant (no descriptors, no style) is gated on the base
/// family being `isTechniqueLearned` — the same rule `addTechniqueToTome`
/// enforces. A **derived** variant has no learning gate (mirrors "evolved
/// branches are never learned separately"). The written `BuildComponentRef`
/// carries a non-null `instanceEntityId` (rule 4), and [TechniqueAddedToTome]
/// is published with that instance.
void hangTechniqueVariant(
  SlotId slot,
  EntityId instanceId,
  PluginContext context,
) {
  final variant = _requireVariant(instanceId, context);
  final owner = variant.owner;
  final isBasic = variant.styleId == null && variant.descriptorIds.isEmpty;
  if (isBasic) {
    final family = techniqueDefinition(variant.baseFamilyId, context);
    if (!isTechniqueLearned(owner, family, context)) {
      throw TechniqueNotLearnedException(variant.baseFamilyId);
    }
  }
  context.tome.insert(
    owner,
    slot,
    BuildComponentRef(
      referenceType: techniqueReferenceType,
      contentId: variant.baseFamilyId,
      instanceEntityId: instanceId,
    ),
  );
  context.events.publish(
    TechniqueAddedToTome(owner, variant.baseFamilyId, slot,
        instanceId: instanceId),
  );
}

/// Every technique-variant instance whose `TechniqueVariant.owner` is
/// [owner] — the single authoritative "owner has this" query (rule 5).
/// Includes hung and loose (owned-but-unplaced) instances alike.
List<EntityId> ownedTechniqueVariants(EntityId owner, PluginContext context) => [
      for (final e in context.components.entitiesWith<TechniqueVariant>())
        if (context.components.get<TechniqueVariant>(e)!.owner == owner) e,
    ];

/// Adds [amount] proficiency to the per-instance MASTERY of variant
/// [instanceId]. Keyed by [techniqueInstanceSubject]; the owner is read
/// from the instance's `TechniqueVariant.owner` (rule 5). Never moves the
/// base family's own mastery.
void trainTechniqueVariantMastery(
  EntityId instanceId,
  num amount,
  PluginContext context,
) {
  final owner = _requireVariant(instanceId, context).owner;
  context.mastery.increase(owner, techniqueInstanceSubject(instanceId), amount);
}

/// Variant [instanceId]'s current MASTERY level — `0` if never trained.
int techniqueVariantMasteryLevel(EntityId instanceId, PluginContext context) {
  final owner = _requireVariant(instanceId, context).owner;
  return context.mastery.levelOf(owner, techniqueInstanceSubject(instanceId));
}

/// Fully removes variant instance [instanceId]. The owner is read from
/// its `TechniqueVariant.owner` (rule 5).
///   1. drop any Tome placement holding it,
///   2. clear its per-instance mastery progress (the `MasteryDefinition`
///      stays — `MasteryTracker` has no undefine; a definition with no
///      progress reads level 0 and is inert),
///   3. remove the `TechniqueVariant` component (entity destroy does not
///      cascade — documented),
///   4. destroy the entity,
///   5. publish [TechniqueVariantRemoved].
///
/// Throws [TechniqueVariantNotFoundException] if [instanceId] has no
/// variant component.
void removeTechniqueVariant(
  EntityId instanceId,
  PluginContext context,
) {
  final variant = _requireVariant(instanceId, context);
  final owner = variant.owner;

  for (final placement in context.tome.inspect(owner)) {
    if (placement.buildComponentRef.instanceEntityId == instanceId) {
      context.tome.remove(owner, placement.slot);
    }
  }

  final subject = techniqueInstanceSubject(instanceId);
  final mastery = context.components.get<MasteryComponent>(owner);
  if (mastery != null && mastery.progress.containsKey(subject)) {
    final trimmed = Map<String, num>.of(mastery.progress)..remove(subject);
    context.components.add<MasteryComponent>(owner, MasteryComponent(trimmed));
  }

  context.components.remove<TechniqueVariant>(instanceId);
  // `EntityRegistry.destroy` throws `StateError` on an already-dead entity.
  if (context.entities.isAlive(instanceId)) context.entities.destroy(instanceId);
  context.events.publish(TechniqueVariantRemoved(owner, instanceId));
}

/// Thrown by [mintVariantForLegacyEvolvedId] when [legacyId] resolves to a
/// hand-authored **evolved** technique with no entry in
/// [_legacyEvolvedDescriptors]. An unmapped evolved id fails loudly here
/// rather than silently degrading into a descriptor-less, basic-like
/// variant. A base technique id and a completely unknown id are both
/// handled elsewhere and never reach this exception.
class LegacyTechniqueMigrationException implements Exception {
  const LegacyTechniqueMigrationException(this.legacyId);

  final String legacyId;

  @override
  String toString() =>
      'No technique-variant migration mapping exists for legacy technique: '
      '$legacyId';
}

/// Descriptor sets for the hand-authored evolved ids, so save data / SP4
/// / SP0b can turn a legacy id into an instanced variant. Only the ids
/// with an explicit thematic mapping migrate; an evolved id absent from
/// this map is **rejected** ([LegacyTechniqueMigrationException]), never
/// silently degraded.
const _legacyEvolvedDescriptors = <String, Set<String>>{
  TechniqueIds.heavyPunch: {'strong'},
  TechniqueIds.fastPunch: {'fast'},
  TechniqueIds.lightPunch: {'focused'},
  TechniqueIds.hammerBlow: {'strong', 'iron'},
  TechniqueIds.mountainBreaker: {'mountain', 'strong'},
  TechniqueIds.lightningJab: {'lightning'},
  TechniqueIds.flashStrike: {'flash'},
  TechniqueIds.thunderFlash: {'thunder', 'flash'},
  TechniqueIds.heavySlash: {'strong'},
  TechniqueIds.quickSlash: {'swift'},
  TechniqueIds.lightningSlash: {'lightning'},
  TechniqueIds.mountainCleave: {'mountain', 'strong'},
  TechniqueIds.ironPalm: {'iron'},
  TechniqueIds.thunderPalm: {'thunder'},
  TechniqueIds.lightningFinger: {'lightning'},
  TechniqueIds.needleFinger: {'needle'},
  TechniqueIds.piercingFinger: {'needle', 'one_hit'},
  TechniqueIds.thrustKick: {'strong'},
  TechniqueIds.spinningKick: {'strong'},
  TechniqueIds.whirlwindKick: {'swift', 'strong'},
};

/// The base family for [legacyId], read from its content's family tag.
String _familyOf(String legacyId, PluginContext context) {
  final tags = techniqueDefinition(legacyId, context).tags;
  const familyTagToBase = {
    'fist': TechniqueIds.basicPunch,
    'blade': TechniqueIds.basicSlash,
    'guard': TechniqueIds.basicGuard,
    'palm': TechniqueIds.basicPalm,
    'finger': TechniqueIds.basicFinger,
    'kick': TechniqueIds.basicKick,
  };
  for (final entry in familyTagToBase.entries) {
    if (tags.contains(entry.key)) return entry.value;
  }
  return legacyId; // already a base, or unknown — mint against itself
}

/// Migrates a hand-authored technique id to an instanced variant. The id
/// is classified against content already in the plugin — never inferred
/// from the presence or absence of a descriptor mapping:
///
/// - **Base technique** ([TechniqueIds.bases]): not an evolved migration
///   at all. Minted straight through the normal SP0a path — a base is
///   legitimately descriptor-less.
/// - **Evolved technique with a mapping**: minted with the mapped
///   descriptors on its family. The mapping approximates the legacy
///   identity as far as SP0a can represent it; it does not reproduce the
///   old combat behaviour.
/// - **Evolved technique with no mapping**: rejected with
///   [LegacyTechniqueMigrationException] — never silently degraded to a
///   descriptor-less basic-like variant.
/// - **Completely unknown id**: fails first in `techniqueDefinition` with
///   the existing content-not-found error, before any classification.
///
/// Additive: the legacy definition still resolves via `techniqueDefinition`
/// and nothing calls this unless a caller opts in. On any failure no
/// entity, component, mastery state, or event is left behind (the mint
/// validates everything before `entities.create()`).
EntityId mintVariantForLegacyEvolvedId(
  EntityId owner,
  String legacyId,
  PluginContext context, {
  String? styleId,
}) {
  // Resolve the content first: a completely unknown id fails here with the
  // existing `ContentNotFoundException`, never a migration exception.
  techniqueDefinition(legacyId, context);

  // A base family (the six ids with an independent LEARNING axis) is not an
  // evolved-technique migration; it maps to itself and is legitimately
  // descriptor-less.
  if (TechniqueIds.bases.contains(legacyId)) {
    return mintTechniqueVariant(owner, legacyId, const {}, context,
        styleId: styleId);
  }

  // Everything else that resolved as content is an evolved branch. It MUST
  // carry an explicit descriptor mapping — absence is a loud failure, not a
  // silent downgrade.
  final descriptors = _legacyEvolvedDescriptors[legacyId];
  if (descriptors == null) {
    throw LegacyTechniqueMigrationException(legacyId);
  }

  return mintTechniqueVariant(
    owner,
    _familyOf(legacyId, context),
    descriptors,
    context,
    styleId: styleId,
  );
}
