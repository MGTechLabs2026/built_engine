import 'package:build_engine/build_engine.dart';

import 'combat_action.dart';
import 'combat_events.dart';
import 'combat_state_component.dart';
import 'combatant_component.dart';
import 'illegal_action_exception.dart';

/// Combat's turn/battle orchestration: starts battles, executes actions
/// (validating turn order, evaluating conditions, applying costs/effects
/// through the existing Effect Engine), advances turns, and ends battles
/// on team elimination. No martial-arts/magic/cultivation/weapon
/// vocabulary anywhere in this class.
///
/// Every entity passed to [startBattle] must carry a [CombatantComponent]
/// — required for both initiative ordering and win/loss grouping.
class CombatSystem {
  CombatSystem(this._context) {
    _context.events.subscribe<EntityKilled>(_onEntityKilled);
  }

  final PluginContext _context;

  /// While an `executeAction` call is applying an action's effects, the
  /// per-kill battle-end check below is suppressed — `executeAction` runs
  /// one authoritative check itself, after all of the action's effects
  /// have landed. This matters because a single action can kill
  /// multiple different-team entities in one call; checking after each
  /// individual `EntityKilled` would let the first death's check run
  /// before the second has happened, misjudging a mutual kill as a
  /// normal win. A kill from outside `executeAction` (this flag `false`)
  /// isn't part of any such batch, so it's always checked immediately.
  bool _executingAction = false;

  /// Creates a battle entity, orders [participants] by descending
  /// `CombatantComponent.initiative` (ties broken by their position in
  /// [participants]), stores its `CombatStateComponent`, and publishes
  /// `BattleStarted` then the first `TurnStarted`.
  EntityId startBattle(List<EntityId> participants) {
    final battle = _context.entities.create();
    final ordered = _byInitiative(participants);
    _context.components.add(
      battle,
      CombatStateComponent(
        participants: ordered,
        currentTurnIndex: 0,
        round: 1,
        active: true,
      ),
    );
    _context.events.publish(BattleStarted(battle, ordered));
    if (ordered.isNotEmpty) {
      _context.events.publish(TurnStarted(battle, ordered.first, 1));
    }
    return battle;
  }

  /// Runs [action] against [battle]. Throws [IllegalActionException] if
  /// [battle] isn't active or it isn't `action.actor`'s turn. If
  /// `action.conditions` don't all pass, no cost/target effects apply,
  /// but `ActionStarted`/`ActionCompleted` still publish and the turn
  /// still advances.
  void executeAction(EntityId battle, CombatAction action) {
    final initialState = _context.components.get<CombatStateComponent>(battle);
    if (initialState == null || !initialState.active) {
      throw const IllegalActionException('battle is not active');
    }
    if (initialState.participants.isEmpty ||
        initialState.participants[initialState.currentTurnIndex] !=
            action.actor) {
      throw const IllegalActionException("it is not this actor's turn");
    }

    _context.events.publish(
      ActionStarted(battle, action.actor, action.targets, action),
    );

    final actorContext = _ruleContextFor(action.actor, action);
    final conditionsPass = action.conditions
        .every((condition) => condition.evaluate(actorContext));

    _executingAction = true;
    try {
      if (conditionsPass) {
        for (final effect in action.costEffects) {
          effect.apply(actorContext);
        }
        for (final target in action.targets) {
          final targetContext = _ruleContextFor(target, action);
          for (final effect in action.effectsFor(target, _context)) {
            effect.apply(targetContext);
          }
        }
      }
    } finally {
      _executingAction = false;
    }

    _checkBattleEndFor(battle);

    _context.events.publish(
      ActionCompleted(battle, action.actor, action.targets, action),
    );

    _advanceTurn(battle);
  }

  RuleContext _ruleContextFor(EntityId subject, Object triggerEvent) =>
      RuleContext(
        subject: subject,
        triggerEvent: triggerEvent,
        entities: _context.entities,
        components: _context.components,
        events: _context.events,
        rng: _context.rng,
        eventCounts: _context.rules.eventCounts,
      );

  void _advanceTurn(EntityId battle) {
    final state = _context.components.get<CombatStateComponent>(battle);
    if (state == null) return;
    _context.events.publish(
      TurnEnded(
        battle,
        state.participants[state.currentTurnIndex],
        state.round,
      ),
    );
    if (!state.active) return;

    final living = _livingParticipants(state.participants).toSet();
    if (living.isEmpty) return;

    var nextIndex = state.currentTurnIndex;
    var round = state.round;
    EntityId next;
    do {
      nextIndex = (nextIndex + 1) % state.participants.length;
      if (nextIndex == 0) round += 1;
      next = state.participants[nextIndex];
    } while (!living.contains(next));

    _context.components.add(
      battle,
      CombatStateComponent(
        participants: state.participants,
        currentTurnIndex: nextIndex,
        round: round,
        active: true,
      ),
    );
    _context.events.publish(TurnStarted(battle, next, round));
  }

  void _onEntityKilled(EntityKilled event) {
    if (_executingAction) return;
    for (final battle
        in _context.components.entitiesWith<CombatStateComponent>()) {
      final state = _context.components.get<CombatStateComponent>(battle)!;
      if (state.active && state.participants.contains(event.id)) {
        _checkBattleEnd(battle, state);
      }
    }
  }

  void _checkBattleEndFor(EntityId battle) {
    final state = _context.components.get<CombatStateComponent>(battle);
    if (state != null && state.active) {
      _checkBattleEnd(battle, state);
    }
  }

  void _checkBattleEnd(EntityId battle, CombatStateComponent state) {
    final living = _livingParticipants(state.participants);
    final livingTeams = <String>{
      for (final id in living)
        _context.components.get<CombatantComponent>(id)!.team,
    };
    if (livingTeams.length > 1) return;

    final allTeams = <String>{
      for (final id in state.participants)
        _context.components.get<CombatantComponent>(id)!.team,
    };

    _context.components.add(
      battle,
      CombatStateComponent(
        participants: state.participants,
        currentTurnIndex: state.currentTurnIndex,
        round: state.round,
        active: false,
      ),
    );

    for (final team in allTeams) {
      if (livingTeams.contains(team)) {
        _context.events.publish(BattleWon(battle, team));
      } else {
        _context.events.publish(BattleLost(battle, team));
      }
    }
  }

  Iterable<EntityId> _livingParticipants(List<EntityId> participants) =>
      _context.queries.evaluate(participants, HealthBelowQuery(1).not());

  List<EntityId> _byInitiative(List<EntityId> participants) {
    final indexed = participants.asMap().entries.toList();
    indexed.sort((a, b) {
      final initiativeA =
          _context.components.get<CombatantComponent>(a.value)!.initiative;
      final initiativeB =
          _context.components.get<CombatantComponent>(b.value)!.initiative;
      final byInitiative = initiativeB.compareTo(initiativeA);
      if (byInitiative != 0) return byInitiative;
      return a.key.compareTo(b.key);
    });
    return [for (final entry in indexed) entry.value];
  }
}
