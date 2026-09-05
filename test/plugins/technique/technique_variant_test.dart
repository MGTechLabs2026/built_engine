// test/plugins/technique/technique_variant_test.dart
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_variant.dart';
import 'package:test/test.dart';

void main() {
  test('holds its owner, family, descriptors, resolved profile and style', () {
    const v = TechniqueVariant(
      owner: EntityId(1),
      baseFamilyId: 'basic_punch',
      descriptorIds: {'bear', 'thunder'},
      axisProfile: {'power': 13, 'speed': -1},
      styleId: 'wing_chun',
    );
    expect(v.owner, const EntityId(1));
    expect(v.baseFamilyId, 'basic_punch');
    expect(v.descriptorIds, {'bear', 'thunder'});
    expect(v.axisProfile, {'power': 13, 'speed': -1});
    expect(v.styleId, 'wing_chun');
  });

  test('a basic variant has an empty descriptor set and null style', () {
    const v = TechniqueVariant(
      owner: EntityId(2),
      baseFamilyId: 'basic_kick',
      descriptorIds: {},
      axisProfile: {},
    );
    expect(v.descriptorIds, isEmpty);
    expect(v.axisProfile, isEmpty);
    expect(v.styleId, isNull);
  });

  group('effectProfile (EffectContributor)', () {
    test('axisProfile power maps to the active tier under the "power" key', () {
      const variant = TechniqueVariant(
        owner: EntityId(1), baseFamilyId: 'basic_punch',
        descriptorIds: {'strong'}, axisProfile: {'power': 4, 'speed': -1},
      );
      final profile = variant.effectProfile();
      expect(profile.amount(EffectTier.active, 'power'), 4);
      expect(profile.tier(EffectTier.permanent), isEmpty);
      expect(profile.tier(EffectTier.supporting), isEmpty);
    });

    test('no power axis -> active tier empty (not a missing-key crash)', () {
      const variant = TechniqueVariant(
        owner: EntityId(1), baseFamilyId: 'basic_guard',
        descriptorIds: {}, axisProfile: {},
      );
      expect(variant.effectProfile().amount(EffectTier.active, 'power'), 0);
    });

    test('other axes (speed/precision/endurance) are not surfaced by '
        'effectProfile — SP1 (tiered effects) introduces no new stat keys',
        () {
      const variant = TechniqueVariant(
        owner: EntityId(1), baseFamilyId: 'basic_kick',
        descriptorIds: {}, axisProfile: {'speed': 5, 'precision': 3},
      );
      final profile = variant.effectProfile();
      expect(profile.tier(EffectTier.active),
          <String, num>{}); // no 'power' key present at all
    });
  });
}
