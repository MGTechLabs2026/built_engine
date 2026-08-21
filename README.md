# build_engine

A modular, data-driven game engine core, written in pure Dart.

The core provides generic verbs — entities, components, events, and a
plugin system — with no game-specific content of any kind. Game content
(martial arts, magic, cultivation, or anything else) is expected to live
entirely in plugins built on top of this foundation, never in the core
itself.

## Status

This repository currently contains the engine **foundation** only:

- `EntityId` — a sequential, deterministic entity identifier
- `EntityRegistry` — creates/destroys entities, publishes lifecycle events
- `ComponentStore` — generic per-type component storage, keyed by `Type`
- `EventBus` — typed publish/subscribe, dispatched by exact runtime type
- `GamePlugin` / `PluginContext` / `PluginManager` — the plugin interface,
  its execution context, and dependency-ordered lifecycle management

No content plugins, and no other engine subsystems (rules, effects,
modifiers, spatial/container queries, resources, scheduling, RNG,
serialization) exist yet — those are future work, each planned and built
as its own pass.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for how the implemented services
fit together, and [`PLUGIN_SYSTEM.md`](PLUGIN_SYSTEM.md) for the plugin
lifecycle and dependency-resolution details. The full architecture
contract this engine follows lives in [`claude.md`](claude.md).

## Requirements

- Dart SDK `^3.7.0`

This is a pure Dart package — it has no Flutter dependency, so it can be
tested and used headlessly.

## Getting started

```bash
dart pub get
dart test
dart analyze
```

## Package layout

```
lib/
  build_engine.dart        # public API barrel export
  src/
    entity/                # EntityId, EntityRegistry
    component/              # ComponentStore
    event/                  # EventBus
    plugin/                 # GamePlugin, PluginContext, PluginManager
test/
  ...                       # unit tests, one file per service
  integration/              # cross-service integration tests
```
