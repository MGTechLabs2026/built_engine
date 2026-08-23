import 'package:build_engine/build_engine.dart';
import 'package:build_engine/example_elemental_plugin.dart';
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
  test(
      'all three definitions load atomically with the custom factories '
      'registered', () {
    final context = _newContext();
    final sdk = PluginSdk(context);
    sdk.registerEffect(
      'applyElementalStatus',
      (p) => ApplyElementalStatus(ContentField.requireString(p, 'element')),
    );
    sdk.registerCondition(
      'hasElementalAffinity',
      (p) => HasElementalAffinity(
        ContentField.requireString(p, 'element'),
        ContentField.requireNum(p, 'threshold'),
      ),
    );

    final definitions = sdk.registerContentBatch(elementalContentDefinitions);

    expect(definitions, hasLength(3));
    final fireball = context.content.get('fireball');
    expect(fireball.costEffects.single, isA<ModifyResource>());
    expect(fireball.conditions.single, isA<HasElementalAffinity>());
    expect(fireball.effects, hasLength(2));
    expect(fireball.effects[0], isA<Damage>());
    expect(fireball.effects[1], isA<ApplyElementalStatus>());
  });
}
