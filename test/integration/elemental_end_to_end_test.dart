import 'package:build_engine/build_engine.dart';
import 'package:build_engine/elemental_plugin.dart';
import 'package:test/test.dart';

void main() {
  test(
      'ElementalPlugin runs standalone (no Combat, no MartialArts) '
      'and is fully removable', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final context = PluginContext(
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

    final manager = PluginManager();
    manager.register(ElementalPlugin());
    manager.initialize(context);
    manager.start(context);

    final caster = entities.create();
    final target = entities.create();
    attuneToElement(caster, Elements.fire, 1, context);
    components.add(caster, ResourceComponent({'mana': 10}));
    components.add(target, const HealthComponent(current: 100, max: 100));

    RuleContext contextFor(EntityId subject) => RuleContext(
          subject: subject,
          triggerEvent: const Object(),
          entities: entities,
          components: components,
          events: events,
          rng: rng,
          eventCounts: EventCounter(events),
        );

    final fireball = context.content.get('fireball');
    final qualifies =
        fireball.conditions.every((c) => c.evaluate(contextFor(caster)));
    expect(qualifies, isTrue);

    for (final cost in fireball.costEffects) {
      cost.apply(contextFor(caster));
    }
    expect(components.get<ResourceComponent>(caster)!.resources['mana'],
        equals(6));

    for (final effect in fireball.effects) {
      effect.apply(contextFor(target));
    }
    expect(components.get<HealthComponent>(target)!.current, equals(88));
    expect(components.get<StatusComponent>(target)!.activeStatuses,
        contains('status:burning'));

    // "Water conducts": a soaked entity that takes damage also gets
    // shocked, purely through the plugin's own rule.
    final soaked = entities.create();
    components.add(soaked, const HealthComponent(current: 50, max: 50));
    components.add(soaked, StatusComponent({'status:soaked'}));
    events.publish(EntityDamaged(soaked, 5));
    expect(components.get<StatusComponent>(soaked)!.activeStatuses,
        contains('status:shocked'));

    // Removability: after stop/unregister, the rule no longer fires and
    // component cleanup stops too — mirroring MartialArtsPlugin's
    // existing removability test.
    manager.stop(context);
    manager.unregister(context);

    final soakedAfter = entities.create();
    components.add(soakedAfter, const HealthComponent(current: 50, max: 50));
    components.add(soakedAfter, StatusComponent({'status:soaked'}));
    events.publish(EntityDamaged(soakedAfter, 5));
    expect(components.get<StatusComponent>(soakedAfter)!.activeStatuses,
        isNot(contains('status:shocked')));

    entities.destroy(caster);
    expect(components.get<ElementalAffinityComponent>(caster), isNotNull);
  });
}
