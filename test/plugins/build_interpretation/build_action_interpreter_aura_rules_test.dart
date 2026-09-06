import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
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

ResolvedBuild _emptyBuild() =>
    ResolvedBuild(owner: const EntityId(1), active: const [], owned: const []);

AuraRule _aura(String id, AuraScope scope) => AuraRule(
      rule: Rule(trigger: Object, effects: const []),
      scope: scope,
      sourceRuleId: id,
    );

class _FixedAuraInterpreter implements BuildActionInterpreter {
  const _FixedAuraInterpreter(this._auras);
  final List<AuraRule> _auras;

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) =>
      const [];

  @override
  List<AuraRule> auraRules({required ResolvedBuild build, required PluginContext context}) => _auras;
}

void main() {
  test('composite concatenates children auraRules in interpreter-list order', () {
    final composite = CompositeBuildActionInterpreter([
      _FixedAuraInterpreter([_aura('a', AuraScope.self)]),
      _FixedAuraInterpreter([_aura('b', AuraScope.opponent), _aura('c', AuraScope.self)]),
    ]);

    final result = composite.auraRules(build: _emptyBuild(), context: _ctx());

    expect(result.map((r) => r.sourceRuleId), ['a', 'b', 'c']);
  });

  test('ItemActionInterpreter and TechniqueActionInterpreter yield no auras for an empty build', () {
    final ctx = _ctx();
    expect(const ItemActionInterpreter().auraRules(build: _emptyBuild(), context: ctx), isEmpty);
    expect(const TechniqueActionInterpreter().auraRules(build: _emptyBuild(), context: ctx), isEmpty);
  });
}
