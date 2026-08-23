import '../component/component_store.dart';
import '../entity/entity_id.dart';
import '../entity/entity_registry.dart';
import '../spatial/placement_exception.dart';
import '../spatial/position.dart';
import '../spatial/slot.dart';
import 'active_build.dart';
import 'build_component_ref.dart';
import 'build_resolver.dart';
import 'tome_definition.dart';
import 'tome_instance.dart';
import 'tome_placement.dart';

/// The generic Tome/Build system: insert, remove, move, replace, inspect,
/// validate, and resolve — built entirely on the existing `Container`
/// abstraction rather than a new `TomeGrid`/`BackpackGrid`.
///
/// The Tome is not an inventory; it's an active build configuration. This
/// class contains no combat logic and knows nothing about Combat — the
/// only thing it produces for anything else to consume is an
/// [ActiveBuild] snapshot via [resolve].
class TomeService {
  TomeService({required EntityRegistry entities, required ComponentStore components})
      : _entities = entities,
        _components = components;

  final EntityRegistry _entities;
  final ComponentStore _components;
  final Map<String, TomeDefinition> _definitions = {};
  final BuildResolver _resolver = const BuildResolver();

  /// Registers (or overwrites) [definition] under its [TomeDefinition.id].
  void defineTome(TomeDefinition definition) {
    _definitions[definition.id] = definition;
  }

  /// Builds a fresh Tome for [owner] from the registered [definitionId],
  /// attaching it as a [TomeInstance]. Overwrites any existing Tome
  /// [owner] already had (matching `ComponentStore.add`'s own overwrite
  /// semantics). Throws [ArgumentError] if [definitionId] was never
  /// [defineTome]d.
  TomeInstance createTome(EntityId owner, String definitionId) {
    final definition = _definitions[definitionId];
    if (definition == null) {
      throw ArgumentError.value(definitionId, 'definitionId', 'no TomeDefinition registered');
    }
    final instance = TomeInstance(
      definitionId: definitionId,
      container: definition.buildContainer(),
    );
    _components.add(owner, instance);
    return instance;
  }

  /// [owner]'s current [TomeInstance], or `null` if [createTome] was never
  /// called for it.
  TomeInstance? tomeOf(EntityId owner) => _components.get<TomeInstance>(owner);

  /// Whether [ref] could be [insert]ed at [slot] right now. Never mutates,
  /// never throws. `false` if [owner] has no Tome.
  bool validate(
    EntityId owner,
    SlotId slot, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
  }) {
    final instance = tomeOf(owner);
    if (instance == null) return false;
    return instance.container.canPlace(
      _previewItem,
      slot,
      size: size,
      rotation: rotation,
      extraRules: _definitions[instance.definitionId]?.extraPlacementRules ?? const [],
    );
  }

  /// A sentinel id never allocated by any real [EntityRegistry] (which
  /// starts at `1` and only increments) — safe to use as [Container
  /// .canPlace]'s required item identity for a placement preview that has
  /// no real backing entity yet.
  static const _previewItem = EntityId(-1);

  /// Places [ref] at [slot] for [owner], creating a fresh placeholder
  /// entity to carry it. Throws [InvalidPlacementException] if invalid —
  /// the placeholder entity is destroyed and nothing is left mutated in
  /// that case. Throws [StateError] if [owner] has no Tome.
  void insert(
    EntityId owner,
    SlotId slot,
    BuildComponentRef ref, {
    ItemSize size = const ItemSize(1, 1),
    Rotation rotation = Rotation.deg0,
  }) {
    final instance = tomeOf(owner);
    if (instance == null) {
      throw StateError('Owner has no Tome; call createTome first');
    }
    final item = _entities.create();
    _components.add(item, ref);
    try {
      instance.container.place(
        item,
        slot,
        size: size,
        rotation: rotation,
        extraRules: _definitions[instance.definitionId]?.extraPlacementRules ?? const [],
      );
    } on InvalidPlacementException {
      _components.remove<BuildComponentRef>(item);
      _entities.destroy(item);
      rethrow;
    }
  }

  /// Removes whatever occupies [slot] in [owner]'s Tome, destroying its
  /// placeholder entity. A no-op if [owner] has no Tome, or [slot] is
  /// empty.
  void remove(EntityId owner, SlotId slot) {
    final instance = tomeOf(owner);
    if (instance == null) return;
    final item = instance.container.itemAt(slot);
    if (item == null) return;
    instance.container.remove(item);
    _components.remove<BuildComponentRef>(item);
    _entities.destroy(item);
  }

  /// Moves whatever occupies [fromSlot] to [toSlot], preserving its size
  /// and rotation. Throws [InvalidPlacementException] if the new position
  /// is invalid — the placement is left unchanged in that case (the same
  /// atomicity `Container.move` already guarantees). A no-op if [owner]
  /// has no Tome, or [fromSlot] is empty.
  void move(EntityId owner, SlotId fromSlot, SlotId toSlot) {
    final instance = tomeOf(owner);
    if (instance == null) return;
    final item = instance.container.itemAt(fromSlot);
    if (item == null) return;
    instance.container.move(
      item,
      toSlot,
      size: instance.container.sizeOf(item) ?? const ItemSize(1, 1),
      rotation: instance.container.rotationOf(item) ?? Rotation.deg0,
      extraRules: _definitions[instance.definitionId]?.extraPlacementRules ?? const [],
    );
  }

  /// Replaces whatever occupies [slot] with [newRef], preserving the prior
  /// occupant's size/rotation if there was one — otherwise behaves exactly
  /// like [insert] at the default 1x1 size. Implemented as [remove] then
  /// [insert], reusing both directly.
  void replace(EntityId owner, SlotId slot, BuildComponentRef newRef) {
    final instance = tomeOf(owner);
    if (instance == null) return;
    final existing = instance.container.itemAt(slot);
    var size = const ItemSize(1, 1);
    var rotation = Rotation.deg0;
    if (existing != null) {
      size = instance.container.sizeOf(existing) ?? size;
      rotation = instance.container.rotationOf(existing) ?? rotation;
      remove(owner, slot);
    }
    insert(owner, slot, newRef, size: size, rotation: rotation);
  }

  /// Every current placement in [owner]'s Tome. Empty if [owner] has no
  /// Tome.
  List<TomePlacement> inspect(EntityId owner) {
    final instance = tomeOf(owner);
    if (instance == null) return const [];
    return [
      for (final item in instance.container.placedItems)
        TomePlacement(
          slot: instance.container.anchorOf(item)!,
          buildComponentRef: _components.get<BuildComponentRef>(item)!,
          size: instance.container.sizeOf(item)!,
          rotation: instance.container.rotationOf(item)!,
        ),
    ];
  }

  /// Resolves [owner]'s current Tome contents into an [ActiveBuild]
  /// snapshot via [BuildResolver] — the only thing anything outside the
  /// Tome (e.g. Combat) is meant to consume. Empty if [owner] has no Tome.
  ActiveBuild resolve(EntityId owner) => _resolver.resolve(owner, inspect(owner));
}
