import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/martial_arts_plugin.dart';
import 'package:build_engine/physique_plugin.dart';
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
  test('5: PhysiquePlugin works without MartialArtsPlugin', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(PhysiquePlugin());
    manager.initialize(context);
    manager.start(context);

    final character = context.entities.create();
    final physiqueId = initializePhysique(character, context);

    expect(PhysiqueTypes.all, contains(physiqueId));
    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test('6: MartialArtsPlugin works without PhysiquePlugin', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(CombatPlugin());
    manager.register(MartialArtsPlugin());
    manager.initialize(context);
    manager.start(context);

    final entity = context.entities.create();
    learnStyle(entity, MartialStyles.polearming, context);

    expect(
        context.components.get<TagSet>(entity)!.tags, contains('western'));
    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  test('7: both plugins can coexist', () {
    final context = _newContext();
    final manager = PluginManager();
    manager.register(CombatPlugin());
    manager.register(MartialArtsPlugin());
    manager.register(PhysiquePlugin());
    manager.initialize(context);
    manager.start(context);

    final character = context.entities.create();
    learnStyle(character, MartialStyles.polearming, context);
    final physiqueId = initializePhysique(character, context);

    expect(PhysiqueTypes.all, contains(physiqueId));
    expect(context.components.get<TagSet>(character)!.tags,
        contains('western'));
    expect(context.components.get<PhysiqueComponent>(character)!.physiqueId,
        equals(physiqueId));

    expect(() => manager.stop(context), returnsNormally);
    expect(() => manager.unregister(context), returnsNormally);
  });

  group('8 & 9: Sturdy/Power synergy with western/eastern traditions', () {
    for (final physiqueId in [PhysiqueTypes.sturdy, PhysiqueTypes.power]) {
      test('$physiqueId: western synergy is 1.25x, eastern is 0.85x', () {
        final context = _newContext();
        PhysiquePlugin().initialize(context);
        final definition =
            physiqueDefinitionFromContent(context.content.get(physiqueId));

        final westernCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(westernCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(westernCharacter, MartialStyles.polearming, context);
        final westernResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(westernCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(westernResolved, equals(125));

        final easternCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(easternCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(easternCharacter, MartialStyles.shaolin, context);
        final easternResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(easternCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(easternResolved, equals(85));
      });
    }
  });

  group('10 & 11: Burst/Endurance synergy with eastern/western traditions',
      () {
    for (final physiqueId in [PhysiqueTypes.burst, PhysiqueTypes.endurance]) {
      test('$physiqueId: eastern synergy is 1.25x, western is 0.85x', () {
        final context = _newContext();
        PhysiquePlugin().initialize(context);
        final definition =
            physiqueDefinitionFromContent(context.content.get(physiqueId));

        final easternCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(easternCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(easternCharacter, MartialStyles.taiChi, context);
        final easternResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(easternCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(easternResolved, equals(125));

        final westernCharacter = context.entities.create();
        for (final modifier in definition.modifiersFor(westernCharacter)) {
          context.modifiers.add(modifier);
        }
        learnStyle(westernCharacter, MartialStyles.polearming, context);
        final westernResolved = const ModifierResolver().resolve(
          100,
          context.modifiers.activeModifiersFor(westernCharacter,
              definition.primaryAffinity, context.components),
        );
        expect(westernResolved, equals(85));
      });
    }
  });

  test('neutral: no martial style learned means no synergy modifier '
      'applies', () {
    final context = _newContext();
    PhysiquePlugin().initialize(context);
    final definition =
        physiqueDefinitionFromContent(context.content.get(PhysiqueTypes.sturdy));

    final character = context.entities.create();
    for (final modifier in definition.modifiersFor(character)) {
      context.modifiers.add(modifier);
    }

    final resolved = const ModifierResolver().resolve(
      100,
      context.modifiers
          .activeModifiersFor(character, definition.primaryAffinity, context.components),
    );
    expect(resolved, equals(100));
  });
}
