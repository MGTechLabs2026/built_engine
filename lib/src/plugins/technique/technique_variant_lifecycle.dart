import 'package:build_engine/build_engine.dart';

import 'technique_content.dart' show techniqueDefinition;
import 'technique_descriptor.dart';
import 'technique_events.dart';
import 'technique_lifecycle.dart' show isTechniqueLearned, TechniqueNotLearnedException;
import 'technique_variant.dart';
import 'technique_variant_resolver.dart';
import 'technique_vocabulary.dart';

export 'technique_descriptor.dart' show UnknownTechniqueDescriptorException;

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
      descriptorIds: descriptorIds,
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
  final variant = context.components.get<TechniqueVariant>(instanceId);
  if (variant == null) {
    throw TechniqueVariantNotFoundException(instanceId);
  }
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
