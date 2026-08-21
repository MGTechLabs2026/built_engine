import 'plugin_context.dart';

/// The contract every plugin implements. Core services never depend on any
/// concrete `GamePlugin` — this is the only shape core code knows about.
///
/// [dependencies] and every lifecycle method default to a no-op / empty list
/// so a plugin only needs to override what it actually uses. [id] and
/// [version] have no sensible default and must be overridden.
abstract class GamePlugin {
  /// A stable, globally-unique identifier for this plugin, e.g. `"combat"`.
  String get id;

  /// This plugin's own version string, e.g. `"1.0.0"`.
  String get version;

  /// The ids of plugins that must be registered, initialized, and started
  /// before this one. See `PluginManager.resolveLoadOrder`.
  List<String> get dependencies => const [];

  /// Called first, in dependency order, for every registered plugin before
  /// any plugin's [initialize] runs.
  void register(PluginContext context) {}

  /// Called after every plugin has [register]ed, in dependency order.
  void initialize(PluginContext context) {}

  /// Called after every plugin has [initialize]d, in dependency order.
  void start(PluginContext context) {}

  /// Called in reverse dependency order when the plugin set is torn down.
  void stop(PluginContext context) {}

  /// Called in reverse dependency order, after every plugin has [stop]ped.
  void unregister(PluginContext context) {}
}
