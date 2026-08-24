import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('all 11 techniques load through ContentRegistry', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);

    for (final id in [
      TechniqueIds.basicPunch,
      TechniqueIds.basicSlash,
      TechniqueIds.basicGuard,
      TechniqueIds.lightPunch,
      TechniqueIds.heavyPunch,
      TechniqueIds.fastPunch,
      TechniqueIds.counterPunch,
      TechniqueIds.quickSlash,
      TechniqueIds.heavySlash,
      TechniqueIds.fastGuard,
      TechniqueIds.counterGuard,
    ]) {
      expect(registry.find(id), isNotNull, reason: '$id should be loaded');
    }
  });

  test('techniqueDefinitionFromContent parses name/tier/properties/evolution', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);

    final basicPunch = techniqueDefinitionFromContent(registry.get(TechniqueIds.basicPunch));

    expect(basicPunch.name, equals('Basic Punch'));
    expect(basicPunch.tier, equals(EvolutionTiers.basic));
    expect(basicPunch.properties['damage'], equals(6));
    expect(basicPunch.evolutionCandidates, hasLength(4));
    expect(
      basicPunch.evolutionCandidates.map((c) => c.targetId),
      containsAll([
        TechniqueIds.lightPunch,
        TechniqueIds.heavyPunch,
        TechniqueIds.fastPunch,
        TechniqueIds.counterPunch,
      ]),
    );
  });

  test('candidate tags match TrainingDimensions vocabulary', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);
    final basicPunch = techniqueDefinitionFromContent(registry.get(TechniqueIds.basicPunch));

    final fastPunch = basicPunch.evolutionCandidates
        .firstWhere((c) => c.targetId == TechniqueIds.fastPunch);

    expect(fastPunch.tags, contains(TrainingDimensions.speed));
  });

  test('an evolved (terminal) technique has no further evolution candidates', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);
    final lightPunch = techniqueDefinitionFromContent(registry.get(TechniqueIds.lightPunch));

    expect(lightPunch.evolutionCandidates, isEmpty);
    expect(lightPunch.tier, equals(EvolutionTiers.intermediate));
  });
}
