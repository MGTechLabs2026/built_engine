import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

class _Evt {
  const _Evt(this.actor);
  final EntityId actor;
}

ContentRegistry _registryWithRule(Map<String, dynamic> ruleJson) {
  final r = ContentRegistry();
  r.registerTrigger('Evt', _Evt, (e) => (e as _Evt).actor);
  r.loadRule(ruleJson);
  return r;
}

ItemDefinition _defWithAuras(List<String> ids) => ItemDefinition(
      id: 'x', category: 'weapon', tags: const {}, properties: const {},
      auraRuleIds: ids,
    );

void main() {
  test('resolves each auraRuleId into an AuraRule with default self scope', () {
    final content = _registryWithRule({
      'id': 'aura.heal',
      'trigger': 'Evt',
      'effects': [{'type': 'heal', 'amount': 2}],
    });
    final auras = ItemAuraContributor(_defWithAuras(['aura.heal']), content).auraRules();
    expect(auras, hasLength(1));
    expect(auras.single.sourceRuleId, 'aura.heal');
    expect(auras.single.scope, AuraScope.self);
    expect(auras.single.rule.effects.single, isA<Heal>());
  });

  test('reads scope: opponent from the rule json', () {
    final content = _registryWithRule({
      'id': 'aura.bleed',
      'trigger': 'Evt',
      'scope': 'opponent',
      'effects': [{'type': 'damage', 'amount': 1}],
    });
    final auras = ItemAuraContributor(_defWithAuras(['aura.bleed']), content).auraRules();
    expect(auras.single.scope, AuraScope.opponent);
  });

  test('empty auraRuleIds yields no auras', () {
    expect(ItemAuraContributor(_defWithAuras(const []), ContentRegistry()).auraRules(), isEmpty);
  });

  test('an unknown auraRuleId throws ContentNotFoundException', () {
    expect(
      () => ItemAuraContributor(_defWithAuras(['aura.missing']), ContentRegistry()).auraRules(),
      throwsA(isA<ContentNotFoundException>()),
    );
  });

  test('an invalid scope value throws ArgumentError', () {
    final content = _registryWithRule({
      'id': 'aura.bad',
      'trigger': 'Evt',
      'scope': 'everyone',
      'effects': [{'type': 'heal', 'amount': 1}],
    });
    expect(
      () => ItemAuraContributor(_defWithAuras(['aura.bad']), content).auraRules(),
      throwsA(isA<ArgumentError>()),
    );
  });
}
