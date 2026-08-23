/// AutoCombat — a separate layer built on top of Combat, deciding *what
/// action to perform* each turn. Combat itself remains untouched and
/// independently usable; this package only ever calls its existing public
/// API (`CombatSystem.executeAction`, `CombatStateComponent`,
/// `CombatantComponent`). No martial-arts/magic/weapon vocabulary — those
/// are content, not AutoCombat's concern.
library;

export 'src/plugins/auto_combat/action_selector.dart';
export 'src/plugins/auto_combat/auto_combat_controller.dart';
export 'src/plugins/auto_combat/combat_policy.dart';
export 'src/plugins/auto_combat/target_selector.dart';
