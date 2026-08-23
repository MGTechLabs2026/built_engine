import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/auto_combat_plugin.dart';
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
  group('auto combat starts', () {
    test('step() executes one legal action and advances the turn', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final controller = AutoCombatController(
        context: context,
        combatSystem: system,
        battle: battle,
        availableActions: [
          AttackAction(actor: a, targets: [b], baseDamage: 40, damageStat: 'attack'),
          AttackAction(actor: b, targets: [a], baseDamage: 20, damageStat: 'attack'),
        ],
      );

      final acted = controller.step();

      expect(acted, isTrue);
      expect(context.components.get<HealthComponent>(b)!.current, equals(60));
    });
  });

  group('selects legal action / does not select illegal action', () {
    test('only executes the action belonging to whoever\'s turn it is', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final controller = AutoCombatController(
        context: context,
        combatSystem: system,
        battle: battle,
        availableActions: [
          AttackAction(actor: a, targets: [b], baseDamage: 40, damageStat: 'attack'),
          AttackAction(actor: b, targets: [a], baseDamage: 20, damageStat: 'attack'),
        ],
      );

      controller.step(); // a's turn: only a's action may fire

      expect(context.components.get<HealthComponent>(a)!.current, equals(100));
      expect(context.components.get<HealthComponent>(b)!.current, equals(60));
    });

    test('ignores an available action whose target is already dead', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      final corpse = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(corpse, const CombatantComponent(team: 'beta', initiative: 1));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      context.components.add(corpse, const HealthComponent(current: 0, max: 100));
      final battle = system.startBattle([a, b, corpse]);
      final controller = AutoCombatController(
        context: context,
        combatSystem: system,
        battle: battle,
        availableActions: [
          // Listed first, but illegal (dead target) - must be skipped.
          AttackAction(actor: a, targets: [corpse], baseDamage: 999, damageStat: 'attack'),
          AttackAction(actor: a, targets: [b], baseDamage: 40, damageStat: 'attack'),
        ],
      );

      controller.step();

      expect(context.components.get<HealthComponent>(b)!.current, equals(60));
    });

    test('no-ops (does not throw) when the current actor has no legal action',
        () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final controller = AutoCombatController(
        context: context,
        combatSystem: system,
        battle: battle,
        availableActions: const [], // nothing available for anyone
      );

      final acted = controller.step();

      expect(acted, isFalse);
    });
  });

  group('deterministic sequence', () {
    test('the same setup always produces the same actor/action sequence', () {
      List<EntityId> runOnce() {
        final context = _newContext();
        final system = CombatSystem(context);
        final a = context.entities.create();
        final b = context.entities.create();
        context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
        context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
        context.components.add(a, const HealthComponent(current: 100, max: 100));
        context.components.add(b, const HealthComponent(current: 100, max: 100));
        final battle = system.startBattle([a, b]);
        final actorLog = <EntityId>[];
        context.events.subscribe<ActionCompleted>((e) => actorLog.add(e.actor));
        final controller = AutoCombatController(
          context: context,
          combatSystem: system,
          battle: battle,
          availableActions: [
            AttackAction(actor: a, targets: [b], baseDamage: 40, damageStat: 'attack'),
            AttackAction(actor: b, targets: [a], baseDamage: 20, damageStat: 'attack'),
          ],
        );
        controller.runUntilBattleEnds();
        return actorLog;
      }

      final sequenceA = runOnce();
      final sequenceB = runOnce();

      expect(sequenceA, isNotEmpty);
      expect(sequenceA.map((id) => id.value), equals(sequenceB.map((id) => id.value)));
    });
  });

  group('stops on victory/loss', () {
    test('runUntilBattleEnds stops once one team is eliminated, and further '
        'steps are no-ops', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);
      final won = <BattleWon>[];
      context.events.subscribe<BattleWon>(won.add);
      final controller = AutoCombatController(
        context: context,
        combatSystem: system,
        battle: battle,
        availableActions: [
          AttackAction(actor: a, targets: [b], baseDamage: 40, damageStat: 'attack'),
          AttackAction(actor: b, targets: [a], baseDamage: 20, damageStat: 'attack'),
        ],
      );

      controller.runUntilBattleEnds();

      expect(controller.isActive, isFalse);
      expect(won.single.team, equals('alpha'));
      expect(controller.step(), isFalse); // no-op once ended
    });
  });

  group('CombatSystem remains independently usable', () {
    test('CombatSystem still works without any AutoCombat involvement', () {
      final context = _newContext();
      final system = CombatSystem(context);
      final a = context.entities.create();
      final b = context.entities.create();
      context.components.add(a, const CombatantComponent(team: 'alpha', initiative: 10));
      context.components.add(b, const CombatantComponent(team: 'beta', initiative: 5));
      context.components.add(a, const HealthComponent(current: 100, max: 100));
      context.components.add(b, const HealthComponent(current: 100, max: 100));
      final battle = system.startBattle([a, b]);

      system.executeAction(
        battle,
        AttackAction(actor: a, targets: [b], baseDamage: 30, damageStat: 'attack'),
      );

      expect(context.components.get<HealthComponent>(b)!.current, equals(70));
    });
  });
}
