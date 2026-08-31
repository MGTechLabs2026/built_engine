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
    content: ContentRegistry(),
  );
}

void main() {
  group('learnStyle', () {
    test('grants the martial tag and a style:<id> tag', () {
      final context = _newContext();
      final entity = context.entities.create();

      learnStyle(entity, MartialStyles.polearming, context);

      final tags = context.components.get<TagSet>(entity)!.tags;
      expect(tags, containsAll({'martial', 'style:polearming'}));
    });

    test('learning shaolin additionally registers the offense/defense '
        'synergy modifier', () {
      final context = _newContext();
      final entity = context.entities.create();

      learnStyle(entity, MartialStyles.shaolin, context);

      final inactive = context.modifiers
          .activeModifiersFor(entity, 'palm', context.components);
      expect(inactive, isEmpty);

      context.components.add(entity, TagSet({'stance:iron_body'}));
      final active = context.modifiers
          .activeModifiersFor(entity, 'palm', context.components);
      expect(active, hasLength(1));
      expect(active.single.value, equals(4));
      expect(active.single.operation, equals(ModifierOperation.add));
    });

    test('no style grants a palm modifier except shaolin — polearming and '
        'taiChi affinity modifiers target other stats', () {
      final context = _newContext();
      final boxer = context.entities.create();
      final taiChiPractitioner = context.entities.create();
      context.components.add(boxer, TagSet({'stance:iron_body'}));
      context.components.add(taiChiPractitioner, TagSet({'stance:iron_body'}));

      learnStyle(boxer, MartialStyles.polearming, context);
      learnStyle(taiChiPractitioner, MartialStyles.taiChi, context);

      expect(
        context.modifiers.activeModifiersFor(boxer, 'palm', context.components),
        isEmpty,
      );
      expect(
        context.modifiers
            .activeModifiersFor(taiChiPractitioner, 'palm', context.components),
        isEmpty,
      );
    });

    test('V1: every style grants its spec:* marker tag(s)', () {
      for (final entry in MartialSpecs.byStyle.entries) {
        final context = _newContext();
        final e = context.entities.create();
        learnStyle(e, entry.key, context);
        final tags = context.components.get<TagSet>(e)!.tags;
        expect(tags, containsAll(entry.value),
            reason: '${entry.key} must grant ${entry.value}');
      }
    });

    test('V1: fencing gets an unconditional +3 initiative (First Blood); '
        'kunlun gets +2 speed only while stance:swallow', () {
      final context = _newContext();
      final fencer = context.entities.create();
      final kunlunStylist = context.entities.create();

      learnStyle(fencer, MartialStyles.fencing, context);
      learnStyle(kunlunStylist, MartialStyles.kunlun, context);

      expect(
        context.modifiers
            .activeModifiersFor(fencer, 'initiative', context.components)
            .single
            .value,
        equals(3),
      );
      expect(
        context.modifiers
            .activeModifiersFor(kunlunStylist, 'speed', context.components),
        isEmpty,
      );
      context.components.add(kunlunStylist, TagSet({MartialStances.swallow}));
      expect(
        context.modifiers
            .activeModifiersFor(kunlunStylist, 'speed', context.components)
            .single
            .value,
        equals(2),
      );
    });

    test('style id constants have the expected values', () {
      expect(MartialStyles.polearming, equals('polearming'));
      expect(MartialStyles.wrestling, equals('wrestling'));
      expect(MartialStyles.fencing, equals('fencing'));
      expect(MartialStyles.shaolin, equals('shaolin'));
      expect(MartialStyles.taiChi, equals('taiChi'));
      expect(MartialStyles.kunlun, equals('kunlun'));
    });

    test('grants the western tradition tag for wrestling and fencing too', () {
      final context = _newContext();
      final wrestler = context.entities.create();
      final fencer = context.entities.create();

      learnStyle(wrestler, MartialStyles.wrestling, context);
      learnStyle(fencer, MartialStyles.fencing, context);

      expect(context.components.get<TagSet>(wrestler)!.tags, contains('western'));
      expect(context.components.get<TagSet>(fencer)!.tags, contains('western'));
    });

    test('grants the eastern tradition tag for kunlun too', () {
      final context = _newContext();
      final practitioner = context.entities.create();

      learnStyle(practitioner, MartialStyles.kunlun, context);

      expect(context.components.get<TagSet>(practitioner)!.tags, contains('eastern'));
    });

    test('grants the western tradition tag for polearming, eastern for '
        'shaolin and taiChi', () {
      final context = _newContext();
      final boxer = context.entities.create();
      final shaolinMonk = context.entities.create();
      final taiChiPractitioner = context.entities.create();

      learnStyle(boxer, MartialStyles.polearming, context);
      learnStyle(shaolinMonk, MartialStyles.shaolin, context);
      learnStyle(taiChiPractitioner, MartialStyles.taiChi, context);

      expect(
          context.components.get<TagSet>(boxer)!.tags, contains('western'));
      expect(context.components.get<TagSet>(boxer)!.tags,
          isNot(contains('eastern')));
      expect(context.components.get<TagSet>(shaolinMonk)!.tags,
          contains('eastern'));
      expect(context.components.get<TagSet>(shaolinMonk)!.tags,
          isNot(contains('western')));
      expect(context.components.get<TagSet>(taiChiPractitioner)!.tags,
          contains('eastern'));
      expect(context.components.get<TagSet>(taiChiPractitioner)!.tags,
          isNot(contains('western')));
    });

    test('an unrecognized style id is still accepted, with no tradition '
        'tag granted', () {
      final context = _newContext();
      final entity = context.entities.create();

      expect(() => learnStyle(entity, 'krav_maga', context), returnsNormally);

      final tags = context.components.get<TagSet>(entity)!.tags;
      expect(tags, containsAll(['martial', 'style:krav_maga']));
      expect(tags, isNot(contains('western')));
      expect(tags, isNot(contains('eastern')));
    });
  });

  group('martialTraditionOf', () {
    test('maps the three western styles to MartialTraditions.western', () {
      expect(martialTraditionOf(MartialStyles.polearming), MartialTraditions.western);
      expect(martialTraditionOf(MartialStyles.wrestling), MartialTraditions.western);
      expect(martialTraditionOf(MartialStyles.fencing), MartialTraditions.western);
    });

    test('maps the three eastern styles to MartialTraditions.eastern', () {
      expect(martialTraditionOf(MartialStyles.shaolin), MartialTraditions.eastern);
      expect(martialTraditionOf(MartialStyles.taiChi), MartialTraditions.eastern);
      expect(martialTraditionOf(MartialStyles.kunlun), MartialTraditions.eastern);
    });

    test('returns null for an unrecognized style id', () {
      expect(martialTraditionOf('capoeira'), isNull);
    });
  });
}
