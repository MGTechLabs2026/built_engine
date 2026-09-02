import 'package:build_engine/build_engine.dart';

import 'technique_variant_lifecycle.dart' show requireTechniqueVariant;

/// Per-run tally of how many combat actions each of an owner's technique
/// variant instances has performed. Pure ECS state on the fighter entity.
/// Not persisted — a run's fresh `PluginContext` starts it empty, the
/// same lifetime bound SP0a's per-instance `MasteryDefinition`s have.
///
/// This file imports Core only. The `ActionCompleted` → usage bridge that
/// *feeds* it lives in the composition layer (it needs Combat's event
/// vocabulary, which `lib/src/plugins/technique/` may not name); it calls
/// [recordTechniqueVariantUsage].
class TechniqueUsageComponent {
  const TechniqueUsageComponent(this.byInstance);
  final Map<EntityId, int> byInstance;
}

/// `+1` to variant [instanceId]'s performed-action count on its owner's
/// [TechniqueUsageComponent] (created if absent). Owner is read from
/// `TechniqueVariant.owner` (rule 5). Throws
/// `TechniqueVariantNotFoundException` for an unknown instance id.
void recordTechniqueVariantUsage(EntityId instanceId, PluginContext context) {
  final owner = requireTechniqueVariant(instanceId, context).owner;
  final existing = context.components.get<TechniqueUsageComponent>(owner);
  final next = <EntityId, int>{...?existing?.byInstance};
  next[instanceId] = (next[instanceId] ?? 0) + 1;
  context.components.add<TechniqueUsageComponent>(
      owner, TechniqueUsageComponent(next));
}

/// Rebuilds the owner's [TechniqueUsageComponent] without [instanceId] —
/// the same rebuild pattern `removeTechniqueVariant` uses for
/// `MasteryComponent`. No-op if there is no component or no entry.
void forgetTechniqueVariantUsage(EntityId instanceId, PluginContext context) {
  final owner = requireTechniqueVariant(instanceId, context).owner;
  final existing = context.components.get<TechniqueUsageComponent>(owner);
  if (existing == null || !existing.byInstance.containsKey(instanceId)) return;
  final trimmed = Map<EntityId, int>.of(existing.byInstance)..remove(instanceId);
  context.components.add<TechniqueUsageComponent>(
      owner, TechniqueUsageComponent(trimmed));
}

/// Variant [instanceId]'s performed-action count this run — `0` if never
/// recorded. Owner read from `TechniqueVariant.owner`. Throws
/// `TechniqueVariantNotFoundException` for an unknown instance id.
int techniqueVariantUsage(EntityId instanceId, PluginContext context) {
  final owner = requireTechniqueVariant(instanceId, context).owner;
  final usage = context.components.get<TechniqueUsageComponent>(owner);
  return usage?.byInstance[instanceId] ?? 0;
}
