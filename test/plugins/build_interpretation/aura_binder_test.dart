import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:test/test.dart';

/// Minimal stand-in for a combat turn event; its actor extractor is what
/// the binder must use generically.
class _Turn {
  const _Turn(this.actor);
  final EntityId actor;
}

/// A second, differently shaped synthetic trigger — the opponent
/// actor-guard must work on it with no event-type branching in the
/// binder (spec §9).
class _Action {
  const _Action(this.actor);
  final EntityId actor;
}

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
  c.content.registerTrigger('Turn', _Turn, (e) => (e as _Turn).actor);
  c.content.registerTrigger('Action', _Action, (e) => (e as _Action).actor);
  return c;
}

/// An interpreter that returns a fixed aura list, so the binder is tested
/// in isolation from Item/Technique resolution.
class _FixedInterpreter implements BuildActionInterpreter {
  const _FixedInterpreter(this._auras);
  final List<AuraRule> _auras;
  @override
  List<CombatAction> interpret({required ResolvedBuild build, required EntityId actor, required List<EntityId> targets, required PluginContext context}) => const [];
  @override
  List<AuraRule> auraRules({required ResolvedBuild build, required PluginContext context}) => _auras;
}

AuraRule _selfHeal() => AuraRule(
      rule: Rule(
        trigger: _Turn,
        subjectOf: (e) => (e as _Turn).actor,
        effects: const [Heal(5)],
      ),
      scope: AuraScope.self,
      sourceRuleId: 'aura.self_heal',
    );

AuraRule _opponentBleed() => AuraRule(
      rule: Rule(
        trigger: _Turn,
        subjectOf: (e) => (e as _Turn).actor,
        effects: const [Damage(5)],
      ),
      scope: AuraScope.opponent,
      sourceRuleId: 'aura.opp_bleed',
    );

/// Same opponent scope, but keyed off `_Action` instead of `_Turn`.
AuraRule _opponentThorns() => AuraRule(
      rule: Rule(
        trigger: _Action,
        subjectOf: (e) => (e as _Action).actor,
        effects: const [Damage(5)],
      ),
      scope: AuraScope.opponent,
      sourceRuleId: 'aura.opp_thorns',
    );

void main() {
  ResolvedBuild build(EntityId owner) =>
      ResolvedBuild(owner: owner, active: const [], owned: const []);

  test('self-scope aura fires on the owner\'s turn only', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_selfHeal()]),
      context: ctx,
      opponents: [enemy],
    );

    ctx.events.publish(_Turn(enemy)); // not the owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);

    ctx.events.publish(_Turn(owner)); // owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 55);
  });

  test('opponent-scope aura hits the opponent, ticking on the owner\'s turn', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(enemy, const HealthComponent(current: 30, max: 30));

    const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_opponentBleed()]),
      context: ctx,
      opponents: [enemy],
    );

    ctx.events.publish(_Turn(enemy)); // enemy's turn -> no tick
    expect(ctx.components.get<HealthComponent>(enemy)!.current, 30);

    ctx.events.publish(_Turn(owner)); // owner's turn -> opponent takes 5
    expect(ctx.components.get<HealthComponent>(enemy)!.current, 25);
  });

  test('opponent-scope aura with no opponent is simply not registered', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final binding = const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_opponentBleed()]),
      context: ctx,
      opponents: const [],
    );
    // No throw; publishing does nothing.
    ctx.events.publish(_Turn(owner));
    binding.dispose(); // also must not throw
  });

  test('opponent-scope aura with >1 opponent throws ArgumentError', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    expect(
      () => const AuraBinder().bind(
        build: build(owner),
        interpreter: _FixedInterpreter([_opponentBleed()]),
        context: ctx,
        opponents: [ctx.entities.create(), ctx.entities.create()],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a throw mid-bind cancels the auras already registered', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    // Self aura FIRST: it is registered (live) before the opponent aura's
    // _wire throws. `bind` returns nothing, so nobody can dispose it —
    // `bind` itself must unwind.
    expect(
      () => const AuraBinder().bind(
        build: build(owner),
        interpreter: _FixedInterpreter([_selfHeal(), _opponentBleed()]),
        context: ctx,
        opponents: [ctx.entities.create(), ctx.entities.create()],
      ),
      throwsA(isA<ArgumentError>()),
    );

    ctx.events.publish(_Turn(owner));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50,
        reason: 'the self aura registered before the throw must be cancelled');
  });

  test('the opponent actor-guard is trigger-type agnostic (_Action, not _Turn)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(enemy, const HealthComponent(current: 30, max: 30));

    const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_opponentThorns()]),
      context: ctx,
      opponents: [enemy],
    );

    ctx.events.publish(_Action(enemy)); // enemy acted -> guard blocks
    expect(ctx.components.get<HealthComponent>(enemy)!.current, 30);

    ctx.events.publish(_Action(owner)); // owner acted -> opponent takes 5
    expect(ctx.components.get<HealthComponent>(enemy)!.current, 25);
  });

  test('dispose() detaches every subscription and is idempotent', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    final binding = const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([_selfHeal()]),
      context: ctx,
      opponents: [ctx.entities.create()],
    );

    binding.dispose();
    binding.dispose(); // idempotent

    ctx.events.publish(_Turn(owner));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50); // no heal after dispose
  });

  test('firing order follows the auraRules list, not sourceRuleId', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 0, max: 100));
    final order = <String>[];
    AuraRule recorder(String id) => AuraRule(
          rule: Rule(
            trigger: _Turn,
            subjectOf: (e) => (e as _Turn).actor,
            conditions: [SubjectIs(owner)],
            effects: [_Record(() => order.add(id))],
          ),
          scope: AuraScope.self,
          sourceRuleId: id,
        );
    const AuraBinder().bind(
      build: build(owner),
      interpreter: _FixedInterpreter([recorder('z'), recorder('a'), recorder('m')]),
      context: ctx,
      opponents: [ctx.entities.create()],
    );
    ctx.events.publish(_Turn(owner));
    expect(order, ['z', 'a', 'm']); // list order, NOT sorted
  });
}

class _Record implements Effect {
  const _Record(this.onApply);
  final void Function() onApply;
  @override
  void apply(RuleContext context) => onApply();
}
