import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('a data-loaded skill definition resolves through the real engine '
      'exactly like a hand-written Condition/Effect would', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final registry = ContentRegistry();

    final definition = registry.load({
      'id': 'dragon_palm',
      'type': 'skill',
      'tags': ['attack', 'fist', 'fire', 'dragon'],
      'components': {
        'cost': {'resource': 'qi', 'amount': 4},
      },
      'conditions': [
        {'type': 'resourceAbove', 'resource': 'qi', 'threshold': 3},
      ],
      'effects': [
        {'type': 'damage', 'amount': 15},
      ],
    });

    final actor = entities.create();
    final target = entities.create();
    components.add(actor, ResourceComponent({'qi': 10}));
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

    // Conditions are evaluated against the actor (do they qualify to use
    // this skill?); cost and effects run against the same actor/target
    // split `AttackAction`/`MartialTechniqueAction` already use.
    final qualifies =
        definition.conditions.every((c) => c.evaluate(contextFor(actor)));
    expect(qualifies, isTrue);

    for (final cost in definition.costEffects) {
      cost.apply(contextFor(actor));
    }
    expect(components.get<ResourceComponent>(actor)!.resources['qi'],
        equals(6));

    for (final effect in definition.effects) {
      effect.apply(contextFor(target));
    }
    expect(
        components.get<HealthComponent>(target)!.current, equals(85));

    // Below the threshold now demonstrates the loaded Condition rejects
    // exactly like the equivalent hand-written `ResourceAbove('qi', 3)`
    // would.
    components.add(actor, ResourceComponent({'qi': 2}));
    final stillQualifies =
        definition.conditions.every((c) => c.evaluate(contextFor(actor)));
    expect(stillQualifies, isFalse);
  });
}
