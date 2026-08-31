/// **The headless reference / balance-simulation harness** — *not* the
/// authoritative shipped run. It composes every plugin (Physique,
/// MartialArts, Item, Technique, Training, Tome, Build Interpretation,
/// AutoCombat, Combat) into one deterministic `runGame(seed, {policy})`
/// so balance can be probed and regressions caught in CI, and so a
/// `DecisionLog` can replay a run exactly.
///
/// Ownership after audit A1:
///
///  * **The client (`Tome_client`) owns run composition** — screen
///    sequencing, the structured run flow (Tome → fights → rewards →
///    hard fight → Tome), the run-length progression, enemy-roster and
///    reward-pool *selection*, and all presentation. Those are UI-facing
///    orchestration.
///  * **The engine owns the domain rules both this harness and the
///    client consume** — combat math (`CombatSystem`/`AutoCombatController`),
///    style-scoped combat rules (`StyleCombatRules`, audit A2), the
///    post-training evolution decision + `TechniqueEvolved`
///    (`resolveTechniqueEvolutionAfterTraining`, audit A4), evolution
///    weighting (`EvolutionResolver`), reward generation (`RewardResolver`),
///    RNG (`RngService`), and the item / technique lifecycles.
///
/// This harness deliberately runs a *simpler* combat model than the
/// shipped client (its `AutoCombatController` path has no per-turn
/// mastery success roll and no mid-fight stance entry), so it does not
/// exercise every style specialty — but it must never implement a
/// *conflicting* rule: anything style-scoped it does apply comes from
/// `StyleCombatRules`, the one implementation.
///
/// Game-specific content (encounters, enemies, reward pools) lives here,
/// never in Core or in any plugin. Lives under `lib/src/plugins/game/`,
/// not `lib/src/game/` — a composition layer, not a registrable
/// `GamePlugin`, the same positioning `lib/src/plugins/build_interpretation/`
/// already established.
library;

export 'src/plugins/game/balance_signals.dart';
export 'src/plugins/game/combat_stage.dart';
export 'src/plugins/game/decision_log.dart';
export 'src/plugins/game/enemy.dart';
export 'src/plugins/game/enemy_content.dart';
export 'src/plugins/game/game_run.dart';
export 'src/plugins/game/playtest_report.dart';
export 'src/plugins/game/reward_stage.dart';
export 'src/plugins/game/run_content.dart';
export 'src/plugins/game/run_decision_policy.dart';
export 'src/plugins/game/run_events.dart';
export 'src/plugins/game/run_result.dart';
export 'src/plugins/game/tome_manager.dart';
export 'src/plugins/game/training_simulation.dart';
export 'src/plugins/game/training_stage.dart';
