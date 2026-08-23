import 'package:build_engine/build_engine.dart';

import 'martial_arts_rules.dart';
import 'martial_loadout_component.dart';
import 'martial_technique_content.dart';

/// MartialArts as an ordinary plugin: styles, techniques, stances, items,
/// and trinkets, expressed entirely through Combat's and Core's public
/// APIs. `dependencies => ['combat']` orders this plugin's lifecycle
/// after Combat's, but `MartialArtsPlugin` never holds a reference to
/// `CombatPlugin`/`CombatSystem` — only to Combat's public event
/// vocabulary, reached through the shared `RuleEngine` every plugin
/// already gets via `PluginContext`. Nothing in Combat's source
/// references MartialArts.
class MartialArtsPlugin extends GamePlugin {
  @override
  String get id => 'martial_arts';

  @override
  String get version => '0.1.0';

  @override
  List<String> get dependencies => const ['combat'];

  /// Constructed in [initialize]; not `late final` since a plugin can be
  /// `initialize`d again after `unregister`.
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);
    sdk.registerComponentCleanup<MartialLoadoutComponent>();
    for (final rule in buildMartialArtsRules()) {
      sdk.registerRule(rule);
    }
    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find('jab') == null) {
      sdk.registerContentBatch(martialTechniqueContentDefinitions);
    }
  }

  /// Mirrors [initialize]: cancels every rule and cleanup subscription
  /// [sdk] took out, so an unregistered `MartialArtsPlugin` stops
  /// reacting to events entirely — the same teardown discipline
  /// `CombatPlugin` established for its own `EntityKilled` subscription.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
