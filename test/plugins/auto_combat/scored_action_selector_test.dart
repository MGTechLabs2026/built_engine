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

class _PriorityAction extends CombatAction {
  const _PriorityAction({required this.actor, required this.targets, required num priorityValue})
      : _priorityValue = priorityValue;

  @override
  final EntityId actor;
  @override
  final List<EntityId> targets;
  final num _priorityValue;

  @override
  num get priority => _priorityValue;

  @override
  List<Effect> effectsFor(EntityId target, PluginContext context) => const [];
}

void main() {
  const selector = ScoredActionSelector();

  test('action priority: higher-priority action wins when nothing else differs', () {
    final context = _newContext();
    final actor = context.entities.create();
    final target = context.entities.create();
    final low = _PriorityAction(actor: actor, targets: [target], priorityValue: 1);
    final high = _PriorityAction(actor: actor, targets: [target], priorityValue: 5);

    final chosen = selector.selectAction(actor, [low, high], null, context);

    expect(chosen, same(high));
  });

  test('deterministic tie-break: equal scores keep the earliest-listed action', () {
    final context = _newContext();
    final actor = context.entities.create();
    final target = context.entities.create();
    final first = _PriorityAction(actor: actor, targets: [target], priorityValue: 3);
    final second = _PriorityAction(actor: actor, targets: [target], priorityValue: 3);

    final chosenOnce = selector.selectAction(actor, [first, second], null, context);
    final chosenAgain = selector.selectAction(actor, [first, second], null, context);

    expect(chosenOnce, same(first));
    expect(chosenAgain, same(first));
  });

  test('multiple actions: the preferred target receives a scoring bonus', () {
    final context = _newContext();
    final actor = context.entities.create();
    final preferred = context.entities.create();
    final other = context.entities.create();
    final atOther = _PriorityAction(actor: actor, targets: [other], priorityValue: 3);
    final atPreferred = _PriorityAction(actor: actor, targets: [preferred], priorityValue: 3);

    final chosen = selector.selectAction(actor, [atOther, atPreferred], preferred, context);

    expect(chosen, same(atPreferred));
  });

  test('resource constraints: an unaffordable action is skipped in favor of an affordable one', () {
    final context = _newContext();
    context.resources.define(const ResourceDefinition(id: 'mana', max: 100));
    final actor = context.entities.create();
    final target = context.entities.create();
    // actor has 0 mana
    final expensive = AttackAction(
      actor: actor,
      targets: [target],
      baseDamage: 999, // would score highest if affordability weren't checked
      damageStat: 'power',
      costEffects: const [ConsumeResource('mana', 50)],
    );
    final cheap = AttackAction(actor: actor, targets: [target], baseDamage: 5, damageStat: 'power');

    final chosen = selector.selectAction(actor, [expensive, cheap], null, context);

    expect(chosen, same(cheap));
  });

  test('an affordable action with sufficient resources is chosen over a cheaper one when it scores higher', () {
    final context = _newContext();
    context.resources.define(const ResourceDefinition(id: 'mana', max: 100));
    final actor = context.entities.create();
    context.components.add(actor, ResourceComponent({'mana': 100}));
    final target = context.entities.create();
    final powerful = AttackAction(
      actor: actor,
      targets: [target],
      baseDamage: 50,
      damageStat: 'power',
      costEffects: const [ConsumeResource('mana', 50)],
    );
    final weak = AttackAction(actor: actor, targets: [target], baseDamage: 5, damageStat: 'power');

    final chosen = selector.selectAction(actor, [weak, powerful], null, context);

    expect(chosen, same(powerful));
  });

  test('illegal action rejection: an action whose conditions fail is skipped when an alternative exists', () {
    final context = _newContext();
    final actor = context.entities.create();
    final target = context.entities.create();
    final blocked = AttackAction(
      actor: actor,
      targets: [target],
      baseDamage: 999,
      damageStat: 'power',
      conditions: const [RandomChance(0.0)], // always fails
    );
    final open = AttackAction(actor: actor, targets: [target], baseDamage: 5, damageStat: 'power');

    final chosen = selector.selectAction(actor, [blocked, open], null, context);

    expect(chosen, same(open));
  });

  test('build modifier affects choice: a Modifier boosting one action\'s damageStat '
      'makes AutoCombat prefer it over an equal-baseDamage alternative', () {
    final context = _newContext();
    final actor = context.entities.create();
    final target = context.entities.create();
    final a = AttackAction(actor: actor, targets: [target], baseDamage: 5, damageStat: 'stat_a');
    final b = AttackAction(actor: actor, targets: [target], baseDamage: 5, damageStat: 'stat_b');
    // Simulates build synergy (Physique + Style + Technique + Item all
    // contributing modifiers to the same stat) via the real Modifier
    // Engine — no special-casing of any content in the scorer itself.
    context.modifiers.add(Modifier(
      source: const ModifierSource('build_synergy'),
      target: actor,
      stat: 'stat_b',
      operation: ModifierOperation.add,
      value: 20,
    ));

    final chosen = selector.selectAction(actor, [a, b], null, context);

    expect(chosen, same(b));
  });

  test('an unaffordable action still executes without throwing if it is the only option', () {
    final context = _newContext();
    context.resources.define(const ResourceDefinition(id: 'mana', max: 100));
    final actor = context.entities.create();
    final target = context.entities.create();
    final onlyOption = AttackAction(
      actor: actor,
      targets: [target],
      baseDamage: 10,
      damageStat: 'power',
      costEffects: const [ConsumeResource('mana', 50)],
    );

    expect(
      () => selector.selectAction(actor, [onlyOption], null, context),
      returnsNormally,
    );
  });
}
