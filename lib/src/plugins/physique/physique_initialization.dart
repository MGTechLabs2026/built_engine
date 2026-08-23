import 'package:build_engine/build_engine.dart';

import 'physique_component.dart';
import 'physique_content.dart';
import 'physique_events.dart';
import 'physique_types.dart';

/// The one generic character-initialization mechanism this plugin
/// provides: given [character] and [context], ensures it has exactly
/// one [PhysiqueComponent] (idempotent — a character that already has
/// one is left untouched, and its existing id is returned), selecting
/// uniformly among [PhysiqueTypes.all] via `context.rng` — never
/// `dart:math` directly, so the same seed and the same sequence of
/// prior `RngService` draws always produce the same physique. Registers
/// the selected physique's synergy `Modifier`s and publishes
/// [PhysiqueAssigned].
///
/// Deliberately a plain function, not a `Rule` reacting to
/// `EntityCreated` — not every entity Core creates is a "character"
/// (battle entities, item entities, ...), so nothing about entity
/// creation alone says when this should run. Whoever creates a
/// character (a future content plugin, a game's own character-creation
/// flow — never this plugin, and never a game-specific
/// "NewGameManager") calls this explicitly, the same way
/// `learnStyle`/`attuneToElement`/`equipItem` are each called
/// explicitly rather than wired to fire automatically.
String initializePhysique(EntityId character, PluginContext context) {
  final existing = context.components.get<PhysiqueComponent>(character);
  if (existing != null) return existing.physiqueId;

  final physiqueId =
      PhysiqueTypes.all[context.rng.nextInt(PhysiqueTypes.all.length)];
  final definition =
      physiqueDefinitionFromContent(context.content.get(physiqueId));

  context.components.add(character, PhysiqueComponent(physiqueId));
  for (final modifier in definition.modifiersFor(character)) {
    context.modifiers.add(modifier);
  }
  context.events.publish(PhysiqueAssigned(character, physiqueId));

  return physiqueId;
}
