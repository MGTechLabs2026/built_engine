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
  group('CombatPlugin', () {
    test('has id "combat", a version, and no dependencies', () {
      final plugin = CombatPlugin();
      expect(plugin.id, equals('combat'));
      expect(plugin.version, isNotEmpty);
      expect(plugin.dependencies, isEmpty);
    });

    test('initialize constructs a usable CombatSystem', () {
      final plugin = CombatPlugin();
      final context = _newContext();

      plugin.initialize(context);

      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha'));
      context.components.add(b, const CombatantComponent(team: 'beta'));

      final battle = plugin.system.startBattle([a, b]);

      expect(context.components.has<CombatStateComponent>(battle), isTrue);
    });

    test(
        'registers, initializes, starts, stops, and unregisters through '
        'PluginManager with no other plugin present', () {
      final context = _newContext();
      final manager = PluginManager();
      final plugin = CombatPlugin();
      manager.register(plugin);

      manager.initialize(context);
      manager.start(context);

      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha'));
      context.components.add(b, const CombatantComponent(team: 'beta'));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = plugin.system.startBattle([a, b]);
      plugin.system.executeAction(
        battle,
        AttackAction(actor: a, targets: [b], baseDamage: 10, damageStat: 'attack'),
      );

      expect(context.components.get<HealthComponent>(b)!.current, equals(90));
      expect(() => manager.stop(context), returnsNormally);
      expect(() => manager.unregister(context), returnsNormally);
    });

    test(
        'after stop + unregister, CombatSystem no longer reacts to '
        'EntityKilled for a still-active battle', () {
      final context = _newContext();
      final manager = PluginManager();
      final plugin = CombatPlugin();
      manager.register(plugin);

      manager.initialize(context);
      manager.start(context);

      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha'));
      context.components.add(b, const CombatantComponent(team: 'beta'));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = plugin.system.startBattle([a, b]);
      expect(context.components.get<CombatStateComponent>(battle)!.active, isTrue);

      manager.stop(context);
      manager.unregister(context);

      final won = <BattleWon>[];
      final lost = <BattleLost>[];
      context.events.subscribe<BattleWon>(won.add);
      context.events.subscribe<BattleLost>(lost.add);

      context.events.publish(EntityKilled(b));

      expect(won, isEmpty);
      expect(lost, isEmpty);
      expect(context.components.get<CombatStateComponent>(battle)!.active, isTrue);
    });
  });
}
