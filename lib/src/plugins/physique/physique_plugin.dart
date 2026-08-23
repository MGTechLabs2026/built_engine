import 'package:build_engine/build_engine.dart';

import 'physique_component.dart';
import 'physique_content.dart';
import 'physique_types.dart';

/// Physique as an ordinary content plugin: four body-type definitions
/// (Sturdy/Power/Burst/Endurance), each with a primary affinity and a
/// pair of conditional synergy `Modifier`s, expressed entirely through
/// Core's public APIs. Depends on nothing but Core (`dependencies =>
/// const []`) — not Combat, not MartialArts. Interoperates with
/// MartialArts purely through the generic `'western'`/`'eastern'` tags
/// MartialArts' own `learnStyle` grants a character — see
/// `ARCHITECTURE.md`'s Physique section for the full design.
class PhysiquePlugin extends GamePlugin {
  @override
  String get id => 'physique';

  @override
  String get version => '0.1.0';

  /// Constructed in [initialize]; not `late final` since a plugin can
  /// be `initialize`d again after `unregister`.
  late PluginSdk sdk;

  @override
  void initialize(PluginContext context) {
    sdk = PluginSdk(context);

    sdk.registerComponentCleanup<PhysiqueComponent>();

    sdk.registerTag('physique',
        description: 'Any physique-related entity or content.');
    sdk.registerTag('defense', description: "Sturdy's primary affinity.");
    sdk.registerTag('strength', description: "Power's primary affinity.");
    sdk.registerTag('speed', description: "Burst's primary affinity.");
    sdk.registerTag('stamina',
        description: "Endurance's primary affinity.");
    sdk.registerTag('western_affinity',
        description:
            'A physique with strong synergy with western martial traditions.');
    sdk.registerTag('eastern_affinity',
        description:
            'A physique with strong synergy with eastern martial traditions.');

    // ContentRegistry has no unload operation, so content loaded here
    // outlives unregister — guard against loading it twice if this
    // plugin is initialize()d again on the same context afterward.
    if (context.content.find(PhysiqueTypes.sturdy) == null) {
      sdk.registerContentBatch(physiqueContentDefinitions);
    }
  }

  /// Mirrors [initialize]: cancels every subscription [sdk] took out —
  /// component cleanup — so an unregistered `PhysiquePlugin` stops
  /// reacting to events entirely.
  @override
  void unregister(PluginContext context) {
    sdk.disposeAll();
  }
}
