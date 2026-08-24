import 'package:build_engine/build_engine.dart';

import 'item_requirement.dart';

/// A piece of physical equipment's immutable, content-derived shape —
/// mirrors `MartialItemDefinition`/`ElementalItemDefinition`'s exact
/// shape (the third occurrence of an already-proven pattern, not a new
/// one). Instances are built from loaded content via
/// `itemDefinitionFromContent`/`itemDefinition` (`item_content.dart`),
/// never hand-written here. [category] is `ContentDefinition.type`
/// verbatim (`'weapon'`/`'armor'`/...) — no redundant second field.
/// [properties] are raw named values (`{'attack': 3}`) describing the
/// item; nothing here activates them as `Modifier`s automatically —
/// [modifiersFor] exposes that capability for a future pass (equip/
/// active-build interpretation) to call, per the milestone's "expose
/// enough information for ActiveBuild interpretation later, don't
/// implement full combat action conversion yet." [trainingWeights] is
/// content data too (`ARCHITECTURE_AUDIT.md`'s category-7 finding) —
/// previously a hand-written Dart constant in `item_training_weights.dart`
/// disconnected from `ContentRegistry`; now parsed the same way
/// [properties] is.
class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.category,
    required this.tags,
    required this.properties,
    this.requirement,
    this.trainingWeights = const {},
    this.modifiersFor = _noModifiers,
  });

  final String id;
  final String category;
  final Set<String> tags;
  final Map<String, num> properties;
  final ItemRequirement? requirement;
  final Map<String, double> trainingWeights;
  final List<Modifier> Function(EntityId owner) modifiersFor;

  static List<Modifier> _noModifiers(EntityId owner) => const [];
}
