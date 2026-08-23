import 'package:build_engine/build_engine.dart';
import 'package:build_engine/martial_arts_plugin.dart';
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
  );
}

void main() {
  group('MartialTechniqueAction attack techniques', () {
    test('jab requires style:boxing, costs nothing, grants momentum, and '
        'deals its base damage', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      learnStyle(actor, MartialStyles.boxing, context);

      final action = jab(actor: actor, targets: [target]);

      expect(action.conditions.every((c) => c.evaluate(
            RuleContext(
              subject: actor,
              triggerEvent: action,
              entities: context.entities,
              components: context.components,
              events: context.events,
              rng: context.rng,
              eventCounts: context.rules.eventCounts,
            ),
          )), isTrue);
      expect(action.costEffects, hasLength(1));
      final effects = action.effectsFor(target, context);
      expect(effects.single, isA<Damage>());
      expect((effects.single as Damage).amount, equals(6));
    });

    test('jab fails its condition without style:boxing', () {
      final context = _newContext();
      final actor = context.entities.create();
      final action = jab(actor: actor, targets: [context.entities.create()]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isFalse);
    });

    test('powerCross requires momentum above 19 and deals 18 base damage',
        () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      learnStyle(actor, MartialStyles.boxing, context);
      context.components.add(actor, ResourceComponent({'momentum': 20}));

      final action = powerCross(actor: actor, targets: [target]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isTrue);
      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(18));
      expect(action.costEffects, hasLength(1));
    });

    test('powerCross fails below the momentum threshold', () {
      final context = _newContext();
      final actor = context.entities.create();
      learnStyle(actor, MartialStyles.boxing, context);
      context.components.add(actor, ResourceComponent({'momentum': 19}));
      final action =
          powerCross(actor: actor, targets: [context.entities.create()]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isFalse);
    });

    test('palmStrike deals 8 base damage on the palm stat', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = palmStrike(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(8));
    });

    test('blazingPalm deals 14 base damage and is tagged fire', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = blazingPalm(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(14));
      expect(action.tags, contains('fire'));
    });

    test('pushHands deals 7 base damage on the internal stat', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = pushHands(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(7));
    });

    test('whirlingPalm deals 10 base damage and is tagged yang', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      final action = whirlingPalm(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(10));
      expect(action.tags, contains('yang'));
    });

    test('attack damage resolves through registered modifiers, like '
        'AttackAction', () {
      final context = _newContext();
      final actor = context.entities.create();
      final target = context.entities.create();
      context.modifiers.add(Modifier(
        source: const ModifierSource('test'),
        target: actor,
        stat: 'punch',
        operation: ModifierOperation.add,
        value: 6,
      ));

      final action = jab(actor: actor, targets: [target]);

      expect((action.effectsFor(target, context).single as Damage).amount,
          equals(12));
    });
  });

  group('MartialTechniqueAction stances', () {
    test('guardStance grants stance:guard and momentum, no damage', () {
      final context = _newContext();
      final actor = context.entities.create();
      final action = guardStance(actor: actor, targets: [actor]);

      final effects = action.effectsFor(actor, context);
      expect(effects, hasLength(2));
      expect(effects.whereType<Damage>(), isEmpty);
    });

    test('ironBodyStance requires qi above 4 and grants stance:iron_body',
        () {
      final context = _newContext();
      final actor = context.entities.create();
      learnStyle(actor, MartialStyles.shaolin, context);
      context.components.add(actor, ResourceComponent({'qi': 5}));
      final action = ironBodyStance(actor: actor, targets: [actor]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isTrue);
      final effects = action.effectsFor(actor, context);
      expect(effects.single, isA<AddTag>());
    });

    test('yieldingStance requires qi above 2 and grants stance:tai_chi', () {
      final context = _newContext();
      final actor = context.entities.create();
      learnStyle(actor, MartialStyles.taiChi, context);
      context.components.add(actor, ResourceComponent({'qi': 3}));
      final action = yieldingStance(actor: actor, targets: [actor]);
      final ruleContext = RuleContext(
        subject: actor,
        triggerEvent: action,
        entities: context.entities,
        components: context.components,
        events: context.events,
        rng: context.rng,
        eventCounts: context.rules.eventCounts,
      );

      expect(action.conditions.every((c) => c.evaluate(ruleContext)), isTrue);
      final effects = action.effectsFor(actor, context);
      expect(effects.single, isA<AddTag>());
    });
  });

  group('all 11 tags appear across the 9 techniques/stances', () {
    test('tag coverage', () {
      final actor = const EntityId(1);
      final targets = [actor];
      final allTags = <String>{
        ...jab(actor: actor, targets: targets).tags,
        ...powerCross(actor: actor, targets: targets).tags,
        ...guardStance(actor: actor, targets: targets).tags,
        ...palmStrike(actor: actor, targets: targets).tags,
        ...blazingPalm(actor: actor, targets: targets).tags,
        ...ironBodyStance(actor: actor, targets: targets).tags,
        ...pushHands(actor: actor, targets: targets).tags,
        ...whirlingPalm(actor: actor, targets: targets).tags,
        ...yieldingStance(actor: actor, targets: targets).tags,
      };

      expect(
        allTags,
        containsAll({
          'martial', 'fist', 'palm', 'internal', 'external', 'qi', 'yang',
          'fire', 'counter', 'western', 'eastern',
        }),
      );
    });
  });
}
