import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt(this.actor);
  final EntityId actor;
}

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
  c.content.registerTrigger('Evt', _Evt, (e) => (e as _Evt).actor);
  c.content.load({
    'id': 'boots_of_regen',
    'type': 'footwear',
    'tags': <String>[],
    'properties': {'attack': 1},
    'auras': ['aura.step_heal'],
  });
  c.content.loadRule({
    'id': 'aura.step_heal',
    'trigger': 'Evt',
    'effects': [{'type': 'heal', 'amount': 2}],
  });
  return c;
}

ResolvedBuild _build(EntityId owner, {List<BuildComponentRef> hung = const [], List<BuildComponentRef> ownedOnly = const []}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

void main() {
  const interp = ItemActionInterpreter();

  test('a hung item with an auras key contributes its AuraRule', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, hung: const [
        BuildComponentRef(referenceType: itemReferenceType, contentId: 'boots_of_regen'),
      ]),
      context: ctx,
    );
    expect(result.map((r) => r.sourceRuleId), ['aura.step_heal']);
  });

  test('an owned-but-not-hung item contributes nothing', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, ownedOnly: const [
        BuildComponentRef(referenceType: itemReferenceType, contentId: 'boots_of_regen'),
      ]),
      context: ctx,
    );
    expect(result, isEmpty);
  });

  test('a hung technique ref is ignored by the item interpreter', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, hung: const [
        BuildComponentRef(referenceType: 'technique', contentId: 'whatever'),
      ]),
      context: ctx,
    );
    expect(result, isEmpty);
  });
}
