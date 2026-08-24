import 'package:build_engine/build_engine.dart';
import 'package:build_engine/src/plugins/item/item_instance.dart';
import 'package:test/test.dart';

void main() {
  test('ItemInstance references its definition and owner', () {
    const owner = EntityId(1);
    const instance = ItemInstance(definitionId: 'iron_sword', owner: owner);

    expect(instance.definitionId, equals('iron_sword'));
    expect(instance.owner, equals(owner));
  });

  test('ItemInstance can be stored and retrieved as an ordinary component', () {
    final events = EventBus();
    final entities = EntityRegistry(events);
    final components = ComponentStore();
    const owner = EntityId(1);

    final itemEntity = entities.create();
    components.add(itemEntity, ItemInstance(definitionId: 'gloves', owner: owner));

    expect(components.get<ItemInstance>(itemEntity)!.definitionId, equals('gloves'));
  });
}
