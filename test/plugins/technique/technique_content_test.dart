import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_content.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  test('the full technique roster loads through ContentRegistry — the three '
      'original families deepened to master, plus palm/finger/kick', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);

    for (final id in [
      TechniqueIds.basicPunch,
      TechniqueIds.preciseJab, TechniqueIds.lightningJab,
      TechniqueIds.hammerBlow, TechniqueIds.mountainBreaker,
      TechniqueIds.flashStrike, TechniqueIds.thunderFlash,
      TechniqueIds.basicSlash,
      TechniqueIds.flashingSlash, TechniqueIds.lightningSlash,
      TechniqueIds.cleavingSlash, TechniqueIds.mountainCleave,
      TechniqueIds.basicGuard,
      TechniqueIds.rollingGuard,
      TechniqueIds.turningGuard, TechniqueIds.stillWaterGuard,
      TechniqueIds.basicPalm, TechniqueIds.focusedPalm, TechniqueIds.pushingPalm,
      TechniqueIds.ironPalm, TechniqueIds.thunderPalm, TechniqueIds.stillPalm,
      TechniqueIds.basicFinger, TechniqueIds.fingerStrike, TechniqueIds.needleFinger,
      TechniqueIds.piercingFinger, TechniqueIds.lightningFinger,
      TechniqueIds.basicKick, TechniqueIds.snapKick, TechniqueIds.thrustKick,
      TechniqueIds.spinningKick, TechniqueIds.whirlwindKick, TechniqueIds.crescentKick,
    ]) {
      expect(registry.find(id), isNotNull, reason: '$id should be loaded');
    }
  });

  test('every form carries a rarity tag; every evolution targetId resolves; '
      'the four tiers form a strictly deepening ladder', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);
    const rarities = {'rarity:common', 'rarity:uncommon', 'rarity:rare', 'rarity:master'};
    int rank(String tier) => const [
          EvolutionTiers.basic,
          EvolutionTiers.intermediate,
          EvolutionTiers.advanced,
          EvolutionTiers.master,
        ].indexOf(tier);

    for (final raw in techniqueContentDefinitions) {
      final parent = techniqueDefinitionFromContent(registry.get(raw['id'] as String));
      expect((raw['tags'] as List).cast<String>().any(rarities.contains), isTrue,
          reason: '${parent.id} needs a rarity tag');
      for (final e in (raw['evolution'] as List? ?? const [])) {
        final child = techniqueDefinitionFromContent(
            registry.get((e as Map)['targetId'] as String));
        expect(rank(child.tier), greaterThan(rank(parent.tier)),
            reason: '${parent.id} (${parent.tier}) -> ${child.id} (${child.tier})');
      }
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

  test('a master-tier technique is terminal — no further evolution candidates', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);
    final lightningJab =
        techniqueDefinitionFromContent(registry.get(TechniqueIds.lightningJab));

    expect(lightningJab.evolutionCandidates, isEmpty);
    expect(lightningJab.tier, equals(EvolutionTiers.master));
  });

  test('an intermediate form now carries its own evolution path and training '
      'weights toward the advanced tier', () {
    final registry = ContentRegistry();
    registry.loadAll(techniqueContentDefinitions);
    final lightPunch =
        techniqueDefinitionFromContent(registry.get(TechniqueIds.lightPunch));

    expect(lightPunch.tier, equals(EvolutionTiers.intermediate));
    expect(lightPunch.evolutionCandidates.single.targetId,
        equals(TechniqueIds.preciseJab));
    expect(lightPunch.trainingWeights, isNotEmpty);
  });
}
