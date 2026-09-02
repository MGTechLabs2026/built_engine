import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_events.dart';
import 'package:build_engine/src/plugins/technique/technique_inspiration.dart';
import 'package:test/test.dart';

void main() {
  test('InspirationResult.none is an empty, not-discovered result', () {
    expect(InspirationResult.none.discovered, isFalse);
    expect(InspirationResult.none.familyId, '');
    expect(InspirationResult.none.descriptorIds, isEmpty);
    expect(InspirationResult.none.inspirerInstanceIds, isEmpty);
  });

  test('Inspirer holds its instance, profile, mastery and usage', () {
    const i = Inspirer(
      instanceId: EntityId(3),
      axisProfile: {'power': 6, 'speed': -1},
      masteryLevel: 2,
      usage: 9,
    );
    expect(i.instanceId, const EntityId(3));
    expect(i.axisProfile['power'], 6);
    expect(i.masteryLevel, 2);
    expect(i.usage, 9);
  });

  test('TechniqueVariantInspired carries descriptors and inspirer ids', () {
    const e = TechniqueVariantInspired(
      owner: EntityId(1),
      instanceId: EntityId(2),
      familyId: 'basic_kick',
      descriptorIds: {'strong', 'swift'},
      inspirerInstanceIds: [EntityId(3), EntityId(4)],
    );
    expect(e.familyId, 'basic_kick');
    expect(e.descriptorIds, {'strong', 'swift'});
    expect(e.inspirerInstanceIds, [const EntityId(3), const EntityId(4)]);
  });
}
