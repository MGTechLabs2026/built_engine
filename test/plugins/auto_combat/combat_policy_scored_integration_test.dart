import 'dart:io';

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/auto_combat_plugin.dart';
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
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('CombatPolicy.scored drives a full battle to victory, preferring the '
      'higher-scoring (Modifier-boosted) action every turn', () {
    final context = _newContext();
    final system = CombatSystem(context);
    final hero = context.entities.create();
    final foe = context.entities.create();
    context.components.add(hero, const CombatantComponent(team: 'hero', initiative: 10));
    context.components.add(foe, const CombatantComponent(team: 'foe', initiative: 5));
    context.components.add(hero, const HealthComponent(current: 100, max: 100));
    context.components.add(foe, const HealthComponent(current: 30, max: 30));
    // Build synergy: a Modifier (standing in for Physique + Style +
    // Technique + Item all contributing to the same stat) makes the
    // heavier attack the higher-scoring choice.
    context.modifiers.add(Modifier(
      source: const ModifierSource('build_synergy'),
      target: hero,
      stat: 'heavy',
      operation: ModifierOperation.add,
      value: 15,
    ));

    final battle = system.startBattle([hero, foe]);
    final controller = AutoCombatController(
      context: context,
      combatSystem: system,
      battle: battle,
      availableActions: [
        AttackAction(actor: hero, targets: [foe], baseDamage: 5, damageStat: 'light'),
        AttackAction(actor: hero, targets: [foe], baseDamage: 5, damageStat: 'heavy'), // scores higher
        AttackAction(actor: foe, targets: [hero], baseDamage: 3, damageStat: 'foe_attack'),
      ],
      policy: CombatPolicy.scored(),
    );

    controller.runUntilBattleEnds();

    expect(controller.isActive, isFalse);
    expect(context.components.get<HealthComponent>(foe)!.current, equals(0)); // victory
    expect(context.components.get<HealthComponent>(hero)!.current, greaterThan(0));
  });

  test('CombatPolicy.scored still results in defeat when the opponent is simply stronger', () {
    final context = _newContext();
    final system = CombatSystem(context);
    final hero = context.entities.create();
    final foe = context.entities.create();
    context.components.add(hero, const CombatantComponent(team: 'hero', initiative: 5));
    context.components.add(foe, const CombatantComponent(team: 'foe', initiative: 10));
    context.components.add(hero, const HealthComponent(current: 20, max: 20));
    context.components.add(foe, const HealthComponent(current: 200, max: 200));

    final battle = system.startBattle([hero, foe]);
    final controller = AutoCombatController(
      context: context,
      combatSystem: system,
      battle: battle,
      availableActions: [
        AttackAction(actor: hero, targets: [foe], baseDamage: 1, damageStat: 'weak'),
        AttackAction(actor: foe, targets: [hero], baseDamage: 50, damageStat: 'strong'),
      ],
      policy: CombatPolicy.scored(),
    );

    controller.runUntilBattleEnds();

    expect(controller.isActive, isFalse);
    expect(context.components.get<HealthComponent>(hero)!.current, equals(0)); // defeat
  });

  test('AutoCombat has no direct Tome dependency: no file under '
      'lib/src/plugins/auto_combat/ references ActiveBuild/BuildComponentRef/TomeService', () {
    final files = Directory('lib/src/plugins/auto_combat')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final forbidden in ['ActiveBuild', 'BuildComponentRef', 'TomeService', 'tome_']) {
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains(forbidden)),
          reason: '${file.path} must not reference "$forbidden"',
        );
      }
    }
  });
}
