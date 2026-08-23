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
  group('MartialArtsPlugin', () {
    test('has id "martial_arts", a version, and depends on "combat"', () {
      final plugin = MartialArtsPlugin();
      expect(plugin.id, equals('martial_arts'));
      expect(plugin.version, isNotEmpty);
      expect(plugin.dependencies, equals(['combat']));
    });

    test('initialize registers all 4 rules', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();

      plugin.initialize(context);

      final entity = context.entities.create();
      context.components.add(entity, TagSet({'stance:iron_body'}));
      context.components.add(entity, const HealthComponent(current: 50, max: 100));
      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(52));
    });

    test('unregister cancels every rule subscription — MartialArts stops '
        'reacting to events entirely', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);
      final entity = context.entities.create();
      context.components.add(entity, TagSet({'stance:iron_body'}));
      context.components.add(entity, const HealthComponent(current: 50, max: 100));

      plugin.unregister(context);
      context.events.publish(EntityDamaged(entity, 10));

      expect(context.components.get<HealthComponent>(entity)!.current, equals(50));
    });

    test('registers, initializes, starts, stops, and unregisters through '
        'PluginManager alongside CombatPlugin with no other plugin present',
        () {
      final context = _newContext();
      final manager = PluginManager();
      final combat = CombatPlugin();
      final martialArts = MartialArtsPlugin();
      manager.register(combat);
      manager.register(martialArts);

      manager.initialize(context);
      manager.start(context);

      final player = context.entities.create();
      final enemy = context.entities.create();
      context.components.add(player, const CombatantComponent(team: 'player', initiative: 10));
      context.components.add(enemy, const CombatantComponent(team: 'enemy', initiative: 5));
      context.components.add(player, const HealthComponent(current: 100, max: 100));
      context.components.add(enemy, const HealthComponent(current: 100, max: 100));
      learnStyle(player, MartialStyles.boxing, context);
      final battle = combat.system.startBattle([player, enemy]);
      combat.system.executeAction(battle, jab(actor: player, targets: [enemy]));

      expect(context.components.get<HealthComponent>(enemy)!.current, equals(94));
      expect(() => manager.stop(context), returnsNormally);
      expect(() => manager.unregister(context), returnsNormally);
    });

    test('removes MartialLoadoutComponent when its entity is destroyed', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);

      final wearer = context.entities.create();
      equipItem(brassKnuckles, wearer, context);
      expect(context.components.has<MartialLoadoutComponent>(wearer), isTrue);

      context.entities.destroy(wearer);

      expect(context.components.has<MartialLoadoutComponent>(wearer), isFalse);
    });

    test('component cleanup stops after unregister', () {
      final context = _newContext();
      final plugin = MartialArtsPlugin();
      plugin.initialize(context);

      final wearer = context.entities.create();
      equipItem(brassKnuckles, wearer, context);

      plugin.unregister(context);
      context.entities.destroy(wearer);

      expect(context.components.has<MartialLoadoutComponent>(wearer), isTrue);
    });
  });
}
