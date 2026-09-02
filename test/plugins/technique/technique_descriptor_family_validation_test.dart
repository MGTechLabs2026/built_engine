import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:build_engine/src/plugins/technique/technique_descriptor_content.dart';
import 'package:build_engine/src/plugins/technique/technique_vocabulary.dart';
import 'package:test/test.dart';

/// Every `family:<id>` tag a descriptor carries must name a real technique
/// base family. An invalid reference is a CONTENT ERROR, caught here — the
/// inspiration resolver assumes this has passed and never re-checks.
Iterable<String> _familyRefs(Iterable<String> tags) => tags
    .where((t) => t.startsWith(techniqueFamilyTagPrefix))
    .map((t) => t.substring(techniqueFamilyTagPrefix.length));

void main() {
  test('shipped technique_descriptor content has only valid family: refs', () {
    for (final def in techniqueDescriptorContentDefinitions) {
      final tags = (def['tags'] as List).cast<String>();
      for (final id in _familyRefs(tags)) {
        expect(TechniqueIds.bases, contains(id),
            reason: 'descriptor ${def['id']} references unknown family "$id"');
      }
    }
  });

  test('a fixture descriptor with an invalid family ref is rejected', () {
    const bad = TechniqueDescriptor(
      id: 'x', axes: {'power': 1}, tags: {'family:not_a_family'});
    expect(_familyRefs(bad.tags).every(TechniqueIds.bases.contains), isFalse);
  });

  test('a fixture descriptor with a valid family ref passes', () {
    const good = TechniqueDescriptor(
      id: 'x', axes: {'power': 1}, tags: {'family:basic_kick'});
    expect(_familyRefs(good.tags).every(TechniqueIds.bases.contains), isTrue);
  });
}
