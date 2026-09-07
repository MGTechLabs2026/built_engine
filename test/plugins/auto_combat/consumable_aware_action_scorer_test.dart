import 'package:build_engine/auto_combat_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  const scorer = ConsumableAwareActionScorer();
  const base = DefaultActionScorer();

  test('a Heal action scores base + missingHealthWeight * missingFraction', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 25, max: 100)); // missing 0.75
    final heal = SelfEffectAction(actor: actor, selfEffects: const [Heal(20)], priority: 8);

    expect(scorer.score(heal, actor, null, ctx), base.score(heal, actor, null, ctx) + 40 * 0.75);
  });

  test('at full HP the Heal bonus is 0', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 100, max: 100));
    final heal = SelfEffectAction(actor: actor, selfEffects: const [Heal(20)], priority: 8);
    expect(scorer.score(heal, actor, null, ctx), base.score(heal, actor, null, ctx));
  });

  test('an ApplyStatus action scores base + buffBonus', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 50, max: 100));
    final buff = SelfEffectAction(actor: actor, selfEffects: [ApplyStatus('status:x')], priority: 3);
    expect(scorer.score(buff, actor, null, ctx), base.score(buff, actor, null, ctx) + 6);
  });

  test('a plain AttackAction is scored identically to DefaultActionScorer (regression)', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final target = ctx.entities.create();
    final atk = AttackAction(actor: actor, targets: [target], baseDamage: 12, damageStat: 'fist');
    expect(scorer.score(atk, actor, target, ctx), base.score(atk, actor, target, ctx));
  });

  test('a GrantModifier-carrying SelfEffectAction gets no bonus and applies no modifier', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    ctx.components.add(actor, const HealthComponent(current: 50, max: 100));
    final buff = SelfEffectAction(
      actor: actor,
      selfEffects: const [GrantModifier('thrown', ModifierOperation.add, 6, sourceKey: 'consumable:pt')],
      priority: 6,
    );
    expect(scorer.score(buff, actor, null, ctx), base.score(buff, actor, null, ctx));
    expect(ctx.modifiers.activeModifiersFor(actor, 'thrown', ctx.components), isEmpty);
  });

  test('no HealthComponent → Heal bonus is 0 (missing fraction treated as 0)', () {
    final ctx = _ctx();
    final actor = ctx.entities.create();
    final heal = SelfEffectAction(actor: actor, selfEffects: const [Heal(20)]);
    expect(scorer.score(heal, actor, null, ctx), base.score(heal, actor, null, ctx));
  });

  test('the Heal bonus is provenance-blind: a non-consumable healing action '
      '(no sourceRef) is untouched at full HP and lifted when hurt', () {
    // §5.6: the bonus keys on the effect shape, not on the action being
    // consumable-sourced — a healing guard technique benefits identically.
    final full = _ctx();
    final fullActor = full.entities.create();
    full.components.add(fullActor, const HealthComponent(current: 100, max: 100));
    final healFull = SelfEffectAction(
        actor: fullActor, selfEffects: const [Heal(15)], priority: 4);
    expect(healFull.sourceRef, isNull);
    expect(
      scorer.score(healFull, fullActor, null, full),
      base.score(healFull, fullActor, null, full),
    );

    final hurt = _ctx();
    final hurtActor = hurt.entities.create();
    hurt.components.add(hurtActor, const HealthComponent(current: 20, max: 100));
    final healHurt = SelfEffectAction(
        actor: hurtActor, selfEffects: const [Heal(15)], priority: 4);
    expect(
      scorer.score(healHurt, hurtActor, null, hurt),
      greaterThan(base.score(healHurt, hurtActor, null, hurt)),
    );
  });
}
