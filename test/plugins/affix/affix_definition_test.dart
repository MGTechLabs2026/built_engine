// test/plugins/affix/affix_definition_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

ContentDefinition _load(ContentRegistry r, Map<String, dynamic> json) => r.load(json);

Map<String, dynamic> _keen() => {
      'id': 'af_keen',
      'type': 'affix',
      'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral'],
      'label': 'Keen',
      'category': 'item_prefix',
      'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 3},
    };

void main() {
  test('affixDefinitionFromContent maps every field', () {
    final r = ContentRegistry();
    final def = affixDefinitionFromContent(_load(r, _keen()));
    expect(def.id, 'af_keen');
    expect(def.label, 'Keen');
    expect(def.category, AffixCategories.itemPrefix);
    expect(def.lean, AffixLean.neutral);
    expect(def.mechanic, isA<WeaponStatBonus>().having((m) => m.amount, 'amount', 3));
  });

  test('missing label / bad category / missing lean tag each throw ContentFieldException', () {
    final r = ContentRegistry();
    expect(() => affixDefinitionFromContent(_load(r, {..._keen(), 'id': 'a1'}..remove('label'))),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'label')));
    expect(() => affixDefinitionFromContent(_load(r, {..._keen(), 'id': 'a2', 'category': 'nope'})),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'category')));
    expect(
        () => affixDefinitionFromContent(
            _load(r, {..._keen(), 'id': 'a3', 'tags': ['affix', 'affix_pool:item_prefix']})),
        throwsA(isA<ContentFieldException>().having((e) => e.path, 'path', 'tags')));
  });

  test('AffixPoolTags.forSlot builds the tag string', () {
    expect(AffixPoolTags.forSlot(AffixDomain.item, 'prefix'), 'affix_pool:item_prefix');
    expect(AffixPoolTags.forSlot(AffixDomain.technique, 'suffix'), 'affix_pool:technique_suffix');
  });
}
