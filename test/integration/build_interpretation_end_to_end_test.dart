import 'package:build_engine/auto_combat_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

/// Proves the real target pipeline end to end, with the real
/// `TechniquePlugin`/`ItemPlugin` content — no hardcoded damage table, no
/// technique-name switch:
///
///   Tome -> ActiveBuild -> Build Interpreter -> Available Actions ->
///   AutoCombat -> CombatSystem
PluginContext _newContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
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
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}

void main() {
  test(
      'Tome -> ActiveBuild -> Build Interpreter -> Available Actions -> '
      'AutoCombat -> CombatSystem, using the real Technique/Item plugins', () {
    final context = _newContext();
    final combat = CombatPlugin()..initialize(context);
    TechniquePlugin().initialize(context);
    ItemPlugin().initialize(context);

    final character = context.entities.create();
    context.components.add(character, const CombatantComponent(team: 'player', initiative: 10));
    context.components.add(character, const HealthComponent(current: 100, max: 100));
    final enemy = context.entities.create();
    context.components.add(enemy, const CombatantComponent(team: 'enemy', initiative: 1));
    context.components.add(enemy, const HealthComponent(current: 50, max: 50));

    // Learn Basic Punch (LEARNED, not just discovered/LOCKED) and own/
    // discover Gloves — the real lifecycle gates, not a shortcut.
    final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
    discoverTechnique(character, basicPunch, context);
    final learning = attemptToLearnTechnique(character, basicPunch, 10, context);
    expect(learning.learned, isTrue);

    final gloves = itemDefinition(ItemIds.gloves, context);
    discoverItem(character, gloves, context);
    expect(isItemUsable(character, gloves, context), isTrue);

    // Real Tome, real ActiveBuild.
    context.tome.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['weapon', 'technique']),
    );
    context.tome.createTome(character, 'basic_tome');
    addTechniqueToTome(character, const SlotId('technique'), basicPunch, context);
    addItemToTome(character, const SlotId('weapon'), gloves, context);
    final build = context.tome.resolve(character, ownedRefs: const []);
    expect(build.active, hasLength(2));

    // Real Build Interpreter -> Available Actions.
    const interpreter = CompositeBuildActionInterpreter([
      TechniqueActionInterpreter(),
      ItemActionInterpreter(),
    ]);
    final playerActions = interpreter.interpret(
      build: build.asActiveBuild,
      actor: character,
      targets: [enemy],
      context: context,
    );
    // Gloves ('fist') contributes a modifier, not a standalone action —
    // only Basic Punch's AttackAction is available.
    expect(playerActions, hasLength(1));
    final punch = playerActions.single as AttackAction;

    // The item's contribution is real: gloves boost the exact stat Basic
    // Punch's AttackAction reads, resolved through the existing Modifier
    // Engine at execution time.
    final resolvedEffects = punch.effectsFor(enemy, context);
    expect((resolvedEffects.single as Damage).amount, equals(7)); // 6 (punch) + 1 (gloves)

    // Real AutoCombat -> real CombatSystem.
    final battle = combat.system.startBattle([character, enemy]);
    final controller = AutoCombatController(
      context: context,
      combatSystem: combat.system,
      battle: battle,
      availableActions: [
        ...playerActions,
        AttackAction(actor: enemy, targets: [character], baseDamage: 1, damageStat: 'enemy_attack'),
      ],
    );
    controller.runUntilBattleEnds();

    expect(context.components.get<HealthComponent>(enemy)!.current, lessThan(50));
    expect(controller.isActive, isFalse);
  });

  test('deterministic: interpreting and running the same build twice yields the same outcome', () {
    (num, bool) runOnce() {
      final context = _newContext();
      final combat = CombatPlugin()..initialize(context);
      TechniquePlugin().initialize(context);
      ItemPlugin().initialize(context);

      final character = context.entities.create();
      context.components.add(character, const CombatantComponent(team: 'player', initiative: 10));
      context.components.add(character, const HealthComponent(current: 100, max: 100));
      final enemy = context.entities.create();
      context.components.add(enemy, const CombatantComponent(team: 'enemy', initiative: 1));
      context.components.add(enemy, const HealthComponent(current: 50, max: 50));

      final basicPunch = techniqueDefinition(TechniqueIds.basicPunch, context);
      discoverTechnique(character, basicPunch, context);
      attemptToLearnTechnique(character, basicPunch, 10, context);
      context.tome.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['technique']),
      );
      context.tome.createTome(character, 'basic_tome');
      addTechniqueToTome(character, const SlotId('technique'), basicPunch, context);
      final build = context.tome.resolve(character, ownedRefs: const []);

      const interpreter = TechniqueActionInterpreter();
      final actions = interpreter.interpret(
        build: build.asActiveBuild,
        actor: character,
        targets: [enemy],
        context: context,
      );

      final battle = combat.system.startBattle([character, enemy]);
      final controller = AutoCombatController(
        context: context,
        combatSystem: combat.system,
        battle: battle,
        availableActions: [
          ...actions,
          AttackAction(actor: enemy, targets: [character], baseDamage: 1, damageStat: 'enemy_attack'),
        ],
      );
      controller.runUntilBattleEnds();

      return (
        context.components.get<HealthComponent>(enemy)!.current,
        controller.isActive,
      );
    }

    expect(runOnce(), equals(runOnce()));
  });
}
