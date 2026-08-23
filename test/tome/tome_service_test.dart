import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  late EventBus events;
  late EntityRegistry entities;
  late ComponentStore components;
  late TomeService tomeService;

  const jab = BuildComponentRef(referenceType: 'technique', contentId: 'jab');
  const ironSword = BuildComponentRef(referenceType: 'item', contentId: 'iron_sword');

  setUp(() {
    events = EventBus();
    entities = EntityRegistry(events);
    components = ComponentStore();
    tomeService = TomeService(entities: entities, components: components);
    tomeService.defineTome(
      TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['core', 'socket_1', 'socket_2']),
    );
  });

  group('creation', () {
    test('createTome attaches a TomeInstance built from the definition', () {
      final owner = entities.create();

      tomeService.createTome(owner, 'basic_tome');

      final instance = tomeService.tomeOf(owner);
      expect(instance, isNotNull);
      expect(instance!.definitionId, equals('basic_tome'));
      expect(instance.container.hasSlot(const SlotId('core')), isTrue);
    });
  });

  group('valid placement', () {
    test('insert places a build component into an empty slot', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');

      tomeService.insert(owner, const SlotId('core'), jab);

      final placements = tomeService.inspect(owner);
      expect(placements, hasLength(1));
      expect(placements.single.slot, equals(const SlotId('core')));
      expect(placements.single.buildComponentRef, equals(jab));
    });

    test('validate reports true for an empty slot', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');

      expect(tomeService.validate(owner, const SlotId('core')), isTrue);
    });
  });

  group('invalid placement', () {
    test('insert throws InvalidPlacementException for an occupied slot', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');
      tomeService.insert(owner, const SlotId('core'), jab);

      expect(
        () => tomeService.insert(owner, const SlotId('core'), ironSword),
        throwsA(isA<InvalidPlacementException>()),
      );
      // the failed attempt must not have mutated anything
      expect(tomeService.inspect(owner), hasLength(1));
      expect(tomeService.inspect(owner).single.buildComponentRef, equals(jab));
    });

    test('insert throws for a slot that does not exist in this Tome', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');

      expect(
        () => tomeService.insert(owner, const SlotId('does_not_exist'), jab),
        throwsA(isA<InvalidPlacementException>()),
      );
    });

    test('validate reports false for an occupied slot', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');
      tomeService.insert(owner, const SlotId('core'), jab);

      expect(tomeService.validate(owner, const SlotId('core')), isFalse);
    });

    test('insert throws StateError when the owner has no Tome', () {
      final owner = entities.create();

      expect(
        () => tomeService.insert(owner, const SlotId('core'), jab),
        throwsStateError,
      );
    });
  });

  group('moving', () {
    test('move relocates a placement to an empty slot', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');
      tomeService.insert(owner, const SlotId('core'), jab);

      tomeService.move(owner, const SlotId('core'), const SlotId('socket_1'));

      final placements = tomeService.inspect(owner);
      expect(placements, hasLength(1));
      expect(placements.single.slot, equals(const SlotId('socket_1')));
      expect(placements.single.buildComponentRef, equals(jab));
    });

    test('move throws and leaves the placement unchanged when the target is occupied',
        () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');
      tomeService.insert(owner, const SlotId('core'), jab);
      tomeService.insert(owner, const SlotId('socket_1'), ironSword);

      expect(
        () => tomeService.move(owner, const SlotId('core'), const SlotId('socket_1')),
        throwsA(isA<InvalidPlacementException>()),
      );
      expect(
        tomeService.inspect(owner).firstWhere((p) => p.slot == const SlotId('core')).buildComponentRef,
        equals(jab),
      );
    });
  });

  group('removing', () {
    test('remove frees the slot', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');
      tomeService.insert(owner, const SlotId('core'), jab);

      tomeService.remove(owner, const SlotId('core'));

      expect(tomeService.inspect(owner), isEmpty);
      expect(tomeService.validate(owner, const SlotId('core')), isTrue);
    });

    test('remove is a no-op for an empty slot', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');

      tomeService.remove(owner, const SlotId('core'));

      expect(tomeService.inspect(owner), isEmpty);
    });
  });

  group('replace', () {
    test('replace swaps the occupant of a slot, keeping the slot filled', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');
      tomeService.insert(owner, const SlotId('core'), jab);

      tomeService.replace(owner, const SlotId('core'), ironSword);

      final placements = tomeService.inspect(owner);
      expect(placements, hasLength(1));
      expect(placements.single.buildComponentRef, equals(ironSword));
    });

    test('replace on an empty slot behaves like insert', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');

      tomeService.replace(owner, const SlotId('core'), jab);

      expect(tomeService.inspect(owner).single.buildComponentRef, equals(jab));
    });
  });

  group('resolving build', () {
    test('resolve produces an ActiveBuild reflecting current placements', () {
      final owner = entities.create();
      tomeService.createTome(owner, 'basic_tome');
      tomeService.insert(owner, const SlotId('core'), jab);
      tomeService.insert(owner, const SlotId('socket_1'), ironSword);

      final build = tomeService.resolve(owner);

      expect(build.owner, equals(owner));
      expect(build.components, containsAll([jab, ironSword]));
      expect(build.components, hasLength(2));
    });

    test('resolve on an owner with no Tome yields an empty ActiveBuild', () {
      final owner = entities.create();

      final build = tomeService.resolve(owner);

      expect(build.components, isEmpty);
    });
  });

  group('deterministic build resolution', () {
    test('the same call sequence yields the same resolved ActiveBuild', () {
      final owner1 = entities.create();
      tomeService.createTome(owner1, 'basic_tome');
      tomeService.insert(owner1, const SlotId('core'), jab);
      tomeService.insert(owner1, const SlotId('socket_1'), ironSword);
      tomeService.remove(owner1, const SlotId('socket_1'));
      tomeService.insert(owner1, const SlotId('socket_2'), ironSword);

      final events2 = EventBus();
      final entities2 = EntityRegistry(events2);
      final components2 = ComponentStore();
      final tomeService2 =
          TomeService(entities: entities2, components: components2);
      tomeService2.defineTome(
        TomeDefinition.namedSlots(id: 'basic_tome', slotIds: ['core', 'socket_1', 'socket_2']),
      );
      final owner2 = entities2.create();
      tomeService2.createTome(owner2, 'basic_tome');
      tomeService2.insert(owner2, const SlotId('core'), jab);
      tomeService2.insert(owner2, const SlotId('socket_1'), ironSword);
      tomeService2.remove(owner2, const SlotId('socket_1'));
      tomeService2.insert(owner2, const SlotId('socket_2'), ironSword);

      final build1 = tomeService.resolve(owner1);
      final build2 = tomeService2.resolve(owner2);

      expect(
        build1.components.map((c) => (c.referenceType, c.contentId)),
        equals(build2.components.map((c) => (c.referenceType, c.contentId))),
      );
    });
  });
}
