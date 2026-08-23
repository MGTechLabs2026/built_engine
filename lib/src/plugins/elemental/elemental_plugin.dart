import 'package:build_engine/build_engine.dart';

import 'elemental_affinity_component.dart';
import 'elemental_conditions.dart';
import 'elemental_content.dart';
import 'elemental_effects.dart';
import 'elemental_item_content.dart';
import 'elemental_rules.dart';
import 'elemental_vocabulary.dart';

/// The reference plugin for the Plugin SDK: Fire/Water/Lightning, built
/// entirely with `PluginSdk`, depending on nothing but Core — not
/// Combat, not MartialArts. Copy this plugin, not MartialArts, as the
/// starting point for a new content plugin.
class ElementalPlugin extends GamePlugin {
  @override
  String get id => 'elemental';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can be
  /// `initialize`d again after `unregister` (same reasoning as
  /// `CombatPlugin.system`).
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);

    sdk.registerComponentCleanup<ElementalAffinityComponent>();

    sdk.registerEffect(
      'applyElementalStatus',
      (p) => ApplyElementalStatus(ContentField.requireString(p, 'element')),
    );
    sdk.registerCondition(
      'hasElementalAffinity',
      (p) => HasElementalAffinity(
        ContentField.requireString(p, 'element'),
        ContentField.requireNum(p, 'threshold'),
      ),
    );

    sdk.registerTag('element:fire',
        description: 'Fire-aligned entity or content.');
    sdk.registerTag('element:water',
        description: 'Water-aligned entity or content.');
    sdk.registerTag('element:lightning',
        description: 'Lightning-aligned entity or content.');
    sdk.registerTag('magic', description: 'Magic-sourced entity or content.');
    sdk.registerTag('fire',
        description: 'Fire-flavored entity or content (see also element:fire).');
    sdk.registerTag('elemental',
        description: 'Elemental-sourced entity or content.');
    sdk.registerTag('spell', description: 'A castable magic spell.');

    for (final rule in buildElementalRules()) {
      sdk.registerRule(rule);
    }

    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find('fireball') == null) {
      sdk.registerContentBatch(elementalContentDefinitions);
    }
    if (context.content.find(ElementalItemIds.emberCharm) == null) {
      sdk.registerContentBatch(elementalItemContentDefinitions);
    }
  }

  /// Mirrors [initialize]: cancels every subscription taken out there —
  /// component cleanup and the "water conducts" rule — so an
  /// unregistered `ElementalPlugin` stops reacting to events
  /// entirely, the same teardown discipline `CombatPlugin`/
  /// `MartialArtsPlugin` already established.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
