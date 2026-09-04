import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';

import 'build_action_interpreter.dart';

/// Combines several [BuildActionInterpreter]s into one — each interpreter
/// sees the *whole* [ActiveBuild] (not a pre-filtered subset), so an item
/// interpreter can react to techniques being present and vice versa if a
/// future interpreter ever needs that; for now each interpreter simply
/// filters to the `referenceType`s it understands and ignores the rest.
/// Results are concatenated in [interpreters] order — deterministic, no
/// re-sorting/de-duplication.
class CompositeBuildActionInterpreter implements BuildActionInterpreter {
  const CompositeBuildActionInterpreter(this.interpreters);

  final List<BuildActionInterpreter> interpreters;

  @override
  List<CombatAction> interpret({
    required ResolvedBuild build,
    required EntityId actor,
    required List<EntityId> targets,
    required PluginContext context,
  }) =>
      [
        for (final interpreter in interpreters)
          ...interpreter.interpret(
            build: build,
            actor: actor,
            targets: targets,
            context: context,
          ),
      ];
}
