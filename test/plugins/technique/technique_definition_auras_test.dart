import 'package:build_engine/build_engine.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('techniqueDefinitionFromContent reads the auras id list', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'test_tech',
      'type': 'technique',
      'tags': <String>[],
      'name': 'Test',
      'tier': 'basic',
      'properties': {'damage': 3},
      'auras': ['aura.venom'],
    });
    expect(techniqueDefinitionFromContent(def).auraRuleIds, ['aura.venom']);
  });

  test('a technique with no auras key has an empty auraRuleIds', () {
    final registry = ContentRegistry();
    final def = registry.load({
      'id': 'plain_tech',
      'type': 'technique',
      'tags': <String>[],
      'name': 'Plain',
      'tier': 'basic',
      'properties': {'damage': 2},
    });
    expect(techniqueDefinitionFromContent(def).auraRuleIds, isEmpty);
  });
}
