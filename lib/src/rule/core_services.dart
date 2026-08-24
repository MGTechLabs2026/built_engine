import '../component/component_store.dart';
import '../discovery/discovery_tracker.dart';
import '../event/event_bus.dart';
import '../mastery/mastery_tracker.dart';
import '../progression/progression_engine.dart';
import '../resource/resource_pool.dart';

/// Bundles the four Core services that `PluginContext` and `RuleEngine`
/// each default independently when not explicitly supplied
/// (`ResourcePool`/`MasteryTracker`/`ProgressionEngine`/`DiscoveryTracker`)
/// — fixes the footgun `ARCHITECTURE_AUDIT.md`'s Additional Observation A
/// flagged: a `PluginContext` and a `RuleEngine` built from the same
/// `ComponentStore`/`EventBus` but relying on their own unsupplied
/// defaults silently end up with *different* tracker instances, so a
/// `Rule` fired through `RuleEngine` reads/writes a different
/// `MasteryTracker`/`DiscoveryTracker` than code writing through
/// `PluginContext.mastery`/`.discovery` directly.
///
/// Construct one `CoreServices` and pass it as `shared:` to both
/// `PluginContext(...)` and `RuleEngine(...)` to make that divergence
/// structurally impossible — both then resolve to the exact same
/// instances. Purely additive: `PluginContext`/`RuleEngine` still accept
/// their four individual optional parameters directly, unchanged, for
/// every caller that doesn't need cross-construction sharing; an
/// explicit individual parameter always takes priority over `shared`.
///
/// Lives in `lib/src/rule/` (not `lib/src/plugin/`) deliberately:
/// `RuleEngine` needs this type and `lib/src/rule/` has no dependency on
/// `lib/src/plugin/` — placing it there instead would have created a
/// `rule -> plugin -> rule` cycle, since `PluginContext` already depends
/// on `RuleEngine`.
class CoreServices {
  factory CoreServices({
    required ComponentStore components,
    required EventBus events,
    ResourcePool? resources,
    MasteryTracker? mastery,
    ProgressionEngine? progression,
    DiscoveryTracker? discovery,
  }) {
    final sharedMastery =
        mastery ?? MasteryTracker(components: components, events: events);
    return CoreServices._(
      resources: resources ?? ResourcePool(components: components, events: events),
      mastery: sharedMastery,
      progression: progression ??
          ProgressionEngine(components: components, events: events, mastery: sharedMastery),
      discovery: discovery ?? DiscoveryTracker(components: components, events: events),
    );
  }

  CoreServices._({
    required this.resources,
    required this.mastery,
    required this.progression,
    required this.discovery,
  });

  final ResourcePool resources;
  final MasteryTracker mastery;
  final ProgressionEngine progression;
  final DiscoveryTracker discovery;
}
