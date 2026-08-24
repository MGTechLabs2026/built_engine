import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

/// Proves `CombatSystem` still runs a full battle entirely on its own —
/// no Tome, no `ActiveBuild`, no build interpreter, no Technique/Item
/// plugin — exactly as it did before this milestone. Nothing under
/// `lib/src/plugins/combat/` was modified to add build interpretation.
void main() {
  test('CombatSystem runs a battle to completion using only hand-built CombatActions', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final context = PluginContext(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: ModifierCollection(),
      content: ContentRegistry(),
    );
    final combat = CombatSystem(context);

    final attacker = entities.create();
    final defender = entities.create();
    components.add(attacker, const CombatantComponent(team: 'a', initiative: 10));
    components.add(defender, const CombatantComponent(team: 'b', initiative: 1));
    components.add(attacker, const HealthComponent(current: 20, max: 20));
    components.add(defender, const HealthComponent(current: 10, max: 10));

    final battle = combat.startBattle([attacker, defender]);
    combat.executeAction(
      battle,
      AttackAction(actor: attacker, targets: [defender], baseDamage: 10, damageStat: 'power'),
    );

    expect(components.get<HealthComponent>(defender)!.current, equals(0));
    combat.dispose();
  });
}
