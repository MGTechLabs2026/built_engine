/// Base type for every exception thrown by the plugin system.
abstract class PluginSystemException implements Exception {
  const PluginSystemException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by [PluginManager.register] when a plugin with the same [id] is
/// already registered.
class DuplicatePluginException extends PluginSystemException {
  DuplicatePluginException(String pluginId)
      : super('Plugin already registered: $pluginId');
}

/// Thrown by [PluginManager.resolveLoadOrder] when a plugin declares a
/// dependency on a plugin id that was never registered.
class MissingPluginDependencyException extends PluginSystemException {
  MissingPluginDependencyException(String pluginId, String missingDependencyId)
      : super(
          'Plugin "$pluginId" depends on unknown plugin '
          '"$missingDependencyId"',
        );
}

/// Thrown by [PluginManager.resolveLoadOrder] when plugin dependencies form
/// a cycle. [cycle] lists the plugin ids in the cycle, in order, with the
/// first id repeated at the end to show where it closes.
class CyclicPluginDependencyException extends PluginSystemException {
  CyclicPluginDependencyException(List<String> cycle)
      : super('Cyclic plugin dependency detected: ${cycle.join(' -> ')}');
}
