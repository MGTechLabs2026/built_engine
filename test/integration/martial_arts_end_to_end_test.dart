import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
    content: ContentRegistry(),
  );
}

void main() {
  test(
      'Player (Boxing, Brass Knuckles, Momentum Trinket) vs. a Generic '
      'Combatant enemy — the complete combat loop', () {
    final context = _newContext();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    combat.initialize(context);
    martialArts.initialize(context);

    final player = context.entities.create();
    final enemy = context.entities.create();
    context.components
        .add(player, const CombatantComponent(team: 'player', initiative: 10));
    context.components
        .add(enemy, const CombatantComponent(team: 'enemy', initiative: 5));
    context.components.add(player, const HealthComponent(current: 100, max: 100));
    context.components.add(enemy, const HealthComponent(current: 200, max: 200));
    context.components.add(player, ResourceComponent({'momentum': 0, 'qi': 0}));

    learnStyle(player, MartialStyles.boxing, context);
    equipItem(brassKnuckles, player, context);
    equipItem(momentumTrinket, player, context);

    final battle = combat.system.startBattle([player, enemy]);

    // Round 1 — player: Jab (6 base + 6 Brass Knuckles = 12), enemy: plain
    // core AttackAction, zero martial-arts awareness.
    //
    // Momentum timing note: the trinket's regen fires on TurnStarted for
    // the PLAYER's *next* turn — which `executeAction` publishes as part
    // of advancing the turn at the end of the *enemy's* preceding call
    // (the turn wraps back to the player there). So by the time each of
    // the two calls below has returned, that round's regen has already
    // landed: momentum after startBattle's initial TurnStarted(player,
    // round 1) is 0 + 3 = 3; Jab's own costEffects then add 8 (-> 11);
    // and by the time the enemy's call returns, advancing back to the
    // player for round 2 has already fired the next regen (+3 -> 14).
    combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));
    combat.system.executeAction(
      battle,
      AttackAction(actor: enemy, targets: [player], baseDamage: 5, damageStat: 'attack'),
    );
    expect(context.components.get<HealthComponent>(enemy)!.current, equals(188));
    expect(context.components.get<HealthComponent>(player)!.current, equals(95));
    // Momentum: 0 + 3 (round-1 regen) + 8 (Jab) + 3 (round-2 regen,
    // fired by the enemy's call above advancing the turn back to the
    // player) = 14.
    expect(
      context.components.get<ResourceComponent>(player)!.resources['momentum'],
      equals(14),
    );

    // Round 2 — another Jab.
    combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));
    combat.system.executeAction(
      battle,
      AttackAction(actor: enemy, targets: [player], baseDamage: 5, damageStat: 'attack'),
    );
    expect(context.components.get<HealthComponent>(enemy)!.current, equals(176));
    // Momentum: 14 + 8 (Jab) + 3 (round-3 regen, same timing as above) = 25.
    expect(
      context.components.get<ResourceComponent>(player)!.resources['momentum'],
      equals(25),
    );

    // Round 3 — momentum is already 25 (see above), clearing Power
    // Cross's threshold (> 19): 18 base + 6 Brass Knuckles = 24 damage,
    // then spends 20 momentum, leaving 5.
    combat.system.executeAction(battle, powerCross(actor: player, targets: [enemy]));
    expect(context.components.get<HealthComponent>(enemy)!.current, equals(152));
    expect(
      context.components.get<ResourceComponent>(player)!.resources['momentum'],
      equals(5),
    );
  });

  test('Shaolin defensive synergy: mitigation heal-back while stance '
      'active, and offense boosted while it is active', () {
    final context = _newContext();
    final martialArts = MartialArtsPlugin();
    martialArts.initialize(context);
    final entity = context.entities.create();
    context.components.add(entity, const HealthComponent(current: 50, max: 100));
    context.components.add(entity, ResourceComponent({'qi': 10}));
    learnStyle(entity, MartialStyles.shaolin, context);
    final target = context.entities.create();

    // No stance yet: palmStrike does its unmodified 8.
    final unboosted = palmStrike(actor: entity, targets: [target])
        .effectsFor(target, context);
    expect((unboosted.single as Damage).amount, equals(8));

    // Activate Iron Body Stance directly (bypassing turn machinery — this
    // test targets the mechanic in isolation).
    ironBodyStance(actor: entity, targets: [entity])
        .effectsFor(entity, context)
        .single
        .apply(RuleContext(
          subject: entity,
          triggerEvent: const Object(),
          entities: context.entities,
          components: context.components,
          events: context.events,
          rng: context.rng,
          eventCounts: context.rules.eventCounts,
        ));

    // Now boosted by the +4 synergy modifier: 8 + 4 = 12.
    final boosted = palmStrike(actor: entity, targets: [target])
        .effectsFor(target, context);
    expect((boosted.single as Damage).amount, equals(12));

    // And the mitigation rule reacts to EntityDamaged with a heal-back:
    // publishing it directly (as `Damage.apply` itself would, after
    // already reducing health) starts health at 50 and Heal(2) applies,
    // landing at 52 — this asserts the rule's reaction in isolation, not
    // the full Damage-then-EntityDamaged sequence (covered elsewhere).
    context.events.publish(EntityDamaged(entity, 10));
    expect(context.components.get<HealthComponent>(entity)!.current, equals(52));
  });

  test('Tai Chi counter redirects damage from a plain, martial-arts-'
      'unaware attacker', () {
    final context = _newContext();
    final martialArts = MartialArtsPlugin();
    martialArts.initialize(context);
    final defender = context.entities.create();
    context.components.add(defender, ResourceComponent({'qi': 10}));
    learnStyle(defender, MartialStyles.taiChi, context);
    yieldingStance(actor: defender, targets: [defender])
        .effectsFor(defender, context)
        .single
        .apply(RuleContext(
          subject: defender,
          triggerEvent: const Object(),
          entities: context.entities,
          components: context.components,
          events: context.events,
          rng: context.rng,
          eventCounts: context.rules.eventCounts,
        ));

    final attacker = context.entities.create();
    context.components.add(attacker, const HealthComponent(current: 100, max: 100));
    final battle = context.entities.create();
    final plainAttack = AttackAction(
      actor: attacker, targets: [defender], baseDamage: 5, damageStat: 'attack',
    );

    context.events.publish(ActionCompleted(battle, attacker, [defender], plainAttack));

    expect(context.components.get<HealthComponent>(attacker)!.current, equals(97));
  });

  test('Tai Chi: activating Yielding Stance through the real battle '
      'pipeline does not self-damage, and the enemy IS countered on their '
      'next attack', () {
    final context = _newContext();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    combat.initialize(context);
    martialArts.initialize(context);

    final player = context.entities.create();
    final enemy = context.entities.create();
    context.components
        .add(player, const CombatantComponent(team: 'player', initiative: 10));
    context.components
        .add(enemy, const CombatantComponent(team: 'enemy', initiative: 5));
    context.components.add(player, const HealthComponent(current: 100, max: 100));
    context.components.add(enemy, const HealthComponent(current: 100, max: 100));
    context.components.add(player, ResourceComponent({'qi': 10}));
    learnStyle(player, MartialStyles.taiChi, context);

    final battle = combat.system.startBattle([player, enemy]);

    // Player's turn: activate Yielding Stance through the real pipeline.
    // Before the fix, this alone would have redirected 3 damage onto the
    // player (the stance action's own ActionCompleted targets the player,
    // who already carries stance:tai_chi by the time it fires).
    combat.system
        .executeAction(battle, yieldingStance(actor: player, targets: [player]));
    expect(context.components.get<HealthComponent>(player)!.current, equals(100));

    // Enemy's turn: a plain core AttackAction, zero martial-arts
    // awareness — should land on the player AND trigger the counter back
    // onto the enemy.
    combat.system.executeAction(
      battle,
      AttackAction(actor: enemy, targets: [player], baseDamage: 5, damageStat: 'attack'),
    );
    expect(context.components.get<HealthComponent>(player)!.current, equals(95));
    expect(context.components.get<HealthComponent>(enemy)!.current, equals(97));
  });

  test('MartialArts is removable: after unregister, Combat keeps working '
      'and MartialArts rules no longer fire', () {
    final context = _newContext();
    final manager = PluginManager();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    manager.register(combat);
    manager.register(martialArts);
    manager.initialize(context);
    manager.start(context);

    final shaolin = context.entities.create();
    context.components.add(shaolin, const HealthComponent(current: 50, max: 100));
    context.components.add(shaolin, TagSet({'stance:iron_body'}));
    // Publishing EntityDamaged directly (as Damage.apply itself would,
    // after already reducing health) starts health at 50; the mitigation
    // rule's Heal(2) is the only thing that changes it here, landing at 52.
    context.events.publish(EntityDamaged(shaolin, 10));
    expect(context.components.get<HealthComponent>(shaolin)!.current, equals(52));

    manager.stop(context);
    manager.unregister(context);

    // MartialArts' rule no longer fires post-unregister — health is
    // unchanged by this publish (it was 52, stays 52).
    context.events.publish(EntityDamaged(shaolin, 10));
    expect(context.components.get<HealthComponent>(shaolin)!.current, equals(52));

    // Combat itself runs a completely normal battle, unaffected.
    final a = context.entities.create();
    final b = context.entities.create();
    context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
    context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
    context.components.add(a, const HealthComponent(current: 30, max: 30));
    context.components.add(b, const HealthComponent(current: 12, max: 30));
    final battle = combat.system.startBattle([a, b]);
    combat.system.executeAction(
      battle,
      AttackAction(actor: a, targets: [b], baseDamage: 12, damageStat: 'attack'),
    );
    expect(context.components.get<HealthComponent>(b)!.current, equals(0));
    expect(context.components.get<CombatStateComponent>(battle)!.active, isFalse);
  });
}
