import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _RecordingPlugin extends GamePlugin {
  _RecordingPlugin(
    this.id,
    this._log, {
    this.dependencies = const <String>[],
  });

  @override
  final String id;

  @override
  String get version => '1.0.0';

  @override
  final List<String> dependencies;

  final List<String> _log;

  @override
  void register(PluginContext context) => _log.add('$id.register');

  @override
  void initialize(PluginContext context) => _log.add('$id.initialize');

  @override
  void start(PluginContext context) => _log.add('$id.start');

  @override
  void stop(PluginContext context) => _log.add('$id.stop');

  @override
  void unregister(PluginContext context) => _log.add('$id.unregister');
}

PluginContext _newContext() {
  final events = EventBus();
  return PluginContext(
    entities: EntityRegistry(events),
    components: ComponentStore(),
    events: events,
  );
}

void main() {
  group('PluginManager registration', () {
    test('two plugins with distinct ids both register', () {
      final manager = PluginManager();
      final log = <String>[];

      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log));

      expect(manager.resolveLoadOrder().toSet(), equals({'a', 'b'}));
    });

    test('registering a duplicate id throws DuplicatePluginException', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));

      expect(
        () => manager.register(_RecordingPlugin('a', log)),
        throwsA(isA<DuplicatePluginException>()),
      );
    });
  });

  group('PluginManager.resolveLoadOrder', () {
    test('a plugin with no dependencies resolves trivially', () {
      final manager = PluginManager();
      manager.register(_RecordingPlugin('a', <String>[]));

      expect(manager.resolveLoadOrder(), equals(['a']));
    });

    test('dependencies are ordered before their dependents', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      manager.register(_RecordingPlugin('c', log, dependencies: ['b']));

      final order = manager.resolveLoadOrder();

      expect(order.indexOf('a'), lessThan(order.indexOf('b')));
      expect(order.indexOf('b'), lessThan(order.indexOf('c')));
    });

    test('a dependency on an unregistered plugin throws '
        'MissingPluginDependencyException', () {
      final manager = PluginManager();
      manager.register(
        _RecordingPlugin('a', <String>[], dependencies: ['ghost']),
      );

      expect(
        () => manager.resolveLoadOrder(),
        throwsA(isA<MissingPluginDependencyException>()),
      );
    });

    test('a two-plugin cycle throws CyclicPluginDependencyException', () {
      final manager = PluginManager();
      manager.register(
        _RecordingPlugin('a', <String>[], dependencies: ['b']),
      );
      manager.register(
        _RecordingPlugin('b', <String>[], dependencies: ['a']),
      );

      expect(
        () => manager.resolveLoadOrder(),
        throwsA(isA<CyclicPluginDependencyException>()),
      );
    });
  });

  group('PluginManager lifecycle ordering', () {
    test('initialize registers every plugin before initializing any',
        () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));

      manager.initialize(_newContext());

      expect(
        log,
        equals(['a.register', 'b.register', 'a.initialize', 'b.initialize']),
      );
    });

    test('start runs in dependency order after initialize', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      final context = _newContext();

      manager.initialize(context);
      log.clear();
      manager.start(context);

      expect(log, equals(['a.start', 'b.start']));
    });

    test('stop runs in reverse dependency order', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      final context = _newContext();
      manager.initialize(context);
      manager.start(context);
      log.clear();

      manager.stop(context);

      expect(log, equals(['b.stop', 'a.stop']));
    });

    test('unregister runs in reverse dependency order after stop', () {
      final manager = PluginManager();
      final log = <String>[];
      manager.register(_RecordingPlugin('a', log));
      manager.register(_RecordingPlugin('b', log, dependencies: ['a']));
      final context = _newContext();
      manager.initialize(context);
      manager.start(context);
      manager.stop(context);
      log.clear();

      manager.unregister(context);

      expect(log, equals(['b.unregister', 'a.unregister']));
    });

    test('initialize, start, stop, and unregister all succeed with zero '
        'plugins registered', () {
      final manager = PluginManager();
      final context = _newContext();

      expect(() => manager.initialize(context), returnsNormally);
      expect(() => manager.start(context), returnsNormally);
      expect(() => manager.stop(context), returnsNormally);
      expect(() => manager.unregister(context), returnsNormally);
    });
  });
}
