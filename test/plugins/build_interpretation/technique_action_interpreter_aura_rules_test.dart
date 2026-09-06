import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/technique_plugin.dart';
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
    'id': 'venom_strike',
    'type': 'technique',
    'tags': <String>[],
    'name': 'Venom',
    'tier': 'basic',
    'properties': {'damage': 3},
    'auras': ['aura.venom'],
  });
  c.content.loadRule({
    'id': 'aura.venom',
    'trigger': 'Evt',
    'scope': 'opponent',
    'effects': [{'type': 'damage', 'amount': 1}],
  });
  return c;
}

ResolvedBuild _build(EntityId owner, {List<BuildComponentRef> hung = const [], List<BuildComponentRef> ownedOnly = const []}) =>
    ResolvedBuild(owner: owner, active: hung, owned: [...hung, ...ownedOnly]);

void main() {
  const interp = TechniqueActionInterpreter();

  test('a hung technique with an auras key contributes its AuraRule', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, hung: const [
        BuildComponentRef(referenceType: techniqueReferenceType, contentId: 'venom_strike'),
      ]),
      context: ctx,
    );
    expect(result.map((r) => r.sourceRuleId), ['aura.venom']);
    expect(result.first.scope, AuraScope.opponent);
  });

  test('an owned-but-not-hung technique contributes nothing', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, ownedOnly: const [
        BuildComponentRef(referenceType: techniqueReferenceType, contentId: 'venom_strike'),
      ]),
      context: ctx,
    );
    expect(result, isEmpty);
  });

  test('a hung item ref is ignored by the technique interpreter', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final result = interp.auraRules(
      build: _build(owner, hung: const [
        BuildComponentRef(referenceType: 'item', contentId: 'whatever'),
      ]),
      context: ctx,
    );
    expect(result, isEmpty);
  });
}
