// test/plugins/affix/affix_content_test.dart
import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

void main() {
  test('33 entries: 11 / 9 / 7 / 6 per pool', () {
    int count(String cat) =>
        affixContentDefinitions.where((e) => e['category'] == cat).length;
    expect(affixContentDefinitions, hasLength(33));
    expect(count('item_prefix'), 11);
    expect(count('item_suffix'), 9);
    expect(count('technique_prefix'), 7);
    expect(count('technique_suffix'), 6);
  });

  test('every id is a distinct opaque af_* token, none equal to its label', () {
    final ids = affixContentDefinitions.map((e) => e['id'] as String).toList();
    expect(ids.toSet(), hasLength(33));
    for (final e in affixContentDefinitions) {
      final id = e['id'] as String;
      expect(id, startsWith('af_'));
      expect(id, isNot(equalsIgnoringCase(e['label'] as String)));
    }
  });

  test('every entry parses, and tag pool matches category + mechanic family', () {
    final r = ContentRegistry()..loadAll(affixContentDefinitions);
    for (final raw in affixContentDefinitions) {
      final def = affixDefinitionFromContent(r.get(raw['id'] as String));
      final tags = (raw['tags'] as List).cast<String>();
      expect(tags, contains('affix_pool:${def.category}'));
      final isItem =
          def.category == 'item_prefix' || def.category == 'item_suffix';
      expect(def.mechanic is WeaponStatBonus, isItem,
          reason: '${def.id}: item pools are weapon_stat_bonus, technique pools are heal/bank');
      expect(def.mechanic.amount, greaterThan(0));
    }
  });

  test('cross-pool labels have distinct ids', () {
    Map<String, dynamic> byId(String id) =>
        affixContentDefinitions.firstWhere((e) => e['id'] == id);
    expect(byId('af_flowing')['label'], 'Flowing');
    expect(byId('af_flowing_technique')['label'], 'Flowing');
    expect(byId('af_of_still_water')['label'], 'of Still Water');
    expect(byId('af_of_still_water_technique')['label'], 'of Still Water');
  });
}
