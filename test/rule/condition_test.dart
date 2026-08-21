import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _TestEvent {
  const _TestEvent();
}

RuleContext _contextFor({
  EntityId? subject,
  ComponentStore? components,
  RngService? rng,
}) {
  final eventBus = EventBus();
  return RuleContext(
    subject: subject,
    triggerEvent: const Object(),
    entities: EntityRegistry(eventBus),
    components: components ?? ComponentStore(),
    events: eventBus,
    rng: rng ?? RngService(1),
    eventCounts: EventCounter(eventBus),
  );
}

void main() {
  group('HasTag', () {
    test('matches when the subject has the tag', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, TagSet({'fire'}));

      expect(
        HasTag('fire')
            .evaluate(_contextFor(subject: subject, components: components)),
        isTrue,
      );
    });

    test('does not match with no subject', () {
      expect(HasTag('fire').evaluate(_contextFor(subject: null)), isFalse);
    });
  });

  group('HasComponent', () {
    test('matches when the subject has the component', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, const HealthComponent(current: 1, max: 1));

      expect(
        const HasComponent<HealthComponent>().evaluate(
          _contextFor(subject: subject, components: components),
        ),
        isTrue,
      );
    });

    test('does not match with no subject', () {
      expect(
        const HasComponent<HealthComponent>().evaluate(
          _contextFor(subject: null),
        ),
        isFalse,
      );
    });
  });

  group('ResourceAbove / ResourceBelow', () {
    test('respect the strict comparisons', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, ResourceComponent({'stamina': 50}));
      final context = _contextFor(subject: subject, components: components);

      expect(ResourceAbove('stamina', 40).evaluate(context), isTrue);
      expect(ResourceAbove('stamina', 50).evaluate(context), isFalse);
      expect(ResourceBelow('stamina', 60).evaluate(context), isTrue);
      expect(ResourceBelow('stamina', 50).evaluate(context), isFalse);
    });
  });

  group('HealthBelow', () {
    test('matches strictly below the threshold', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, const HealthComponent(current: 20, max: 100));

      expect(
        HealthBelow(50)
            .evaluate(_contextFor(subject: subject, components: components)),
        isTrue,
      );
    });

    test('does not match with no subject', () {
      expect(HealthBelow(9999).evaluate(_contextFor(subject: null)), isFalse);
    });
  });

  group('StatusActive', () {
    test('matches when the status is active', () {
      final components = ComponentStore();
      const subject = EntityId(1);
      components.add(subject, StatusComponent({'burning'}));

      expect(
        StatusActive('burning').evaluate(
          _contextFor(subject: subject, components: components),
        ),
        isTrue,
      );
    });
  });

  group('EventCount', () {
    test('every comparison direction behaves correctly', () {
      final events = EventBus();
      final counter = EventCounter(events);
      counter.trackType(_TestEvent);
      events.publish(const _TestEvent());
      final context = RuleContext(
        subject: null,
        triggerEvent: const Object(),
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
        rng: RngService(1),
        eventCounts: counter,
      );

      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.greaterThan,
          threshold: 0,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.greaterThanOrEqual,
          threshold: 1,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.lessThan,
          threshold: 2,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.lessThanOrEqual,
          threshold: 1,
        ).evaluate(context),
        isTrue,
      );
      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.equal,
          threshold: 1,
        ).evaluate(context),
        isTrue,
      );
    });

    test('an untracked event type reports zero', () {
      final events = EventBus();
      final context = RuleContext(
        subject: null,
        triggerEvent: const Object(),
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
        rng: RngService(1),
        eventCounts: EventCounter(events),
      );

      expect(
        const EventCount(
          eventType: _TestEvent,
          comparison: CountComparison.equal,
          threshold: 0,
        ).evaluate(context),
        isTrue,
      );
    });
  });

  group('RandomChance', () {
    test('chance(0.0) never matches', () {
      final context = _contextFor(subject: null, rng: RngService(1));
      for (var i = 0; i < 20; i++) {
        expect(RandomChance(0.0).evaluate(context), isFalse);
      }
    });

    test('chance(1.0) always matches', () {
      final context = _contextFor(subject: null, rng: RngService(1));
      for (var i = 0; i < 20; i++) {
        expect(RandomChance(1.0).evaluate(context), isTrue);
      }
    });
  });
}
