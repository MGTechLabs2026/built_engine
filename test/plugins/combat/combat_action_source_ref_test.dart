import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/src/plugins/build_interpretation/self_effect_action.dart';
import 'package:test/test.dart';

const _ref = BuildComponentRef(
  referenceType: 'technique',
  contentId: 'basic_punch',
  instanceEntityId: EntityId(42),
);

void main() {
  test('CombatAction.sourceRef defaults to null', () {
    const action = SelfEffectAction(actor: EntityId(1));
    expect(action.sourceRef, isNull);
  });

  test('AttackAction carries a sourceRef when given one', () {
    const action = AttackAction(
      actor: EntityId(1),
      targets: [EntityId(2)],
      baseDamage: 5,
      damageStat: 'fist',
      sourceRef: _ref,
    );
    expect(action.sourceRef, same(_ref));
  });

  test('SelfEffectAction carries a sourceRef when given one', () {
    const action = SelfEffectAction(actor: EntityId(1), sourceRef: _ref);
    expect(action.sourceRef, same(_ref));
  });

  test('sourceRef does not change effectsFor output (behaviour-neutral)', () {
    final ctx = _newCombatContext();
    const withRef = AttackAction(
      actor: EntityId(1), targets: [EntityId(2)],
      baseDamage: 7, damageStat: 'fist', sourceRef: _ref,
    );
    const withoutRef = AttackAction(
      actor: EntityId(1), targets: [EntityId(2)],
      baseDamage: 7, damageStat: 'fist',
    );
    final a = withRef.effectsFor(const EntityId(2), ctx);
    final b = withoutRef.effectsFor(const EntityId(2), ctx);
    expect(a.map((e) => e.toString()), b.map((e) => e.toString()));
  });
}

PluginContext _newCombatContext() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  return PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}
