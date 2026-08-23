import 'package:build_engine/build_engine.dart';

import 'combat_state_component.dart';
import 'combat_system.dart';
import 'combatant_component.dart';

/// Turn-based combat as an ordinary plugin: combatants, actions, targets,
/// damage, healing, and defeat, expressed entirely through core's generic
/// services (entities, components, events, conditions, effects, queries,
/// modifiers, RNG). No martial-arts/magic/cultivation/weapon vocabulary —
/// those are separate future plugins that depend on this one, never the
/// reverse (`claude.md`'s DEPENDENCY RULE).
class CombatPlugin extends GamePlugin {
  @override
  String get id => 'combat';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; the only way calling code reaches
  /// Combat's behavior — there's no service-locator in core, so whoever
  /// holds this [CombatPlugin] instance holds `system` too. Not `final` —
  /// a [CombatPlugin] can be `initialize`d again after `unregister` (see
  /// [unregister]), and `late final` would throw on the second assignment.
  late CombatSystem system;

  /// Cleans up `CombatantComponent`/`CombatStateComponent` on
  /// `EntityDestroyed` (see [initialize]/[unregister]).
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    system = CombatSystem(context);
    sdk = PluginSdk(context);
    sdk.registerComponentCleanup<CombatantComponent>();
    sdk.registerComponentCleanup<CombatStateComponent>();
  }

  /// Mirrors [initialize]: tears down the `EntityKilled` subscription
  /// `system` took out and the `EntityDestroyed` cleanup subscriptions
  /// [sdk] took out, so a stopped/unregistered `CombatPlugin` stops
  /// reacting to events entirely.
  @override
  void unregister(PluginContext context) {
    system.dispose();
    sdk.disposeAll();
  }
}
