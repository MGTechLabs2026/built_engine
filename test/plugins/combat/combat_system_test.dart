import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
  );
}

void main() {
  group('CombatSystem.startBattle', () {
    test(
        'orders participants by descending initiative, ties by input '
        'order, and publishes BattleStarted + the first TurnStarted', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      final c = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 5));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 10));
      context.components
          .add(c, const CombatantComponent(team: 'alpha', initiative: 5));
      final started = <BattleStarted>[];
      final turnsStarted = <TurnStarted>[];
      context.events.subscribe<BattleStarted>(started.add);
      context.events.subscribe<TurnStarted>(turnsStarted.add);

      final battle = system.startBattle([a, b, c]);

      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.participants, equals([b, a, c]));
      expect(state.currentTurnIndex, equals(0));
      expect(state.round, equals(1));
      expect(state.active, isTrue);
      expect(started, hasLength(1));
      expect(started.single.participants, equals([b, a, c]));
      expect(turnsStarted, hasLength(1));
      expect(turnsStarted.single.actor, equals(b));
      expect(turnsStarted.single.round, equals(1));
    });
  });

  group('CombatSystem.executeAction — illegal use', () {
    test("throws IllegalActionException when it isn't the actor's turn", () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final action =
          AttackAction(actor: b, targets: [a], baseDamage: 10, damageStat: 'attack');

      expect(
        () => system.executeAction(battle, action),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('throws IllegalActionException when the battle is inactive', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      final battle = context.entities.create();
      context.components.add(
        battle,
        const CombatStateComponent(
          participants: [],
          currentTurnIndex: 0,
          round: 1,
          active: false,
        ),
      );
      final action =
          AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack');

      expect(
        () => system.executeAction(battle, action),
        throwsA(isA<IllegalActionException>()),
      );
    });
  });

  group('CombatSystem.executeAction — successful action', () {
    test(
        'applies cost + damage, publishes events in order, and advances '
        'the turn', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      context.components.add(a, ResourceComponent({'stamina': 20}));
      final battle = system.startBattle([a, b]);
      final log = <String>[];
      context.events.subscribe<ActionStarted>((_) => log.add('ActionStarted'));
      context.events.subscribe<EntityDamaged>((_) => log.add('EntityDamaged'));
      context.events
          .subscribe<ActionCompleted>((_) => log.add('ActionCompleted'));
      context.events.subscribe<TurnEnded>((_) => log.add('TurnEnded'));
      context.events.subscribe<TurnStarted>((_) => log.add('TurnStarted'));

      system.executeAction(
        battle,
        AttackAction(
          actor: a,
          targets: [b],
          baseDamage: 10,
          damageStat: 'attack',
          costEffects: const [ModifyResource('stamina', -5)],
        ),
      );

      expect(
        log,
        equals([
          'ActionStarted',
          'EntityDamaged',
          'ActionCompleted',
          'TurnEnded',
          'TurnStarted',
        ]),
      );
      expect(context.components.get<HealthComponent>(b)!.current, equals(90));
      expect(
        context.components.get<ResourceComponent>(a)!.resources['stamina'],
        equals(15),
      );
      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.currentTurnIndex, equals(1));
      expect(state.participants[state.currentTurnIndex], equals(b));
    });

    test(
        'failed conditions skip cost and target effects but still '
        'advance the turn', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      context.components.add(a, ResourceComponent({'stamina': 2}));
      final battle = system.startBattle([a, b]);
      final damaged = <EntityDamaged>[];
      context.events.subscribe<EntityDamaged>(damaged.add);

      system.executeAction(
        battle,
        AttackAction(
          actor: a,
          targets: [b],
          baseDamage: 10,
          damageStat: 'attack',
          conditions: const [ResourceAbove('stamina', 5)],
          costEffects: const [ModifyResource('stamina', -5)],
        ),
      );

      expect(damaged, isEmpty);
      expect(
        context.components.get<ResourceComponent>(a)!.resources['stamina'],
        equals(2),
      );
      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.currentTurnIndex, equals(1));
    });

    test(
        'a RandomChance(0.0) condition always fails, demonstrating an '
        'RNG-gated action', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final damaged = <EntityDamaged>[];
      context.events.subscribe<EntityDamaged>(damaged.add);

      system.executeAction(
        battle,
        AttackAction(
          actor: a,
          targets: [b],
          baseDamage: 10,
          damageStat: 'attack',
          conditions: const [RandomChance(0.0)],
        ),
      );

      expect(damaged, isEmpty);
    });

    test('advancing the turn skips participants with 0 health', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      final c = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 30));
      context.components
          .add(b, const CombatantComponent(team: 'alpha', initiative: 20));
      context.components
          .add(c, const CombatantComponent(team: 'beta', initiative: 10));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 0, max: 100));
      context.components.add(c, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b, c]);

      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [c], baseDamage: 5, damageStat: 'attack'),
      );

      final state = context.components.get<CombatStateComponent>(battle)!;
      expect(state.participants[state.currentTurnIndex], equals(c));
    });
  });

  group('CombatSystem — defeat and battle end', () {
    test(
        'reducing the last opposing team member to 0 health ends the '
        'battle: BattleWon/BattleLost fire, the battle goes inactive, and '
        'no further TurnStarted is published', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 10, max: 100));
      final won = <BattleWon>[];
      final lost = <BattleLost>[];
      final turnsEnded = <TurnEnded>[];
      final turnsStarted = <TurnStarted>[];
      // Subscribed before startBattle so turnsStarted captures its initial
      // TurnStarted too — the EventBus is synchronous and does not replay
      // past events to late subscribers, so subscribing after startBattle
      // would make the "only startBattle's initial one" assertion below
      // unsatisfiable by any implementation.
      context.events.subscribe<BattleWon>(won.add);
      context.events.subscribe<BattleLost>(lost.add);
      context.events.subscribe<TurnEnded>(turnsEnded.add);
      context.events.subscribe<TurnStarted>(turnsStarted.add);
      final battle = system.startBattle([a, b]);

      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(won, hasLength(1));
      expect(won.single.team, equals('alpha'));
      expect(lost, hasLength(1));
      expect(lost.single.team, equals('beta'));
      expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
      expect(turnsEnded, hasLength(1));
      expect(turnsEnded.single.actor, equals(a));
      expect(turnsStarted, hasLength(1)); // only startBattle's initial one
    });

    test('executeAction throws once the battle has ended', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 10, max: 100));
      final battle = system.startBattle([a, b]);
      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(
        () => system.executeAction(
          battle,
          AttackAction(actor: a, targets: [b], baseDamage: 1, damageStat: 'attack'),
        ),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test(
        'mutual annihilation (no living teams remain) publishes '
        'BattleLost for every team and no BattleWon', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 10, max: 100));
      context.components.add(b, const HealthComponent(current: 10, max: 100));
      final battle = system.startBattle([a, b]);
      final won = <BattleWon>[];
      final lost = <BattleLost>[];
      context.events.subscribe<BattleWon>(won.add);
      context.events.subscribe<BattleLost>(lost.add);

      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [a, b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(won, isEmpty);
      expect(lost.map((e) => e.team).toSet(), equals({'alpha', 'beta'}));
    });

    test(
        'a kill from outside executeAction (e.g. a different rule/plugin) '
        'still ends the battle', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components
          .add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components
          .add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 0, max: 100));
      final battle = system.startBattle([a, b]);
      final won = <BattleWon>[];
      context.events.subscribe<BattleWon>(won.add);

      context.events.publish(EntityKilled(b));

      expect(won, hasLength(1));
      expect(won.single.team, equals('alpha'));
      expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
    });

    test(
        'a kill in one battle caused as a side effect of an action '
        'executed in a DIFFERENT, concurrently-active battle still ends '
        'that other battle', () {
      final context = _newContext();
      final system = CombatSystem(context);

      // Battle A: p1 acts against p2 and, incidentally, q2 (a participant
      // of battle B, not battle A).
      final p1 = context.entities.create();
      final p2 = context.entities.create();
      context.components
          .add(p1, const CombatantComponent(team: 'a-alpha', initiative: 10));
      context.components
          .add(p2, const CombatantComponent(team: 'a-beta', initiative: 5));
      context.components.add(p1, const HealthComponent(current: 100, max: 100));
      context.components.add(p2, const HealthComponent(current: 100, max: 100));

      // Battle B: q1 and q2, on separate teams. q2 is one hit from death.
      final q1 = context.entities.create();
      final q2 = context.entities.create();
      context.components
          .add(q1, const CombatantComponent(team: 'b-alpha', initiative: 10));
      context.components
          .add(q2, const CombatantComponent(team: 'b-beta', initiative: 5));
      context.components.add(q1, const HealthComponent(current: 100, max: 100));
      context.components.add(q2, const HealthComponent(current: 1, max: 100));

      final battleA = system.startBattle([p1, p2]);
      final battleB = system.startBattle([q1, q2]);

      final wonB = <BattleWon>[];
      final lostB = <BattleLost>[];
      context.events.subscribe<BattleWon>((e) {
        if (e.battle == battleB) wonB.add(e);
      });
      context.events.subscribe<BattleLost>((e) {
        if (e.battle == battleB) lostB.add(e);
      });

      // Nothing stops targets from including an entity outside the
      // acting battle — executeAction only validates the actor's turn.
      system.executeAction(
        battleA,
        AttackAction(
          actor: p1,
          targets: [p2, q2],
          baseDamage: 10,
          damageStat: 'attack',
        ),
      );

      expect(wonB, hasLength(1));
      expect(wonB.single.team, equals('b-alpha'));
      expect(lostB, hasLength(1));
      expect(lostB.single.team, equals('b-beta'));
      expect(
        context.components.get<CombatStateComponent>(battleB)!.active,
        isFalse,
      );
    });
  });
}
