import 'package:build_engine/build_engine.dart';

import 'martial_arts_rules.dart';

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

  final List<EventSubscription> _subscriptions = [];

  @override
  void initialize(PluginContext context) {
    for (final rule in buildMartialArtsRules()) {
      _subscriptions.add(context.rules.register(rule));
    }
  }

  /// Mirrors [initialize]: cancels every rule subscription taken out
  /// there, so an unregistered `MartialArtsPlugin` stops reacting to
  /// events entirely — the same teardown discipline `CombatPlugin`
  /// established for its own `EntityKilled` subscription.
  @override
  void unregister(PluginContext context) {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
