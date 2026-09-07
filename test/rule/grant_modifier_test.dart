import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt();
}

RuleContext _ctx(EntityId? subject, {ModifierCollection? modifiers}) {
  final events = EventBus();
  return RuleContext(
    subject: subject,
    triggerEvent: const _Evt(),
    entities: EntityRegistry(events),
    components: ComponentStore(),
    events: events,
    rng: RngService(1),
    eventCounts: EventCounter(events),
    modifiers: modifiers,
  );
}

void main() {
  test('apply adds one source-scoped Modifier on the subject', () {
    final modifiers = ModifierCollection();
    const owner = EntityId(7);
    const GrantModifier('thrown', ModifierOperation.add, 6, sourceKey: 'consumable:power_tonic')
        .apply(_ctx(owner, modifiers: modifiers));

    final active = modifiers
        .activeModifiersFor(owner, 'thrown', ComponentStore())
        .toList();
    expect(active, hasLength(1));
    expect(active.single.value, 6);
    expect(active.single.source, const ModifierSource('consumable:power_tonic:7'));
  });

  test('re-apply with the same subject + sourceKey replaces, never stacks', () {
    final modifiers = ModifierCollection();
    const owner = EntityId(7);
    const g = GrantModifier('thrown', ModifierOperation.add, 6, sourceKey: 'consumable:power_tonic');
    g.apply(_ctx(owner, modifiers: modifiers));
    g.apply(_ctx(owner, modifiers: modifiers));

    expect(modifiers.activeModifiersFor(owner, 'thrown', ComponentStore()).length, 1);
  });

  test('no-op on a null subject', () {
    final modifiers = ModifierCollection();
    expect(
      () => const GrantModifier('x', ModifierOperation.add, 1).apply(_ctx(null, modifiers: modifiers)),
      returnsNormally,
    );
    expect(modifiers.activeModifiersFor(const EntityId(1), 'x', ComponentStore()), isEmpty);
  });
}
