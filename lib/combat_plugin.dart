/// Combat — a plugin built on Build Engine core. Turn-based combat
/// (combatants, actions, targets, damage, healing, defeat) with zero
/// martial-arts/magic/cultivation/weapon vocabulary — see `claude.md`'s
/// CORE PROVIDES VERBS / PLUGINS PROVIDE NOUNS contract. Depends only on
/// `package:build_engine/build_engine.dart`'s public core API.
library;

export 'src/plugins/combat/combat_action.dart';
export 'src/plugins/combat/combat_events.dart';
export 'src/plugins/combat/combat_plugin.dart';
export 'src/plugins/combat/combat_state_component.dart';
export 'src/plugins/combat/combat_system.dart';
export 'src/plugins/combat/combatant_component.dart';
export 'src/plugins/combat/illegal_action_exception.dart';
