// Every public symbol the spec §10 promises must resolve through the
// single barrel import — nothing else.
import 'package:build_engine/affix_plugin.dart';
import 'package:test/test.dart';

void main() {
  test('the barrel exposes the full §10 surface', () {
    // types
    AffixLean.neutral;
    AffixDomain.item;
    AffixCategories.itemPrefix;
    AffixPoolTags.forSlot(AffixDomain.item, 'prefix');
    // mechanic
    const AffixMechanic m = WeaponStatBonus(1);
    expect(m.amount, 1);
    expect(AffixMechanic.fromJson({'kind': 'heal', 'amount': 2}), isA<ImmediateHeal>());
    // definition + content
    expect(affixContentDefinitions, hasLength(33));
    expect(affixDefinitionFromContent, isNotNull);
    // resolver
    expect(kNoAffixChance, 0.34);
    const AffixRewardContext(domain: AffixDomain.item, physiqueTradition: null);
    // application target types
    expect(CharacterTarget, isNotNull);
    expect(ItemInstanceTarget, isNotNull);
    expect(applyAffixMechanic, isNotNull);
    // acquisition
    const RunRef(runId: 'r', runNumber: 1);
    AffixAcquisitionIdSource();
    const AffixAcquisition(
      affixId: 'a', affixEventId: 'e', runId: 'r', runNumber: 1,
      stat: 's', value: 1, category: 'item_prefix');
    expect(acquireAffixes, isNotNull);
    expect(AffixPlugin().id, 'affix');
  });
}
