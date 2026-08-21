import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Trigger {
  const _Trigger(this.actor);
  final EntityId actor;
}

class _OtherEvent {
  const _OtherEvent();
}

class _RecordingEffect implements Effect {
  const _RecordingEffect(this.onApply);

  final void Function() onApply;

  @override
  void apply(RuleContext context) => onApply();
}

RuleEngine _newEngine({
  required EntityRegistry entities,
  required ComponentStore components,
  required EventBus events,
  int seed = 1,
}) =>
    RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: RngService(seed),
    );

num _runRandomRule({required int seed}) {
  final events = EventBus();
  final components = ComponentStore();
  final entities = EntityRegistry(events);
  final actor = entities.create();
  components.add(actor, const HealthComponent(current: 100, max: 100));
  final engine = RuleEngine(
    entities: entities,
    components: components,
    events: events,
    rng: RngService(seed),
  );

  engine.register(Rule(
    trigger: _Trigger,
    subjectOf: (event) => (event as _Trigger).actor,
    conditions: [const RandomChance(0.5)],
    effects: [const Damage(10)],
  ));

  for (var i = 0; i < 10; i++) {
    events.publish(_Trigger(actor));
  }

  return components.get<HealthComponent>(actor)!.current;
}

void main() {
  group('RuleEngine', () {
    test('a registered rule fires when its trigger is published', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        effects: [const Damage(10)],
      ));

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(90));
    });

    test('a rule does not fire for a different event type', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        effects: [const Damage(10)],
      ));

      events.publish(const _OtherEvent());

      expect(components.get<HealthComponent>(actor)!.current, equals(100));
    });

    test('all conditions must pass (AND) for effects to run', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, TagSet({'fire'}));
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        conditions: [HasTag('fire'), HasTag('ice')],
        effects: [const Damage(10)],
      ));

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(100));
    });

    test('effects run in list order', () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        effects: [const Damage(50), const Heal(10)],
      ));

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(60));
    });

    test('an entity-scoped condition never passes with no resolvable subject',
        () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final engine =
          _newEngine(entities: entities, components: components, events: events);
      var fired = false;

      engine.register(Rule(
        trigger: _OtherEvent,
        conditions: [HasTag('fire')],
        effects: [_RecordingEffect(() => fired = true)],
      ));

      events.publish(const _OtherEvent());

      expect(fired, isFalse);
    });

    test('EventCount is auto-tracked from rule registration, not retroactively',
        () {
      final events = EventBus();
      final components = ComponentStore();
      final entities = EntityRegistry(events);
      final actor = entities.create();
      components.add(actor, const HealthComponent(current: 100, max: 100));
      final engine =
          _newEngine(entities: entities, components: components, events: events);

      events.publish(const _OtherEvent());
      engine.register(Rule(
        trigger: _Trigger,
        subjectOf: (event) => (event as _Trigger).actor,
        conditions: [
          const EventCount(
            eventType: _OtherEvent,
            comparison: CountComparison.equal,
            threshold: 1,
          ),
        ],
        effects: [const Damage(10)],
      ));
      events.publish(const _OtherEvent());

      events.publish(_Trigger(actor));

      expect(components.get<HealthComponent>(actor)!.current, equals(90));
    });

    test('the same seed and the same registration/publish order produce the '
        'same outcome', () {
      final resultA = _runRandomRule(seed: 42);
      final resultB = _runRandomRule(seed: 42);

      expect(resultA, equals(resultB));
    });
  });
}
