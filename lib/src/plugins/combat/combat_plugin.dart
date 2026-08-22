import 'package:build_engine/build_engine.dart';

import 'combat_system.dart';

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
  /// holds this [CombatPlugin] instance holds `system` too.
  late final CombatSystem system;

  @override
  void initialize(PluginContext context) {
    system = CombatSystem(context);
  }
}
