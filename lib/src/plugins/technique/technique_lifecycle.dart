import 'package:build_engine/build_engine.dart';

import 'technique_definition.dart';
import 'technique_events.dart';
import 'technique_vocabulary.dart';

class TechniqueNotDiscoveredException implements Exception {
  const TechniqueNotDiscoveredException(this.definitionId);
  final String definitionId;
  @override
  String toString() => 'Technique not discovered: $definitionId';
}

class TechniqueRequirementsNotMetException implements Exception {
  const TechniqueRequirementsNotMetException(this.definitionId);
  final String definitionId;
  @override
  String toString() => 'Technique requirements not met: $definitionId';
}

class TechniqueNotLearnedException implements Exception {
  const TechniqueNotLearnedException(this.definitionId);
  final String definitionId;
  @override
  String toString() => 'Technique not learned: $definitionId';
}

/// The result of one [attemptToLearnTechnique] call — success (crossed the
/// single learning threshold) or partial progress, never both silently
/// conflated. Mirrors `TrainingResult`'s own "pure data, no hidden
/// decision" shape.
class LearningAttemptResult {
  const LearningAttemptResult({
    required this.learned,
    required this.experienceGained,
    required this.totalExperience,
  });

  final bool learned;
  final num experienceGained;
  final num totalExperience;
}

/// Moves [owner]'s discovery state for [technique] to `discovered` — the
/// DISCOVERED state. Delegates entirely to the existing generic
/// `DiscoveryTracker`.
void discoverTechnique(EntityId owner, TechniqueDefinition technique, PluginContext context) =>
    context.discovery.discover(owner, techniqueSubject(technique.id));

/// Whether [owner] has at least discovered [technique] — reuses the
/// generic `IsDiscovered` condition rather than reading `DiscoveryState`
/// directly, the same pattern `usabilityConditionsFor` (Item plugin) uses.
bool isTechniqueDiscovered(
  EntityId owner,
  TechniqueDefinition technique,
  PluginContext context,
) =>
    IsDiscovered(techniqueSubject(technique.id)).evaluate(context.ruleContextFor(owner));

/// Attempts to learn [technique]: requires [technique] to be at least
/// discovered (else [TechniqueNotDiscoveredException]) and every one of
/// [TechniqueDefinition.requirements] to pass (else
/// [TechniqueRequirementsNotMetException]) — the two hard gates on even
/// *attempting* to learn. On a met gate, adds [experienceGained] to the
/// LEARNING axis via `ProgressionEngine.addExperience` (the "generic
/// progression primitive" this milestone calls for — `ProgressionEngine`'s
/// own doc comment already names "technique learning" as an intended use).
/// Crossing the single registered threshold is SUCCESS (LEARNED);
/// otherwise this is PROGRESS, not failure in the sense of "nothing
/// happened" — `LearningAttemptResult.learned` is the caller's signal,
/// never an exception. Deliberately never touches Evolution — "do not
/// automatically evolve the technique when it is merely learned."
LearningAttemptResult attemptToLearnTechnique(
  EntityId owner,
  TechniqueDefinition technique,
  num experienceGained,
  PluginContext context,
) {
  if (!isTechniqueDiscovered(owner, technique, context)) {
    throw TechniqueNotDiscoveredException(technique.id);
  }
  final ruleContext = context.ruleContextFor(owner);
  final requirementsMet =
      technique.requirements.every((condition) => condition.evaluate(ruleContext));
  if (!requirementsMet) {
    throw TechniqueRequirementsNotMetException(technique.id);
  }

  final subject = techniqueKnowledgeSubject(technique.id);
  context.progression.addExperience(owner, subject, experienceGained);
  return LearningAttemptResult(
    learned: context.progression.tierOf(owner, subject) >= 1,
    experienceGained: experienceGained,
    totalExperience: context.progression.experienceOf(owner, subject),
  );
}

/// Whether [owner] has successfully learned [technique] — the LEARNED
/// state, read live from `ProgressionEngine.tierOf`. Never stored
/// separately; can't desync from the experience it's based on.
bool isTechniqueLearned(EntityId owner, TechniqueDefinition technique, PluginContext context) =>
    context.progression.tierOf(owner, techniqueKnowledgeSubject(technique.id)) >= 1;

/// Adds [amount] of proficiency to [owner]'s MASTERY of [technique] — the
/// third, independent axis. Deliberately unrelated to
/// [attemptToLearnTechnique]/[isTechniqueLearned]: different subject
/// string ([techniqueSubject], not [techniqueKnowledgeSubject]), so
/// training mastery never moves the learned state and vice versa.
void trainTechniqueMastery(
  EntityId owner,
  TechniqueDefinition technique,
  num amount,
  PluginContext context,
) =>
    context.mastery.increase(owner, techniqueSubject(technique.id), amount);

/// [owner]'s current mastery level for [technique] — `0` if no
/// `MasteryDefinition` was registered for this subject or none has been
/// reached yet.
int techniqueMasteryLevel(
  EntityId owner,
  TechniqueDefinition technique,
  PluginContext context,
) =>
    context.mastery.levelOf(owner, techniqueSubject(technique.id));

/// Inserts [technique] into [owner]'s Tome at [slot] — but only if
/// [isTechniqueLearned] first. Throws [TechniqueNotLearnedException]
/// (leaving the Tome untouched) otherwise; on success, publishes
/// [TechniqueAddedToTome]. Mirrors `ItemPlugin.addItemToTome` exactly —
/// same reasoning for gating here rather than inside `TomeService`.
void addTechniqueToTome(
  EntityId owner,
  SlotId slot,
  TechniqueDefinition technique,
  PluginContext context,
) {
  if (!isTechniqueLearned(owner, technique, context)) {
    throw TechniqueNotLearnedException(technique.id);
  }
  context.tome.insert(
    owner,
    slot,
    BuildComponentRef(referenceType: techniqueReferenceType, contentId: technique.id),
  );
  context.events.publish(TechniqueAddedToTome(owner, technique.id, slot));
}
