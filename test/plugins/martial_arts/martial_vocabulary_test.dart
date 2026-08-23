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
}
