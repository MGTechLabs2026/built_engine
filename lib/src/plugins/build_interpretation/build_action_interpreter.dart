import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// The generic Build -> Action contract: turns a [ResolvedBuild] (Core, no
/// content vocabulary) into [CombatAction] candidates (Combat, no content
/// vocabulary either) for [actor] against [targets]. Plugins implement
/// this directly to interpret their own content — no registry, the same
/// "no registry required" pattern `Condition`/`Effect`/`PlacementRule`/
/// `CombatAction`/`TrainingExercise`/`ActionSelector`/`TargetSelector`
/// already use throughout this engine.
///
/// This is the "Build Interpreter" stage of the target pipeline:
///
///   Tome -> ResolvedBuild -> Build Interpreter -> Available Actions ->
///   AutoCombat -> CombatSystem
///
/// Lives in its own module (`lib/src/plugins/build_interpretation/`),
/// mirroring how `AutoCombat` is its own layer built on top of Combat
/// rather than living inside it — Combat stays untouched, Core stays
/// untouched, and neither the Technique nor Item plugin needs to depend
/// on Combat just to run its own discovery/learning/mastery lifecycle;
/// only this bridging layer does.
abstract class BuildActionInterpreter {
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  });

  /// The `AuraRule`s (`package:build_engine/build_engine.dart`) to keep
  /// live while their owning component is hung — i.e. present in
  /// `build.active`. Fed to `AuraBinder`. Abstract: every interpreter in
  /// this repo uses `implements`, not `extends`, so a default body would
  /// not propagate. See
  /// `docs/superpowers/specs/2026-09-06-per-active-auras-sp2-design.md`.
  List<AuraRule> auraRules({
    required ResolvedBuild build,
    required PluginContext context,
  });
}
