import 'package:build_engine/build_engine.dart';
import 'package:build_engine/consumable_plugin.dart';

/// Grants each hung consumable's per-fight charges as a `ResourcePool`
/// value on the build owner, and — on `dispose()` — zeroes those pools
/// and removes any `consumable:*` `Modifier` a `GrantModifier` effect
/// added this fight. Sibling of `AuraBinder`: created per resolved build
/// (per fight in the harness), disposed at fight end.
///
/// `grant()` is NOT an in-place reconciliation mechanism (SP3 §5.5): a
/// placement change is applied by `dispose()` old → resolve new build →
/// `grant()` again. `grant()` only `set`s the keys present in ITS
/// `build.active`; `dispose()` is what zeroes the key of a consumable
/// that dropped out. Calling `grant()` twice without an intervening
/// `dispose()` is unsupported.
class ConsumableBinder {
  const ConsumableBinder();

  ConsumableCharges grant({
    required ResolvedBuild build,
    required PluginContext context,
  }) {
    final byContent = <String, int>{};
    for (final ref in build.active) {
      if (ref.referenceType != consumableReferenceType) continue;
      final def = context.content.find(ref.contentId);
      if (def == null) continue;
      final charges = consumableDefinitionFromContent(def).charges;
      byContent[ref.contentId] = (byContent[ref.contentId] ?? 0) + charges;
    }
    for (final entry in byContent.entries) {
      // Authoritative aggregate write. The resource is defined
      // `max: double.infinity`, so `set` is a plain assignment — 3 hung
      // copies → 3, never clamped to one copy's `charges`.
      context.resources.set(build.owner, consumableChargeResource(entry.key), entry.value);
    }
    return ConsumableCharges._(
      owner: build.owner,
      contentIds: byContent.keys.toList(growable: false),
      resources: context.resources,
      modifiers: context.modifiers,
    );
  }
}

/// The disposable handle from [ConsumableBinder.grant]. Membership is
/// fixed at construction (no update path). [dispose] is idempotent.
class ConsumableCharges {
  ConsumableCharges._({
    required this.owner,
    required this.contentIds,
    required this.resources,
    required this.modifiers,
  });

  final EntityId owner;
  final List<String> contentIds;
  final ResourcePool resources;
  final ModifierCollection modifiers;
  var _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in contentIds) {
      resources.set(owner, consumableChargeResource(id), 0);
      modifiers.removeBySource(ModifierSource('consumable:$id:${owner.value}'));
    }
  }
}
