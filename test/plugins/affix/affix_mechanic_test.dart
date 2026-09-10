// test/plugins/affix/affix_mechanic_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart' show ContentFieldException;
import 'package:test/test.dart';

void main() {
  test('fromJson dispatches on kind and reads amount', () {
    expect(AffixMechanic.fromJson({'kind': 'weapon_stat_bonus', 'amount': 3}),
        isA<WeaponStatBonus>().having((m) => m.amount, 'amount', 3));
    expect(AffixMechanic.fromJson({'kind': 'heal', 'amount': 12}),
        isA<ImmediateHeal>().having((m) => m.amount, 'amount', 12));
    expect(AffixMechanic.fromJson({'kind': 'bank_progression', 'amount': 2}),
        isA<BankProgression>().having((m) => m.amount, 'amount', 2));
  });

  test('unknown kind throws ContentFieldException on mechanic.kind', () {
    expect(() => AffixMechanic.fromJson({'kind': 'teleport', 'amount': 1}),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'mechanic.kind')));
  });

  test('missing / non-num amount throws ContentFieldException on mechanic.amount', () {
    expect(() => AffixMechanic.fromJson({'kind': 'heal'}),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'mechanic.amount')));
    expect(() => AffixMechanic.fromJson({'kind': 'heal', 'amount': 'lots'}),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'mechanic.amount')));
  });
}
