import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

/// The generic Build -> Action contract: turns [ActiveBuild] (Core, no
/// content vocabulary) into [CombatAction] candidates (Combat, no content
/// vocabulary either) for [actor] against [targets]. Plugins implement
/// this directly to interpret their own content — no registry, the same
/// "no registry required" pattern `Condition`/`Effect`/`PlacementRule`/
/// `CombatAction`/`TrainingExercise`/`ActionSelector`/`TargetSelector`
/// already use throughout this engine.
///
/// This is the "Build Interpreter" stage of the target pipeline:
///
///   Tome -> ActiveBuild -> Build Interpreter -> Available Actions ->
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
    required ActiveBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  });
}
