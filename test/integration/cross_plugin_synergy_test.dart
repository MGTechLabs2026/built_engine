import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/elemental_plugin.dart';
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
  test('D: Elemental + Combat works, MartialArts absent', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(CombatPlugin());
    manager.register(ElementalPlugin());
    manager.initialize(context);
    manager.start(context);

    final caster = context.entities.create();
    attuneToElement(caster, Elements.fire, 1, context);
    context.components.add(caster, ResourceComponent({'mana': 10}));
    final target = context.entities.create();
    context.components.add(
      target,
      const HealthComponent(current: 100, max: 100),
    );

    final fireball = context.content.get('fireball');
    expect(
      fireball.conditions.every(
        (c) => c.evaluate(context.ruleContextFor(caster)),
      ),
      isTrue,
    );
    for (final cost in fireball.costEffects) {
      cost.apply(context.ruleContextFor(caster));
    }
    for (final effect in fireball.effects) {
      effect.apply(context.ruleContextFor(target));
    }
    expect(
      context.components.get<HealthComponent>(target)!.current,
      equals(88),
    );

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test('E: MartialArts + Elemental + Combat works, and a martial '
      'attack gains a generic fire-modifier synergy bonus', () {
    final context = _newContext();
    final manager = PluginManager();
    final combat = CombatPlugin();
    manager.register(combat);
    manager.register(MartialArtsPlugin());
    manager.register(ElementalPlugin());
    manager.initialize(context);
    manager.start(context);

    final baseline = context.entities.create();
    final baselineTarget = context.entities.create();
    context.components.add(
      baseline,
      const CombatantComponent(team: 'a', initiative: 10),
    );
    context.components.add(
      baselineTarget,
      const CombatantComponent(team: 'b', initiative: 1),
    );
    context.components.add(
      baseline,
      const HealthComponent(current: 100, max: 100),
    );
    context.components.add(
      baselineTarget,
      const HealthComponent(current: 100, max: 100),
    );
    learnStyle(baseline, MartialStyles.boxing, context);
    final battleBaseline = combat.system.startBattle([
      baseline,
      baselineTarget,
    ]);
    combat.system.executeAction(
      battleBaseline,
      jab(actor: baseline, targets: [baselineTarget]),
    );
    expect(
      context.components.get<HealthComponent>(baselineTarget)!.current,
      equals(94),
    );

    final enchanted = context.entities.create();
    final enchantedTarget = context.entities.create();
    context.components.add(
      enchanted,
      const CombatantComponent(team: 'a', initiative: 10),
    );
    context.components.add(
      enchantedTarget,
      const CombatantComponent(team: 'b', initiative: 1),
    );
    context.components.add(
      enchanted,
      const HealthComponent(current: 100, max: 100),
    );
    context.components.add(
      enchantedTarget,
      const HealthComponent(current: 100, max: 100),
    );
    learnStyle(enchanted, MartialStyles.boxing, context);
    equipElementalItem(emberCharm, enchanted, context);
    final battleEnchanted = combat.system.startBattle([
      enchanted,
      enchantedTarget,
    ]);
    combat.system.executeAction(
      battleEnchanted,
      jab(actor: enchanted, targets: [enchantedTarget]),
    );

    // The generic synergy: same jab, same baseDamage (6), but the
    // enchanted attacker's ember_charm Modifier (+4 add punch) is
    // resolved by MartialTechniqueAction.effectsFor through the same
    // Modifier Engine mechanism Shaolin's own iron-body synergy uses —
    // 6 + 4 = 10, dealt entirely through generic engine primitives, with
    // neither plugin's source referencing the other.
    expect(
      context.components.get<HealthComponent>(enchantedTarget)!.current,
      equals(90),
    );

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test('F: removing Elemental does not break MartialArts', () {
    final context = _newContext();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    final elemental = ElementalPlugin();
    combat.initialize(context);
    martialArts.initialize(context);
    elemental.initialize(context);

    elemental.unregister(context);

    final player = context.entities.create();
    final enemy = context.entities.create();
    context.components.add(
      player,
      const CombatantComponent(team: 'player', initiative: 10),
    );
    context.components.add(
      enemy,
      const CombatantComponent(team: 'enemy', initiative: 5),
    );
    context.components.add(
      player,
      const HealthComponent(current: 100, max: 100),
    );
    context.components.add(
      enemy,
      const HealthComponent(current: 100, max: 100),
    );
    learnStyle(player, MartialStyles.boxing, context);
    final battle = combat.system.startBattle([player, enemy]);
    combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));

    expect(context.components.get<HealthComponent>(enemy)!.current, equals(94));
  });

  test('F (mirror): removing MartialArts does not break Elemental', () {
    final context = _newContext();
    final combat = CombatPlugin();
    final martialArts = MartialArtsPlugin();
    final elemental = ElementalPlugin();
    combat.initialize(context);
    martialArts.initialize(context);
    elemental.initialize(context);

    martialArts.unregister(context);

    final caster = context.entities.create();
    attuneToElement(caster, Elements.fire, 1, context);
    context.components.add(caster, ResourceComponent({'mana': 10}));
    final target = context.entities.create();
    context.components.add(
      target,
      const HealthComponent(current: 100, max: 100),
    );

    final fireball = context.content.get('fireball');
    for (final cost in fireball.costEffects) {
      cost.apply(context.ruleContextFor(caster));
    }
    for (final effect in fireball.effects) {
      effect.apply(context.ruleContextFor(target));
    }
    expect(
      context.components.get<HealthComponent>(target)!.current,
      equals(88),
    );

    // Elemental's own "water conducts" rule must also still fire
    // — proves its rules survive MartialArts' removal, not just its
    // content lookups.
    final soaked = context.entities.create();
    context.components.add(soaked, const HealthComponent(current: 50, max: 50));
    context.components.add(soaked, StatusComponent({'status:soaked'}));
    context.events.publish(EntityDamaged(soaked, 5));
    expect(
      context.components.get<StatusComponent>(soaked)!.activeStatuses,
      contains('status:shocked'),
    );
  });
}
