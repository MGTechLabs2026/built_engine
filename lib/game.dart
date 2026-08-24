/// The first real headless game run — composes every existing plugin
/// (Physique, MartialArts, Item, Technique, Training, Tome, Build
/// Interpretation, AutoCombat, Combat) into one deterministic
/// `runGame(seed, {policy})` API. Game-specific content (encounters,
/// enemies, reward pools) lives here, never in Core or in any plugin.
///
/// Lives under `lib/src/plugins/game/`, not `lib/src/game/` — a
/// composition layer over multiple plugins, not a registrable
/// `GamePlugin` itself, the same positioning `lib/src/plugins/
/// build_interpretation/` already established.
library;

export 'src/plugins/game/enemy.dart';
export 'src/plugins/game/game_run.dart';
export 'src/plugins/game/run_content.dart';
export 'src/plugins/game/run_decision_policy.dart';
export 'src/plugins/game/run_result.dart';
export 'src/plugins/game/training_simulation.dart';
