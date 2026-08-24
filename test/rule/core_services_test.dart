import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

/// Proves `CoreServices` fixes the exact footgun
/// `ARCHITECTURE_AUDIT.md`'s Additional Observation A describes: a
/// `PluginContext` and a `RuleEngine` built from the same
/// `ComponentStore`/`EventBus` but relying on their own unsupplied
/// `MasteryTracker` defaults silently diverge, so a `Rule` (dispatched
/// through `RuleEngine`) reading mastery never sees progress written
/// through `PluginContext.mastery` directly.
void main() {
  PluginContext buildContext({required bool shareServices}) {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(1);
    final shared =
        shareServices ? CoreServices(components: components, events: events) : null;
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
        shared: shared,
      ),
      queries: QueryEngine(QueryScope(components: components)),
      modifiers: ModifierCollection(),
      content: ContentRegistry(),
      shared: shared,
    );
  }

  test('with shared: CoreServices, a Rule dispatched through RuleEngine sees mastery '
      'written through PluginContext.mastery directly', () {
    final context = buildContext(shareServices: true);
    context.mastery.define(const MasteryDefinition(subject: 'skill:x', thresholds: [10]));
    context.rules.register(Rule(
      trigger: MasteryLevelReached,
      subjectOf: (event) => (event as MasteryLevelReached).owner,
      conditions: const [MasteryAtLeast('skill:x', 1)],
      effects: const [AddTag('unlocked')],
    ));
    final entity = context.entities.create();

    context.mastery.increase(entity, 'skill:x', 10); // written through PluginContext.mastery

    expect(context.components.get<TagSet>(entity)?.tags.contains('unlocked'), isTrue);
  });

  test('without shared:, the same setup reproduces the historical divergence bug '
      '(documented, not a regression — shared: is opt-in)', () {
    final context = buildContext(shareServices: false);
    context.mastery.define(const MasteryDefinition(subject: 'skill:x', thresholds: [10]));
    context.rules.register(Rule(
      trigger: MasteryLevelReached,
      subjectOf: (event) => (event as MasteryLevelReached).owner,
      conditions: const [MasteryAtLeast('skill:x', 1)],
      effects: const [AddTag('unlocked')],
    ));
    final entity = context.entities.create();

    context.mastery.increase(entity, 'skill:x', 10);

    // RuleEngine's own unshared MasteryTracker never saw the increase,
    // so the rule's condition reads level 0 and never applies the tag —
    // exactly the bug this session's Technique/Item test bootstraps hit.
    expect(context.components.get<TagSet>(entity)?.tags.contains('unlocked'), isNot(isTrue));
  });
}
