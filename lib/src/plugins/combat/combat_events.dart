import 'package:build_engine/build_engine.dart';

import 'combat_action.dart';

/// Published by `CombatSystem.executeAction` before evaluating [action]'s
/// conditions — always, whether or not they end up passing.
class ActionStarted {
  const ActionStarted(this.battle, this.actor, this.targets, this.action);
  final EntityId battle;
  final EntityId actor;
  final List<EntityId> targets;
  final CombatAction action;
}

/// Published by `CombatSystem.executeAction` after [action]'s effects (if
/// any applied) have run. Its presence with no `EntityDamaged`/etc. in
/// between marks an action whose conditions failed.
class ActionCompleted {
  const ActionCompleted(this.battle, this.actor, this.targets, this.action);
  final EntityId battle;
  final EntityId actor;
  final List<EntityId> targets;
  final CombatAction action;
}

/// Published by `CombatSystem` when [actor]'s turn in [battle] begins.
class TurnStarted {
  const TurnStarted(this.battle, this.actor, this.round);
  final EntityId battle;
  final EntityId actor;
  final int round;
}

/// Published by `CombatSystem` when [actor]'s turn in [battle] ends —
/// always, even if that same action also ended the battle.
class TurnEnded {
  const TurnEnded(this.battle, this.actor, this.round);
  final EntityId battle;
  final EntityId actor;
  final int round;
}

/// Published by `CombatSystem.startBattle`.
class BattleStarted {
  const BattleStarted(this.battle, this.participants);
  final EntityId battle;
  final List<EntityId> participants;
}

/// Published once per surviving team when [battle] ends with exactly one
/// team still standing.
class BattleWon {
  const BattleWon(this.battle, this.team);
  final EntityId battle;
  final String team;
}

/// Published once per eliminated team when [battle] ends — every starting
/// team, if the battle ends in mutual annihilation.
class BattleLost {
  const BattleLost(this.battle, this.team);
  final EntityId battle;
  final String team;
}
