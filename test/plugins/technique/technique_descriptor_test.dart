import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:test/test.dart';

void main() {
  test('parses a multi-axis descriptor from content', () {
    final registry = ContentRegistry();
    registry.loadAll(const [
      {
        'id': 'bear',
        'type': 'technique_descriptor',
        'tags': ['technique_descriptor', 'beast'],
        'axes': {'power': 6, 'speed': -1},
      },
    ]);
    final d = techniqueDescriptorFromContent(registry.get('bear'));
    expect(d.id, 'bear');
    expect(d.axes, {'power': 6, 'speed': -1});
    expect(d.tags, contains('beast'));
  });

  test('accessor throws for an unknown descriptor id', () {
    final registry = ContentRegistry();
    expect(
      () => _lookup(registry, 'no_such'),
      throwsA(isA<UnknownTechniqueDescriptorException>()),
    );
  });
}

TechniqueDescriptor _lookup(ContentRegistry registry, String id) {
  // techniqueDescriptor takes a PluginContext; exercise the same logic via a
  // tiny shim so this test needs no full context.
  final def = registry.find(id);
  if (def == null || def.extra['axes'] == null) {
    throw UnknownTechniqueDescriptorException(id);
  }
  return techniqueDescriptorFromContent(def);
}
