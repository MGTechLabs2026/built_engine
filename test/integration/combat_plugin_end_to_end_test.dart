import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

/// A minimal custom CombatAction — proves Combat's execution pipeline
/// handles healing without a dedicated "HealAction" class, and that a
/// future content plugin can add its own actions the same way.
class _DrinkAction extends CombatAction {
  const _DrinkAction({required this.actor, required this.amount});

  @override
  final EntityId actor;
  final num amount;

  @override
  List<EntityId> get targets => [actor];

  // conditions/costEffects are not overridden — CombatAction's own
  // `const []` defaults apply, since this class `extends CombatAction`.

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) =>
      [Heal(amount)];
}

PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(7);
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
  test(
      'AttackAction and a custom healing CombatAction both run through '
      'CombatSystem, using only generic components', () {
    final context = _newContext();
    final plugin = CombatPlugin();
    plugin.initialize(context);
    final system = plugin.system;

    final alpha = context.entities.create();
    final beta = context.entities.create();
    context.components
        .add(alpha, const CombatantComponent(team: 'alpha', initiative: 10));
    context.components
        .add(beta, const CombatantComponent(team: 'beta', initiative: 5));
    context.components.add(alpha, const HealthComponent(current: 30, max: 30));
    context.components.add(beta, const HealthComponent(current: 30, max: 30));

    final turnsStarted = <TurnStarted>[];
    context.events.subscribe<TurnStarted>(turnsStarted.add);

    final battle = system.startBattle([alpha, beta]);
    expect(turnsStarted.single.actor, equals(alpha));

    system.executeAction(
      battle,
      AttackAction(
        actor: alpha,
        targets: [beta],
        baseDamage: 12,
        damageStat: 'attack',
      ),
    );
    expect(context.components.get<HealthComponent>(beta)!.current, equals(18));

    system.executeAction(battle, _DrinkAction(actor: beta, amount: 5));
    expect(context.components.get<HealthComponent>(beta)!.current, equals(23));

    expect(
      turnsStarted.map((e) => e.actor).toList(),
      equals([alpha, beta, alpha]),
    );
  });

  test(
      'reducing a combatant to 0 health ends the battle with a decisive '
      'win/loss, using only generic components', () {
    final context = _newContext();
    final plugin = CombatPlugin();
    plugin.initialize(context);
    final system = plugin.system;

    final alpha = context.entities.create();
    final beta = context.entities.create();
    context.components
        .add(alpha, const CombatantComponent(team: 'alpha', initiative: 10));
    context.components
        .add(beta, const CombatantComponent(team: 'beta', initiative: 5));
    context.components.add(alpha, const HealthComponent(current: 30, max: 30));
    context.components.add(beta, const HealthComponent(current: 12, max: 30));

    final won = <BattleWon>[];
    final lost = <BattleLost>[];
    context.events.subscribe<BattleWon>(won.add);
    context.events.subscribe<BattleLost>(lost.add);

    final battle = system.startBattle([alpha, beta]);
    system.executeAction(
      battle,
      AttackAction(
        actor: alpha,
        targets: [beta],
        baseDamage: 12,
        damageStat: 'attack',
      ),
    );

    expect(context.components.get<HealthComponent>(beta)!.current, equals(0));
    expect(won.single.team, equals('alpha'));
    expect(lost.single.team, equals('beta'));
    expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
    expect(
      () => system.executeAction(
        battle,
        AttackAction(
          actor: alpha,
          targets: [beta],
          baseDamage: 1,
          damageStat: 'attack',
        ),
      ),
      throwsA(isA<IllegalActionException>()),
    );
  });
}
