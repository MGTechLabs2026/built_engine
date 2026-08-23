import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

Map<String, dynamic> _dragonPalm({
  String id = 'dragon_palm',
  List<Map<String, dynamic>> effects = const [
    {'type': 'damage', 'amount': 15},
  ],
  List<Map<String, dynamic>> conditions = const [],
  Set<String>? requires,
}) =>
    {
      'id': id,
      'type': 'skill',
      'tags': ['attack', 'fist', 'fire', 'dragon'],
      'components': {
        'cost': {'resource': 'qi', 'amount': 4},
      },
      if (conditions.isNotEmpty) 'conditions': conditions,
      'effects': effects,
      if (requires != null) 'requires': requires.toList(),
    };

void main() {
  group('load', () {
    test('parses a full envelope', () {
      final registry = ContentRegistry();
      final definition = registry.load(_dragonPalm());

      expect(definition.id, equals('dragon_palm'));
      expect(definition.type, equals('skill'));
      expect(definition.tags, equals({'attack', 'fist', 'fire', 'dragon'}));
      expect(definition.costEffects, hasLength(1));
      expect(definition.effects, hasLength(1));
      expect(definition.effects.single, isA<Damage>());
    });

    test('components.cost parses into a single ModifyResource cost effect',
        () {
      final registry = ContentRegistry();
      final definition = registry.load(_dragonPalm());
      final cost = definition.costEffects.single as ModifyResource;
      expect(cost.resource, equals('qi'));
      expect(cost.delta, equals(-4));
    });

    test('unrecognized top-level fields land in extra', () {
      final registry = ContentRegistry();
      final json = _dragonPalm();
      json['flavorText'] = 'A palm wreathed in flame.';
      final definition = registry.load(json);
      expect(definition.extra['flavorText'],
          equals('A palm wreathed in flame.'));
    });

    test('components sibling keys beside cost land in extra.components', () {
      final registry = ContentRegistry();
      final json = {
        'id': 'iron_sword',
        'type': 'item',
        'components': {
          'attack': {'damage': 12},
        },
      };
      final definition = registry.load(json);
      expect(definition.costEffects, isEmpty);
      expect(
        definition.extra['components'],
        equals({
          'attack': {'damage': 12},
        }),
      );
    });

    test('raw preserves the exact input map', () {
      final registry = ContentRegistry();
      final json = _dragonPalm();
      final definition = registry.load(json);
      expect(definition.raw, equals(json));
    });

    test(
        'createEntity/destroyEntity/transformEntity factories accept '
        'minimal params', () {
      final registry = ContentRegistry();
      final definition = registry.load(_dragonPalm(
        id: 'utility_test',
        effects: [
          {'type': 'createEntity'},
          {'type': 'destroyEntity'},
          {
            'type': 'transformEntity',
            'tags': ['x'],
          },
        ],
      ));
      expect(definition.effects, hasLength(3));
      expect(definition.effects[0], isA<CreateEntity>());
      expect(definition.effects[1], isA<DestroyEntity>());
      expect(definition.effects[2], isA<TransformEntity>());
    });
  });

  group('validation', () {
    test('missing id throws ContentFieldException', () {
      final registry = ContentRegistry();
      expect(() => registry.load({'type': 'skill'}),
          throwsA(isA<ContentFieldException>()));
    });

    test('missing type throws ContentValidationException naming the id', () {
      final registry = ContentRegistry();
      expect(
        () => registry.load({'id': 'dragon_palm'}),
        throwsA(
          isA<ContentValidationException>().having(
              (e) => e.toString(), 'message', contains('dragon_palm')),
        ),
      );
    });

    test('unknown effect type throws UnknownContentFactoryException', () {
      final registry = ContentRegistry();
      expect(
        () => registry.load(_dragonPalm(effects: [
          {'type': 'summonDragon', 'amount': 1},
        ])),
        throwsA(
          isA<UnknownContentFactoryException>().having(
              (e) => e.toString(), 'message', contains('summonDragon')),
        ),
      );
    });

    test('malformed components.cost missing resource throws with field path',
        () {
      final registry = ContentRegistry();
      final json = {
        'id': 'dragon_palm',
        'type': 'skill',
        'components': {
          'cost': {'amount': 4},
        },
      };
      expect(
        () => registry.load(json),
        throwsA(
          isA<ContentValidationException>().having(
              (e) => e.toString(),
              'message',
              contains('components.cost.resource')),
        ),
      );
    });

    test('effect factory validates its own params: damage requires amount',
        () {
      final registry = ContentRegistry();
      expect(
        () => registry.load(_dragonPalm(effects: [
          {'type': 'damage'},
        ])),
        throwsA(
          isA<ContentValidationException>().having((e) => e.toString(),
              'message', contains('effects[0].amount')),
        ),
      );
    });

    test('every built-in effect factory with a required param rejects its '
        'absence', () {
      final registry = ContentRegistry();
      final cases = <Map<String, dynamic>>[
        {'type': 'damage'},
        {'type': 'heal'},
        {'type': 'modifyStat', 'stat': 'punch'},
        {'type': 'modifyResource', 'resource': 'qi'},
        {'type': 'applyStatus'},
        {'type': 'removeStatus'},
        {'type': 'addTag'},
        {'type': 'removeTag'},
      ];
      for (final effect in cases) {
        expect(
          () => registry
              .load(_dragonPalm(id: 'x_${effect['type']}', effects: [effect])),
          throwsA(isA<ContentValidationException>()),
          reason: 'effect ${effect['type']} should validate its params',
        );
      }
    });

    test('every built-in condition factory with a required param rejects '
        'its absence', () {
      final registry = ContentRegistry();
      final cases = <Map<String, dynamic>>[
        {'type': 'hasTag'},
        {'type': 'resourceAbove', 'resource': 'qi'},
        {'type': 'resourceBelow', 'resource': 'qi'},
        {'type': 'healthBelow'},
        {'type': 'statusActive'},
        {'type': 'randomChance'},
      ];
      for (final condition in cases) {
        expect(
          () => registry.load(
              _dragonPalm(id: 'y_${condition['type']}', conditions: [condition])),
          throwsA(isA<ContentValidationException>()),
          reason: 'condition ${condition['type']} should validate its params',
        );
      }
    });
  });

  group('lookup', () {
    test('get/find/allOfType/withTag', () {
      final registry = ContentRegistry();
      registry.load(_dragonPalm());
      registry.load({
        'id': 'iron_sword',
        'type': 'item',
        'tags': ['weapon', 'sword'],
      });

      expect(registry.get('dragon_palm').type, equals('skill'));
      expect(registry.find('nonexistent'), isNull);
      expect(() => registry.get('nonexistent'),
          throwsA(isA<ContentNotFoundException>()));
      expect(registry.allOfType('item'), hasLength(1));
      expect(registry.allOfType('skill'), hasLength(1));
      expect(registry.withTag('dragon'), hasLength(1));
      expect(registry.withTag('weapon').single.id, equals('iron_sword'));
    });
  });

  group('dependency errors', () {
    test('requires referencing an unregistered id throws '
        'ContentDependencyException', () {
      final registry = ContentRegistry();
      expect(
        () => registry.load(_dragonPalm(requires: {'style:shaolin'})),
        throwsA(
          isA<ContentDependencyException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('dragon_palm'), contains('style:shaolin')),
          ),
        ),
      );
    });

    test('requires satisfied by an already-registered id succeeds', () {
      final registry = ContentRegistry();
      registry.load({'id': 'style:shaolin', 'type': 'style'});
      final definition =
          registry.load(_dragonPalm(requires: {'style:shaolin'}));
      expect(definition.requires, contains('style:shaolin'));
    });

    test('two definitions in the same loadAll batch may reference each '
        'other', () {
      final registry = ContentRegistry();
      final results = registry.loadAll([
        {
          'id': 'a',
          'type': 'skill',
          'requires': ['b'],
        },
        {
          'id': 'b',
          'type': 'skill',
          'requires': ['a'],
        },
      ]);
      expect(results, hasLength(2));
      expect(registry.get('a').requires, contains('b'));
      expect(registry.get('b').requires, contains('a'));
    });

    test('loadAll with an unresolvable requires registers nothing from the '
        'batch', () {
      final registry = ContentRegistry();
      expect(
        () => registry.loadAll([
          {'id': 'a', 'type': 'skill'},
          {
            'id': 'b',
            'type': 'skill',
            'requires': ['nonexistent'],
          },
        ]),
        throwsA(isA<ContentDependencyException>()),
      );
      expect(registry.find('a'), isNull);
      expect(registry.find('b'), isNull);
    });
  });

  group('duplicate ids', () {
    test('loading the same id twice throws ContentDuplicateIdException', () {
      final registry = ContentRegistry();
      registry.load(_dragonPalm());
      expect(() => registry.load(_dragonPalm()),
          throwsA(isA<ContentDuplicateIdException>()));
    });

    test('duplicate id within one loadAll batch throws and registers '
        'nothing', () {
      final registry = ContentRegistry();
      expect(
        () => registry.loadAll([
          {'id': 'a', 'type': 'skill'},
          {'id': 'a', 'type': 'skill'},
        ]),
        throwsA(isA<ContentDuplicateIdException>()),
      );
      expect(registry.find('a'), isNull);
    });

    test('a rule id colliding with a content id throws', () {
      final registry = ContentRegistry();
      registry.load({'id': 'shared_id', 'type': 'skill'});
      expect(
        () => registry.loadRule({
          'id': 'shared_id',
          'trigger': 'EntityDamaged',
          'effects': [
            {'type': 'heal', 'amount': 2},
          ],
        }),
        throwsA(isA<ContentDuplicateIdException>()),
      );
    });
  });

  group('rules', () {
    test('loadRule parses trigger/conditions/effects into a working Rule',
        () {
      final events = EventBus();
      final entities = EntityRegistry(events);
      final components = ComponentStore();
      final rules = RuleEngine(
        entities: entities,
        components: components,
        events: events,
        rng: RngService(1),
      );

      final registry = ContentRegistry();
      final definition = registry.loadRule({
        'id': 'shaolin_iron_body_heal',
        'trigger': 'EntityDamaged',
        'conditions': [
          {'type': 'hasTag', 'tag': 'stance:iron_body'},
        ],
        'effects': [
          {'type': 'heal', 'amount': 2},
        ],
      });

      rules.register(definition.rule);

      final subject = entities.create();
      components.add(subject, const HealthComponent(current: 50, max: 100));
      components.add(subject, TagSet({'stance:iron_body'}));

      events.publish(EntityDamaged(subject, 10));

      expect(components.get<HealthComponent>(subject)!.current, equals(52));
    });

    test('unknown trigger key throws UnknownContentFactoryException', () {
      final registry = ContentRegistry();
      expect(
        () => registry.loadRule({
          'id': 'r1',
          'trigger': 'ActionCompleted',
          'effects': [
            {'type': 'heal', 'amount': 2},
          ],
        }),
        throwsA(isA<UnknownContentFactoryException>()),
      );
    });

    test('rule lookup via rule(id)', () {
      final registry = ContentRegistry();
      final definition = registry.loadRule({
        'id': 'r1',
        'trigger': 'EntityHealed',
        'effects': const <Map<String, dynamic>>[],
      });
      expect(registry.rule('r1'), same(definition));
      expect(
          () => registry.rule('nonexistent'), throwsA(isA<ContentNotFoundException>()));
    });
  });

  group('serialization', () {
    test('toJson round-trips through a fresh registry', () {
      final source = ContentRegistry();
      source.load(_dragonPalm());
      source.load({
        'id': 'style:shaolin',
        'type': 'style',
        'tags': ['martial'],
      });
      source.loadRule({
        'id': 'r1',
        'trigger': 'EntityDamaged',
        'effects': [
          {'type': 'heal', 'amount': 2},
        ],
      });

      final dumped = source.toJson();

      final rebuilt = ContentRegistry();
      final contentJson =
          dumped.where((j) => !j.containsKey('trigger')).toList();
      final ruleJson = dumped.where((j) => j.containsKey('trigger')).toList();
      rebuilt.loadAll(contentJson);
      for (final ruleEntry in ruleJson) {
        rebuilt.loadRule(ruleEntry);
      }

      expect(rebuilt.get('dragon_palm').type,
          equals(source.get('dragon_palm').type));
      expect(
          rebuilt.get('dragon_palm').tags, equals(source.get('dragon_palm').tags));
      expect(rebuilt.allOfType('style'), hasLength(1));
      expect(rebuilt.rule('r1').rule.trigger, equals(EntityDamaged));
    });
  });
}
