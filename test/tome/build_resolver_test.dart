import 'package:build_engine/src/entity/entity_id.dart';
import 'package:build_engine/src/spatial/position.dart';
import 'package:build_engine/src/spatial/slot.dart';
import 'package:build_engine/src/tome/active_build.dart';
import 'package:build_engine/src/tome/build_component_ref.dart';
import 'package:build_engine/src/tome/build_resolver.dart';
import 'package:build_engine/src/tome/tome_placement.dart';
import 'package:test/test.dart';

void main() {
  const resolver = BuildResolver();
  const owner = EntityId(1);
  const slotA = SlotId('a');
  const itemRef = BuildComponentRef(referenceType: 'item', contentId: 'knife');
  const looseRef = BuildComponentRef(referenceType: 'item', contentId: 'shield');

  TomePlacement placement(SlotId slot, BuildComponentRef ref) => TomePlacement(
        slot: slot,
        buildComponentRef: ref,
        size: const ItemSize(1, 1),
        rotation: Rotation.deg0,
      );

  BuildComponentRef ref(String type, String id) =>
      BuildComponentRef(referenceType: type, contentId: id); // non-const call — a fresh object each time

  test('active is exactly the hung refs, as ActiveBuild is today', () {
    final resolved = resolver.resolve(owner, [placement(slotA, itemRef)]);
    expect(resolved.active, [itemRef]);
  });

  test('ownedRefs not placed on the Tome appear in owned, absent from active', () {
    final resolved = resolver.resolve(
      owner,
      [placement(slotA, itemRef)],
      ownedRefs: [itemRef, looseRef],
    );
    expect(resolved.owned, containsAll([itemRef, looseRef]));
    expect(resolved.active, isNot(contains(looseRef)));
  });

  test('active is always a subset of owned, even if the caller never '
      'mentions a hung ref in ownedRefs', () {
    final resolved = resolver.resolve(
      owner,
      [placement(slotA, itemRef)],
      ownedRefs: const [], // caller forgot / has nothing else owned
    );
    expect(resolved.active.every(resolved.owned.contains), isTrue);
  });

  test('asActiveBuild compat getter matches the old ActiveBuild shape', () {
    final resolved = resolver.resolve(owner, [placement(slotA, itemRef)]);
    final compat = resolved.asActiveBuild;
    expect(compat.owner, owner);
    expect(compat.components, [itemRef]);
  });

  test('a hung ref that is also separately listed in ownedRefs (same fields, '
      'different object) appears in owned exactly once', () {
    final placedRef = ref('item', 'knife');
    final separatelyConstructedSameRef = ref('item', 'knife');
    expect(identical(placedRef, separatelyConstructedSameRef), isFalse); // genuinely distinct objects
    final resolved = resolver.resolve(
      owner,
      [placement(slotA, placedRef)],
      ownedRefs: [separatelyConstructedSameRef],
    );
    expect(resolved.owned.where((r) => r == placedRef), hasLength(1));
  });

  test('empty placements + empty ownedRefs -> both lists empty', () {
    final resolved = resolver.resolve(owner, const []);
    expect(resolved.active, isEmpty);
    expect(resolved.owned, isEmpty);
  });
}
