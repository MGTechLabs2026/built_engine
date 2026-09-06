import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

class _Dummy implements AuraContributor {
  @override
  List<AuraRule> auraRules() => const [];
}

void main() {
  test('AuraScope is exactly {self, opponent}', () {
    expect(AuraScope.values, [AuraScope.self, AuraScope.opponent]);
  });

  test('AuraRule carries rule, scope, and source id unchanged', () {
    final rule = Rule(trigger: Object, effects: const []);
    final aura = AuraRule(
      rule: rule,
      scope: AuraScope.opponent,
      sourceRuleId: 'aura.x',
    );
    expect(aura.rule, same(rule));
    expect(aura.scope, AuraScope.opponent);
    expect(aura.sourceRuleId, 'aura.x');
  });

  test('AuraContributor is exported and implementable', () {
    expect(_Dummy(), isA<AuraContributor>());
    expect(_Dummy().auraRules(), isEmpty);
  });
}
