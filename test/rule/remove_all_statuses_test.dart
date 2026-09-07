import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

RuleContext _ctx(EntityId? subject, ComponentStore components) {
  final events = EventBus();
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
  test('clears a multi-status StatusComponent', () {
    final components = ComponentStore();
    const owner = EntityId(1);
    components.add(owner, StatusComponent({'status:poison', 'status:burn'}));

    const RemoveAllStatuses().apply(_ctx(owner, components));

    expect(components.get<StatusComponent>(owner), isNull);
  });

  test('no-op when the subject has no StatusComponent', () {
    final components = ComponentStore();
    const owner = EntityId(1);
    expect(() => const RemoveAllStatuses().apply(_ctx(owner, components)),
        returnsNormally);
    expect(components.get<StatusComponent>(owner), isNull);
  });

  test('no-op on a null subject', () {
    final components = ComponentStore();
    expect(() => const RemoveAllStatuses().apply(_ctx(null, components)),
        returnsNormally);
  });

  test("the 'removeAllStatuses' content factory parses a bare entry", () {
    final registry = ContentRegistry();
    registry.registerTrigger('Evt', _Evt, (e) => const EntityId(1));
    final rule = registry.loadRule({
      'id': 'r.clear',
      'trigger': 'Evt',
      'effects': [
        {'type': 'removeAllStatuses'},
      ],
    });
    expect(rule.rule.effects.single, isA<RemoveAllStatuses>());
  });
}
