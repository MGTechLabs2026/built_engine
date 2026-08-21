import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _MarkerComponent {
  const _MarkerComponent(this.label);
  final String label;
}

class _EntityCreatingPlugin extends GamePlugin {
  _EntityCreatingPlugin(this.id, {this.dependencies = const <String>[]});

  @override
  final String id;

  @override
  String get version => '1.0.0';

  @override
  final List<String> dependencies;

  EntityId? createdEntity;

  @override
  void initialize(PluginContext context) {
    final entity = context.entities.create();
    context.components.add(entity, _MarkerComponent(id));
    createdEntity = entity;
  }

  @override
  void unregister(PluginContext context) {
    final entity = createdEntity;
    if (entity != null && context.entities.isAlive(entity)) {
      context.components.remove<_MarkerComponent>(entity);
      context.entities.destroy(entity);
    }
  }
}

void main() {
  group('core without any plugins', () {
    test('full lifecycle succeeds with zero plugins registered', () {
      final events = EventBus();
      final context = PluginContext(
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
      );
      final manager = PluginManager();

      manager.initialize(context);
      manager.start(context);
      manager.stop(context);
      manager.unregister(context);

      expect(context.entities.all, isEmpty);
    });

    test('entity/component/event services work with no plugins involved',
        () {
      final events = EventBus();
      final registry = EntityRegistry(events);
      final components = ComponentStore();
      final createdIds = <EntityId>[];
      events.subscribe<EntityCreated>((event) => createdIds.add(event.id));

      final entity = registry.create();
      components.add(entity, const _MarkerComponent('standalone'));

      expect(createdIds, equals([entity]));
      expect(components.get<_MarkerComponent>(entity)!.label,
          equals('standalone'));
    });
  });

  group('core with dependent plugins', () {
    test('plugins load and unload in dependency order end-to-end', () {
      final events = EventBus();
      final context = PluginContext(
        entities: EntityRegistry(events),
        components: ComponentStore(),
        events: events,
      );
      final manager = PluginManager();
      final base = _EntityCreatingPlugin('base');
      final dependent =
          _EntityCreatingPlugin('dependent', dependencies: ['base']);
      manager.register(dependent);
      manager.register(base);

      manager.initialize(context);
      manager.start(context);

      expect(base.createdEntity, isNotNull);
      expect(dependent.createdEntity, isNotNull);
      expect(
        base.createdEntity!.value,
        lessThan(dependent.createdEntity!.value),
        reason: 'base must initialize before dependent, per the declared dependency',
      );
      expect(context.entities.isAlive(base.createdEntity!), isTrue);
      expect(context.entities.isAlive(dependent.createdEntity!), isTrue);
      expect(context.components.get<_MarkerComponent>(base.createdEntity!)!.label,
          equals('base'));

      manager.stop(context);
      manager.unregister(context);

      expect(context.entities.isAlive(base.createdEntity!), isFalse);
      expect(context.entities.isAlive(dependent.createdEntity!), isFalse);
      expect(context.entities.all, isEmpty);
    });
  });
}
