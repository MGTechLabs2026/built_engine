import 'game_plugin.dart';
import 'plugin_context.dart';
import 'plugin_exceptions.dart';

/// Registers [GamePlugin]s, resolves their dependency order, and drives
/// their lifecycle (register → initialize → start, then stop → unregister
/// in reverse) in that resolved order.
class PluginManager {
  final Map<String, GamePlugin> _plugins = {};
  List<String>? _loadOrder;

  /// Adds [plugin] to the registry. Does not call any lifecycle method.
  ///
  /// Throws [DuplicatePluginException] if a plugin with the same [GamePlugin.id]
  /// is already registered.
  void register(GamePlugin plugin) {
    if (_plugins.containsKey(plugin.id)) {
      throw DuplicatePluginException(plugin.id);
    }
    _plugins[plugin.id] = plugin;
    _loadOrder = null;
  }

  /// Returns every registered plugin's id, topologically sorted so each
  /// plugin's dependencies precede it. Deterministic for a fixed
  /// registration order. The result is cached until the next [register].
  ///
  /// Throws [MissingPluginDependencyException] if a plugin depends on an id
  /// that was never registered, or [CyclicPluginDependencyException] if
  /// dependencies form a cycle.
  List<String> resolveLoadOrder() {
    final cachedOrder = _loadOrder;
    if (cachedOrder != null) return cachedOrder;

    final visited = <String>{};
    final visiting = <String>{};
    final order = <String>[];

    void visit(String pluginId, List<String> path) {
      if (visited.contains(pluginId)) return;
      if (visiting.contains(pluginId)) {
        throw CyclicPluginDependencyException([...path, pluginId]);
      }
      final plugin = _plugins[pluginId];
      if (plugin == null) {
        throw MissingPluginDependencyException(path.last, pluginId);
      }
      visiting.add(pluginId);
      for (final dependencyId in plugin.dependencies) {
        visit(dependencyId, [...path, pluginId]);
      }
      visiting.remove(pluginId);
      visited.add(pluginId);
      order.add(pluginId);
    }

    for (final pluginId in _plugins.keys) {
      visit(pluginId, const []);
    }

    _loadOrder = order;
    return order;
  }

  /// Calls [GamePlugin.register] on every plugin in dependency order, then
  /// [GamePlugin.initialize] on every plugin in dependency order.
  void initialize(PluginContext context) {
    final order = resolveLoadOrder();
    for (final pluginId in order) {
      _plugins[pluginId]!.register(context);
    }
    for (final pluginId in order) {
      _plugins[pluginId]!.initialize(context);
    }
  }

  /// Calls [GamePlugin.start] on every plugin in dependency order.
  void start(PluginContext context) {
    for (final pluginId in resolveLoadOrder()) {
      _plugins[pluginId]!.start(context);
    }
  }

  /// Calls [GamePlugin.stop] on every plugin in reverse dependency order.
  void stop(PluginContext context) {
    for (final pluginId in resolveLoadOrder().reversed) {
      _plugins[pluginId]!.stop(context);
    }
  }

  /// Calls [GamePlugin.unregister] on every plugin in reverse dependency
  /// order, then clears the registry.
  void unregister(PluginContext context) {
    for (final pluginId in resolveLoadOrder().reversed) {
      _plugins[pluginId]!.unregister(context);
    }
    _plugins.clear();
    _loadOrder = null;
  }
}
