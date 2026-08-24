import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

/// Proves `ProgressionEngine` (the Learning primitive) and
/// `EvolutionResolver` serve a domain that has nothing to do with
/// techniques at all, with zero import of `technique_plugin.dart` or
/// anything under `lib/src/plugins/technique/` — the milestone's own
/// "unrelated content can reuse learning/evolution primitives"
/// requirement, proven structurally rather than asserted in prose.
void main() {
  test('a made-up "recipe learning" domain reuses ProgressionEngine directly', () {
    final events = EventBus();
    final components = ComponentStore();
    final mastery = MasteryTracker(components: components, events: events);
    final progression =
        ProgressionEngine(components: components, events: events, mastery: mastery);
    const cook = EntityId(1);
    const subject = 'recipe:herbal_soup:knowledge';

    progression.define(const ProgressionDefinition(subject: subject, thresholds: [5]));
    progression.addExperience(cook, subject, 3);
    expect(progression.tierOf(cook, subject), equals(0));

    progression.addExperience(cook, subject, 2);
    expect(progression.tierOf(cook, subject), equals(1));
  });

  test('the same EvolutionResolver serves a made-up "recipe upgrade" tree', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    final rng = RngService(9);
    final context = RuleContext(
      subject: const EntityId(1),
      triggerEvent: const Object(),
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      eventCounts: EventCounter(events),
    );
    const recipeTree = EvolutionDefinition(
      id: 'herbal_soup',
      tier: EvolutionTiers.basic,
      candidates: [
        EvolutionCandidate(targetId: 'hearty_herbal_soup', tags: {'power'}),
        EvolutionCandidate(targetId: 'delicate_herbal_soup', tags: {'precision'}),
      ],
    );
    const profile = TrainingProfile({TrainingDimensions.precision: 0.8});

    final result = const EvolutionResolver().resolve(
      context: context,
      current: recipeTree,
      profile: profile,
    );

    expect(result.evolved, isTrue);
    expect(
      ['hearty_herbal_soup', 'delicate_herbal_soup'],
      contains(result.chosenCandidate!.targetId),
    );
  });
}
