import 'package:build_engine/build_engine.dart';

import 'technique_descriptor.dart';
import 'technique_events.dart';
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
