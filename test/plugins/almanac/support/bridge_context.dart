/// A thin real [PluginContext] for the Phase 7 bridge unit tests — Core
/// services only, no gameplay plugins, built the same way `game_run.dart`
/// builds its own (`ARCHITECTURE.md`'s bootstrap example). Enough for the
/// bridge's `_context.tome.inspect` / `_context.mastery.levelOf` /
/// `_context.components` reads; the lifecycle / turn-counting / run-profile
/// tests never place anything in the Tome, so an empty one is fine.
library;

import 'package:build_engine/build_engine.dart';

/// A fresh Core-only [PluginContext] bound to [events].
PluginContext bridgeTestContext(EventBus events) {
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
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
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
}
