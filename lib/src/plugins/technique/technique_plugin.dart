import 'package:build_engine/build_engine.dart';

import 'technique_content.dart';
import 'technique_descriptor_content.dart';
import 'technique_vocabulary.dart';

/// The Technique plugin: generic learnable movements/abilities (Basic
/// Punch/Slash/Guard and their 8 evolved branches), built entirely with
/// `PluginSdk`, depending on nothing but Core — not Combat, not
/// MartialArts. A third proof (after `ElementalPlugin`/`ItemPlugin`) that
/// "copy Elemental, not MartialArts" produces a fully decoupled content
/// plugin.
///
/// Registers a single-tier `ProgressionDefinition` per base technique
/// (its LEARNING threshold) and a multi-tier `MasteryDefinition` (its
/// proficiency curve) — two independent registrations under two
/// deliberately different subject strings (see
/// `technique_vocabulary.dart`), keeping Discovery/Learning/Mastery from
/// ever colliding in storage. No `ComponentStore` cleanup is registered:
/// unlike `ItemPlugin` (which creates a per-owned-copy `ItemInstance`
/// entity), nothing here attaches a new component type to any entity —
/// every axis is tracked entirely through the existing
/// Discovery/Progression/Mastery trackers, keyed by subject strings, with
/// zero new ECS state of its own.
class TechniquePlugin extends GamePlugin {
  @override
  String get id => 'technique';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can be
  /// `initialize`d again after `unregister`.
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);

    sdk.registerTag('technique', description: 'A learnable movement/ability.');

    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find(TechniqueIds.basicPunch) == null) {
      sdk.registerContentBatch(techniqueContentDefinitions);
    }

    final firstDescriptorId =
        techniqueDescriptorContentDefinitions.first['id'] as String;
    // Same idempotency guard as the technique batch above.
    if (context.content.find(firstDescriptorId) == null) {
      sdk.registerContentBatch(techniqueDescriptorContentDefinitions);
    }

    // MASTERY axis for every technique — base and evolved alike — so a
    // rewarded or evolved form gains a rank from training exactly like a
    // base form. (Only the three base forms also get the LEARNING axis;
    // evolved branches are terminal and never "learned" separately.)
    for (final def in techniqueContentDefinitions) {
      final id = def['id'] as String;
      context.mastery.define(
        MasteryDefinition(
          subject: techniqueSubject(id),
          thresholds: techniqueMasteryThresholds,
        ),
      );
    }
    for (final id in TechniqueIds.bases) {
      context.progression.define(
        ProgressionDefinition(
          subject: techniqueKnowledgeSubject(id),
          thresholds: techniqueLearningThresholds,
        ),
      );
    }
  }

  /// Nothing to tear down beyond the SDK's own bookkeeping — this plugin
  /// registers no rules, no event subscriptions, no component cleanup.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
