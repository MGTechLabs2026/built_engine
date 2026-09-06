import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

RuleContext _ctx(EntityId? subject) {
  final events = EventBus();
  final components = ComponentStore();
  final entities = EntityRegistry(events);
  return RuleContext(
    subject: subject,
    triggerEvent: const _Evt(),
    entities: entities,
    components: components,
    events: events,
    rng: RngService(1),
    eventCounts: EventCounter(events),
  );
}

void main() {
  test('matches when the subject equals the entity', () {
    expect(const SubjectIs(EntityId(7)).evaluate(_ctx(const EntityId(7))), isTrue);
  });

  test('does not match a different subject', () {
    expect(const SubjectIs(EntityId(7)).evaluate(_ctx(const EntityId(8))), isFalse);
  });

  test('does not match a null subject', () {
    expect(const SubjectIs(EntityId(7)).evaluate(_ctx(null)), isFalse);
  });
}
