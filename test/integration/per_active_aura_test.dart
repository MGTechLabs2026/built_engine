/// SP2 §12 acceptance invariant — "per-active" means exactly this.
library;

import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
        entities: entities, components: components, events: events, rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  CombatPlugin().initialize(c); // triggers must exist before Item/Technique load their aura rules
  ItemPlugin().initialize(c);
  TechniquePlugin().initialize(c);
  return c;
}

const _interpreter = CompositeBuildActionInterpreter([
  TechniqueActionInterpreter(),
  ItemActionInterpreter(),
]);

/// A ref for a hung `cloth_armor` (self-heal aura `aura.regen_weave`).
const _clothArmorRef =
    BuildComponentRef(referenceType: itemReferenceType, contentId: 'cloth_armor');

ResolvedBuild _build(EntityId owner, {required bool hung}) => ResolvedBuild(
      owner: owner,
      active: hung ? const [_clothArmorRef] : const [],
      owned: const [_clothArmorRef],
    );

void main() {
  test('owned + loose: aura does NOT fire', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    const AuraBinder().bind(
      build: _build(owner, hung: false),
      interpreter: _interpreter,
      context: ctx,
      opponents: [ctx.entities.create()],
    );

    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);
  });

  test('owned + hung: aura fires on the owner\'s turn', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );

    ctx.events.publish(TurnStarted(battle, enemy, 1)); // not owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);

    ctx.events.publish(TurnStarted(battle, owner, 1)); // owner's turn
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51); // aura.regen_weave heals 1
  });

  test('unhung mid-run: aura stops on the next event after re-bind', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    final first = const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );
    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51);

    // Player unhangs the armour: dispose old, resolve new (loose), bind new.
    first.dispose();
    const AuraBinder().bind(
      build: _build(owner, hung: false),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );
    ctx.events.publish(TurnStarted(battle, owner, 2));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51); // no further heal
  });

  test('fight ends: dispose() detaches every aura subscription', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    final enemy = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    final binding = const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );
    binding.dispose();
    binding.dispose(); // idempotent

    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 50);
  });

  test('next fight: only fresh bindings exist (no leakage)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final battle = ctx.entities.create();
    ctx.components.add(owner, const HealthComponent(current: 50, max: 100));

    // Fight 1
    const AuraBinder()
        .bind(build: _build(owner, hung: true), interpreter: _interpreter, context: ctx, opponents: [ctx.entities.create()])
        .dispose();
    // Fight 2 — a fresh binding; one owner-turn heals exactly once (1), not twice.
    const AuraBinder().bind(
      build: _build(owner, hung: true),
      interpreter: _interpreter,
      context: ctx,
      opponents: [ctx.entities.create()],
    );
    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51);
  });

  test('same seed + same events -> identical aura effect sequence', () {
    num runHealTotal() {
      final ctx = _ctx();
      final owner = ctx.entities.create();
      final battle = ctx.entities.create();
      final enemy = ctx.entities.create();
      ctx.components.add(owner, const HealthComponent(current: 1, max: 100));
      const AuraBinder().bind(
        build: _build(owner, hung: true),
        interpreter: _interpreter,
        context: ctx,
        opponents: [enemy],
      );
      for (var round = 1; round <= 5; round++) {
        ctx.events.publish(TurnStarted(battle, owner, round));
        ctx.events.publish(TurnStarted(battle, enemy, round));
      }
      return ctx.components.get<HealthComponent>(owner)!.current;
    }

    expect(runHealTotal(), runHealTotal()); // deterministic: 1 + 5 owner-turn heals = 6
    expect(runHealTotal(), 6);
  });
}
