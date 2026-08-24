/// Build -> Action interpretation — the bridging layer between the Tome
/// (`ActiveBuild`) and combat (`CombatAction`/`AutoCombat`). A separate
/// layer built on top of Technique/Item/Combat, exactly the way
/// `AutoCombat` is a separate layer built on top of Combat: none of
/// Core, Combat, the Technique plugin, or the Item plugin is modified to
/// support this — only this package depends on all three.
library;

export 'src/plugins/build_interpretation/build_action_interpreter.dart';
export 'src/plugins/build_interpretation/composite_build_action_interpreter.dart';
export 'src/plugins/build_interpretation/item_action_interpreter.dart';
export 'src/plugins/build_interpretation/self_effect_action.dart';
export 'src/plugins/build_interpretation/technique_action_interpreter.dart';
