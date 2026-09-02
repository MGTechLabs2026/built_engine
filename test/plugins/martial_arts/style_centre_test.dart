import 'package:build_engine/src/plugins/martial_arts/martial_styles.dart';
import 'package:build_engine/src/plugins/martial_arts/style_centre.dart';
import 'package:test/test.dart';

const _families = [
  'basic_punch', 'basic_slash', 'basic_guard',
  'basic_palm', 'basic_finger', 'basic_kick',
];
const _styles = [
  MartialStyles.polearming, MartialStyles.wrestling, MartialStyles.fencing,
  MartialStyles.shaolin, MartialStyles.taiChi, MartialStyles.kunlun,
];

void main() {
  test('a known style/family pair returns its nudge', () {
    expect(styleCentre(MartialStyles.wrestling, 'basic_punch'), {'power': 3});
    expect(styleCentre(MartialStyles.taiChi, 'basic_guard'), {'endurance': 3});
  });

  test('an unknown style or family returns an empty map', () {
    expect(styleCentre('made_up_style', 'basic_punch'), isEmpty);
    expect(styleCentre(MartialStyles.shaolin, 'made_up_family'), isEmpty);
  });

  test('every shipped style × base family resolves without throwing', () {
    for (final s in _styles) {
      for (final f in _families) {
        final centre = styleCentre(s, f);
        expect(centre, isA<Map<String, num>>());
        for (final v in centre.values) {
          expect(v, isA<num>());
        }
      }
    }
  });
}
