import 'package:build_engine/martial_arts_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('MartialResources names the two MartialArts resources', () {
    expect(MartialResources.qi, equals('qi'));
    expect(MartialResources.momentum, equals('momentum'));
  });

  test('MartialStances names the three MartialArts stance tags', () {
    expect(MartialStances.guard, equals('stance:guard'));
    expect(MartialStances.ironBody, equals('stance:iron_body'));
    expect(MartialStances.taiChi, equals('stance:tai_chi'));
  });

  test('MartialItemIds names all 8 items/trinkets', () {
    expect(MartialItemIds.brassKnuckles, equals('brass_knuckles'));
    expect(MartialItemIds.ironPalmWraps, equals('iron_palm_wraps'));
    expect(MartialItemIds.taiChiSilkSash, equals('tai_chi_silk_sash'));
    expect(MartialItemIds.sparringGloves, equals('sparring_gloves'));
    expect(MartialItemIds.weightedVest, equals('weighted_vest'));
    expect(MartialItemIds.momentumTrinket, equals('momentum_trinket'));
    expect(MartialItemIds.qiPendant, equals('qi_pendant'));
    expect(MartialItemIds.counterstrikeRing, equals('counterstrike_ring'));
  });
}
