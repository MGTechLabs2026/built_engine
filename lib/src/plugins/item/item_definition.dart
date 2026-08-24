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
///
/// [maxClass]/[gradeEvolutionCandidates]/[classScalingPercent] are the
/// Combine feature's data
/// (`docs/superpowers/specs/2026-08-24-item-combine-design.md`):
/// `maxClass == null` means this item never opted into Combine at all;
/// `gradeEvolutionCandidates` mirrors `TechniqueDefinition
/// .evolutionCandidates` byte-for-byte (candidates travel with the
/// content definition itself, no separate registry).
class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.category,
    required this.tags,
    required this.properties,
    this.requirement,
    this.trainingWeights = const {},
    this.modifiersFor = _noModifiers,
    this.maxClass,
    this.gradeEvolutionCandidates = const [],
    this.classScalingPercent = 15,
  });

  final String id;
  final String category;
  final Set<String> tags;
  final Map<String, num> properties;
  final ItemRequirement? requirement;
  final Map<String, double> trainingWeights;
  final List<Modifier> Function(EntityId owner) modifiersFor;
  final int? maxClass;
  final List<EvolutionCandidate> gradeEvolutionCandidates;
  final num classScalingPercent;

  static List<Modifier> _noModifiers(EntityId owner) => const [];

  /// Builds the `EvolutionDefinition` this item's grade branches
  /// represent, for `EvolutionResolver.resolve` to consume — exactly
  /// mirrors `TechniqueDefinition.toEvolutionDefinition()`
  /// (`technique_definition.dart`). `tier` is passed through as
  /// [category] purely for descriptive/organizational value —
  /// `EvolutionDefinition.tier` is never read by the resolver.
  EvolutionDefinition toGradeEvolutionDefinition() =>
      EvolutionDefinition(id: id, tier: category, candidates: gradeEvolutionCandidates);

  /// Pure per-class stat scaling: `base * (1 + classScalingPercent/100 *
  /// (itemClass-1))` per property. Used by `ItemActionInterpreter`
  /// (`lib/src/plugins/build_interpretation/item_action_interpreter.dart`)
  /// instead of raw [properties] once it knows a placement's live
  /// `itemClass`.
  Map<String, num> scaledProperties(int itemClass) => {
        for (final entry in properties.entries)
          entry.key: entry.value * (1 + classScalingPercent / 100 * (itemClass - 1)),
      };
}
