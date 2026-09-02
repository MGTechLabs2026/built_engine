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
}
