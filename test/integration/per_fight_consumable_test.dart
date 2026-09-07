/// SP3 §12 — the acceptance-invariant table. "Per-fight limited-use
/// consumable" means exactly the rows below, each proved through
/// observable state (charge-pool values, `HealthComponent`,
/// `StatusComponent`, live `Modifier`s) — never `ConsumableCharges`
/// internals.
///
/// One `test(...)` per §12 row. The context mirrors the other
/// `test/integration/` files: Combat is initialized first (its triggers
/// must exist before Item/Technique register their aura rules), then the
/// content plugins, then the 3-interpreter composite.
library;

import 'package:build_engine/auto_combat_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/build_interpretation.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/consumable_plugin.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1); // fixed seed — no wall-clock, no global RNG
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(
      entities: entities,
      components: components,
      events: events,
      rng: rng,
      shared: shared,
    ),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  CombatPlugin().initialize(c); // FIRST — triggers exist before aura rules load
  ItemPlugin().initialize(c);
  TechniquePlugin().initialize(c);
  ConsumablePlugin().initialize(c);
  return c;
}

const _interpreter = CompositeBuildActionInterpreter([
  TechniqueActionInterpreter(),
  ItemActionInterpreter(),
  ConsumableActionInterpreter(),
]);

BuildComponentRef _ref(String id) =>
    BuildComponentRef(referenceType: consumableReferenceType, contentId: id);

ResolvedBuild _hung(EntityId owner, List<BuildComponentRef> refs) =>
    ResolvedBuild(owner: owner, active: refs, owned: refs);

String _pool(String id) => consumableChargeResource(id);

/// A combat-ready entity: [CombatantComponent] (initiative ordering /
/// team) + [HealthComponent].
EntityId _combatant(PluginContext ctx, String team, int initiative, int hp,
    {int? max}) {
  final e = ctx.entities.create();
  ctx.components.add(e, CombatantComponent(team: team, initiative: initiative));
  ctx.components.add(e, HealthComponent(current: hp, max: max ?? hp));
  return e;
}

void main() {
  // ── Row 1 ──────────────────────────────────────────────────────────
  test('owned but not hung: no consumable action, no charge granted', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    final ref = _ref(ConsumableIds.healPotion);

    // In `owned`, NOT in `active`.
    final build = ResolvedBuild(owner: owner, active: const [], owned: [ref]);

    final actions = _interpreter.interpret(
      build: build,
      actor: owner,
      targets: [enemy],
      context: ctx,
    );
    expect(actions, isEmpty,
        reason: 'an owned-but-loose consumable contributes no action');

    const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0,
        reason: 'grant only charges refs in build.active');
  });

  // ── Row 2 ──────────────────────────────────────────────────────────
  test('hung, fight starts: pool == 1 and the action carries the '
      'ConsumeResource cost', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final enemy = ctx.entities.create();
    final build = _hung(owner, [_ref(ConsumableIds.healPotion)]);

    const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 1);

    final action = _interpreter.interpret(
      build: build,
      actor: owner,
      targets: [enemy],
      context: ctx,
    ).single;
    expect(action, isA<SelfEffectAction>());
    expect(action.costEffects, hasLength(1));
    final cost = action.costEffects.single as ConsumeResource;
    expect(cost.resource, 'consumable:${ConsumableIds.healPotion}');
    expect(cost.amount, 1);
    // heal_potion ships Heal(20).
    expect((action as SelfEffectAction).selfEffects.single,
        isA<Heal>().having((h) => h.amount, 'amount', 20));
  });

  // ── Row 3 ──────────────────────────────────────────────────────────
  test('2 identical hung consumables: aggregate pool == 2', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final r = _ref(ConsumableIds.healPotion);
    final build = _hung(owner, [r, r]); // two Tome cells, same id

    const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 2,
        reason: '2 copies x per-copy charges(1) = 2');
  });

  // ── Row 4 ──────────────────────────────────────────────────────────
  test('resource cap: pool of 3 stays 3 (max is double.infinity)', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final r = _ref(ConsumableIds.healPotion);
    final build = _hung(owner, [r, r, r]);

    const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 3,
        reason: 'the aggregate set is never clamped to one copy\'s charges');
    expect(
      ctx.resources.definitionOf(_pool(ConsumableIds.healPotion))!.max,
      double.infinity,
    );
  });

  // ── Row 5 ──────────────────────────────────────────────────────────
  test('used N times then filtered: _isAvailable false at pool 0, and a forced '
      'CombatSystem execute no-ops both cost and effect (pool never negative, '
      'health unchanged)', () {
    final ctx = _ctx();
    final owner = _combatant(ctx, 'player', 10, 10, max: 100); // hurt: 10/100
    final enemy = _combatant(ctx, 'enemy', 1, 50);
    final build = _hung(owner, [_ref(ConsumableIds.healPotion)]);

    const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 1);

    final healAction = _interpreter.interpret(
      build: build,
      actor: owner,
      targets: [enemy],
      context: ctx,
    ).single;
    final fallbackAttack = AttackAction(
      actor: owner,
      targets: [enemy],
      baseDamage: 5,
      damageStat: 'fist',
    );

    const selector =
        ScoredActionSelector(scorer: ConsumableAwareActionScorer());

    // pool 1: the heal is available and, hurt to 10/100, out-scores the
    // attack — the selector returns it.
    expect(
      selector.selectAction(owner, [healAction, fallbackAttack], null, ctx),
      same(healAction),
    );

    // Spend the only charge (the brief's allowed `resources.consume` form).
    ctx.resources.consume(owner, _pool(ConsumableIds.healPotion), 1);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);

    // pool 0: `_isAvailable` filters the heal even though it still scores
    // highest — the selector falls back to the attack.
    expect(
      selector.selectAction(owner, [healAction, fallbackAttack], null, ctx),
      same(fallbackAttack),
    );

    // Force the heal through CombatSystem at pool 0. The consumable action
    // carries `conditions: [ResourceAbove('consumable:heal_potion', 0)]`
    // (SP3 C1), so `executeAction`'s condition check fails and it applies
    // NEITHER the ConsumeResource cost NOR the Heal effect: the pool stays
    // 0 (never negative), the owner's health is unchanged, and nothing
    // throws.
    final system = CombatSystem(ctx);
    final battle = system.startBattle([owner, enemy]); // owner's turn first
    final hpBefore = ctx.components.get<HealthComponent>(owner)!.current;
    expect(() => system.executeAction(battle, healAction), returnsNormally);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);
    expect(ctx.components.get<HealthComponent>(owner)!.current, hpBefore);
    system.dispose();
  });

  // ── Row 6 ──────────────────────────────────────────────────────────
  test('fight ends (incl. a throw): dispose() zeroes every pool and removes '
      'every consumable modifier; idempotent', () {
    final ctx = _ctx();
    final owner = _combatant(ctx, 'player', 10, 100);
    final enemy = _combatant(ctx, 'enemy', 1, 50);
    final build = _hung(owner, [
      _ref(ConsumableIds.powerTonic),
      _ref(ConsumableIds.healPotion),
    ]);

    final charges = const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.powerTonic)), 1);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 1);

    // Execute power_tonic so a GrantModifier lands a live 'thrown' modifier
    // (this is also the "incl. a throw" path — power_tonic buffs the
    // firebomb's damage stat).
    final tonicAction = _interpreter
        .interpret(build: build, actor: owner, targets: [enemy], context: ctx)
        .firstWhere((a) =>
            a.sourceRef?.contentId == ConsumableIds.powerTonic);
    final system = CombatSystem(ctx);
    final battle = system.startBattle([owner, enemy]); // owner first
    system.executeAction(battle, tonicAction);

    final live =
        ctx.modifiers.activeModifiersFor(owner, 'thrown', ctx.components).toList();
    expect(live, hasLength(1));
    expect(live.single.value, 6); // power_tonic ships +6 on 'thrown'
    expect(live.single.source,
        ModifierSource('consumable:${ConsumableIds.powerTonic}:${owner.value}'));

    // Fight ends.
    charges.dispose();
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.powerTonic)), 0);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0,
        reason: 'dispose zeroes a still-full pool too');
    expect(
      ctx.modifiers.activeModifiersFor(owner, 'thrown', ctx.components),
      isEmpty,
      reason: 'the consumable-sourced modifier is removed at fight end',
    );

    // Idempotent: a second dispose neither throws nor changes anything.
    charges.dispose();
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.powerTonic)), 0);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);
    expect(
      ctx.modifiers.activeModifiersFor(owner, 'thrown', ctx.components),
      isEmpty,
    );
    system.dispose();
  });

  // ── Row 7 ──────────────────────────────────────────────────────────
  test('partial fight setup: AuraBinder.bind OK then ConsumableBinder.grant '
      'throws — the aura binding is disposed, no consumable pool survives', () {
    final ctx = _ctx();
    final owner = _combatant(ctx, 'player', 10, 50, max: 100); // hurt 50/100
    final enemy = _combatant(ctx, 'enemy', 1, 50);
    final battle = ctx.entities.create();

    // A hung item with a real self-heal aura (`cloth_armor` /
    // `aura.regen_weave`, heal 1 on the owner's TurnStarted).
    final auraBuild = ResolvedBuild(
      owner: owner,
      active: const [
        BuildComponentRef(referenceType: itemReferenceType, contentId: 'cloth_armor'),
      ],
      owned: const [
        BuildComponentRef(referenceType: itemReferenceType, contentId: 'cloth_armor'),
      ],
    );

    // A deliberately malformed consumable: the content id registers fine
    // (the registry never interprets `effect`), but
    // `consumableDefinitionFromContent` rejects an empty `effect` object —
    // so `ConsumableBinder.grant` throws while resolving it.
    ctx.content.load(<String, dynamic>{
      'id': 'malformed_consumable',
      'type': consumableReferenceType,
      'tags': <String>['consumable'],
      'effect': <String, dynamic>{},
    });
    final badBuild = _hung(owner, [_ref('malformed_consumable')]);

    // Mirror `CombatStage.runFight`'s exception-safe shape:
    // `try { grant(bad) } finally { auraBinding.dispose(); }`.
    final auraBinding = const AuraBinder().bind(
      build: auraBuild,
      interpreter: _interpreter,
      context: ctx,
      opponents: [enemy],
    );

    // Positive control: while the binding is live its TurnStarted trigger
    // heals the owner 1 (regen_weave). Without this leg the negative
    // assertion below could pass simply because the aura never fires for
    // this event at all.
    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51,
        reason: 'the aura binding is live before the partial setup fails');

    Object? caught;
    try {
      const ConsumableBinder().grant(build: badBuild, context: ctx);
    } catch (e) {
      caught = e;
    } finally {
      auraBinding.dispose();
    }

    expect(caught, isA<ContentFieldException>(),
        reason: 'grant propagates the malformed-content failure');

    // The aura binding was disposed by the finally: the same trigger now
    // does nothing (health holds at 51, not 52).
    ctx.events.publish(TurnStarted(battle, owner, 1));
    expect(ctx.components.get<HealthComponent>(owner)!.current, 51,
        reason: 'no live aura subscription survived the partial setup');

    // No consumable charge pool left non-zero.
    expect(ctx.resources.currentOf(owner, _pool('malformed_consumable')), 0);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.powerTonic)), 0);
  });

  // ── Row 8 ──────────────────────────────────────────────────────────
  test('next fight refreshed: dispose then grant the same build restores the '
      'full aggregate', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final r = _ref(ConsumableIds.healPotion);
    final build = _hung(owner, [r, r]); // aggregate 2

    // Fight 1.
    final fight1 = const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 2);
    // ... spend one ...
    ctx.resources.consume(owner, _pool(ConsumableIds.healPotion), 1);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 1);
    // ... fight ends.
    fight1.dispose();
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);

    // Fight 2: a fresh grant from the same build — refreshed, not depleted.
    const ConsumableBinder().grant(build: build, context: ctx);
    expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 2,
        reason: 'charges refresh to the full aggregate each fight');
  });

  // ── Row 9 ──────────────────────────────────────────────────────────
  test('determinism: the row-2/5 sequence and a cleanse are byte-identical '
      'across two fresh runs', () {
    ({num pool, num hp, int thrownMods}) healSequence() {
      final ctx = _ctx();
      final owner = _combatant(ctx, 'player', 10, 10, max: 100);
      final enemy = _combatant(ctx, 'enemy', 1, 50);
      final build = _hung(owner, [_ref(ConsumableIds.healPotion)]);

      const ConsumableBinder().grant(build: build, context: ctx);
      final heal = _interpreter.interpret(
        build: build,
        actor: owner,
        targets: [enemy],
        context: ctx,
      ).single;
      final attack = AttackAction(
        actor: owner,
        targets: [enemy],
        baseDamage: 5,
        damageStat: 'fist',
      );
      const selector =
          ScoredActionSelector(scorer: ConsumableAwareActionScorer());

      // pool 1 -> heal selected; consume; pool 0 -> attack selected.
      expect(selector.selectAction(owner, [heal, attack], null, ctx),
          same(heal));
      ctx.resources.consume(owner, _pool(ConsumableIds.healPotion), 1);
      expect(selector.selectAction(owner, [heal, attack], null, ctx),
          same(attack));

      return (
        pool: ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)),
        hp: ctx.components.get<HealthComponent>(owner)!.current,
        thrownMods: ctx.modifiers
            .activeModifiersFor(owner, 'thrown', ctx.components)
            .length,
      );
    }

    final a = healSequence();
    final b = healSequence();
    expect(a, b);
    expect(a.pool, 0);

    // cleanse_tonic: a synthetic status is gone after the action fires —
    // twice, identically.
    bool? cleanse() {
      final ctx = _ctx();
      final owner = _combatant(ctx, 'player', 10, 100);
      final enemy = _combatant(ctx, 'enemy', 1, 50);
      ctx.components.add(owner, StatusComponent({'status:poison'}));
      final build = _hung(owner, [_ref(ConsumableIds.cleanseTonic)]);

      const ConsumableBinder().grant(build: build, context: ctx);
      final action = _interpreter.interpret(
        build: build,
        actor: owner,
        targets: [enemy],
        context: ctx,
      ).single;
      final system = CombatSystem(ctx);
      final battle = system.startBattle([owner, enemy]);
      system.executeAction(battle, action);
      system.dispose();
      return ctx.components.get<StatusComponent>(owner) == null;
    }

    // Two independent fresh-context runs both fully clear the status.
    // (Cross-run RunResult determinism — including consumable refs in
    // `finalBuild` / `rewardsGranted` — is covered by
    // `consumable_combat_stage_test.dart`; this row only needs the
    // consumable's own effect to be reproducible.)
    final c1 = cleanse();
    final c2 = cleanse();
    expect(c1, isTrue);
    expect(c2, isTrue);
  });

  // ── Supplementary coverage (SP3 §9 / §11) ─────────────────────────────
  group('firebomb end-to-end and multi-charge spend', () {
    test('firebomb: executing the consumable action deals 15 to the enemy from '
        'a consumable-sourced AttackAction (targets = enemy, not self)', () {
      final ctx = _ctx();
      final owner = _combatant(ctx, 'player', 10, 100);
      final enemy = _combatant(ctx, 'enemy', 1, 60);
      final build = _hung(owner, [_ref(ConsumableIds.firebomb)]);

      const ConsumableBinder().grant(build: build, context: ctx);
      final action = _interpreter
          .interpret(build: build, actor: owner, targets: [enemy], context: ctx)
          .single;

      expect(action, isA<AttackAction>());
      expect(action.sourceRef?.referenceType, consumableReferenceType);
      expect(action.sourceRef?.contentId, ConsumableIds.firebomb);
      expect(action.targets, [enemy],
          reason: 'firebomb is enemy-targeted, never self');

      final damaged = <EntityDamaged>[];
      ctx.events.subscribe<EntityDamaged>(damaged.add);

      final system = CombatSystem(ctx);
      final battle = system.startBattle([owner, enemy]); // owner first
      system.executeAction(battle, action);
      system.dispose();

      expect(damaged.map((d) => (d.id, d.amount)), contains((enemy, 15)));
      expect(ctx.components.get<HealthComponent>(enemy)!.current, 60 - 15);
      expect(ctx.components.get<HealthComponent>(owner)!.current, 100,
          reason: 'the thrower is untouched');
    });

    test('attack consumable with no targets yields no action', () {
      final ctx = _ctx();
      final owner = _combatant(ctx, 'player', 10, 100);
      final build = _hung(owner, [_ref(ConsumableIds.firebomb)]);

      final actions = _interpreter.interpret(
          build: build, actor: owner, targets: const [], context: ctx);
      expect(actions, isEmpty);
    });

    test('two hung heal_potion copies: the aggregate pool covers N spends and '
        'the (N+1)th selection is gated; a forced (N+1)th execute no-ops', () {
      final ctx = _ctx();
      final owner = _combatant(ctx, 'player', 40, 40, max: 100); // hurt 40/100
      final enemy = _combatant(ctx, 'enemy', 1, 50);
      final r = _ref(ConsumableIds.healPotion);
      final build = _hung(owner, [r, r]); // aggregate 2

      const ConsumableBinder().grant(build: build, context: ctx);
      expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 2);

      final heal = _interpreter
          .interpret(build: build, actor: owner, targets: [enemy], context: ctx)
          .first;
      final fallback = AttackAction(
          actor: owner, targets: [enemy], baseDamage: 5, damageStat: 'fist');
      const selector =
          ScoredActionSelector(scorer: ConsumableAwareActionScorer());

      // pool 2 → heal offered; spend a charge; pool 1 → still offered;
      // spend the last; pool 0 → the gate fails, selector drops to attack.
      expect(selector.selectAction(owner, [heal, fallback], null, ctx),
          same(heal));
      ctx.resources.consume(owner, _pool(ConsumableIds.healPotion), 1);
      expect(selector.selectAction(owner, [heal, fallback], null, ctx),
          same(heal));
      ctx.resources.consume(owner, _pool(ConsumableIds.healPotion), 1);
      expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);
      expect(selector.selectAction(owner, [heal, fallback], null, ctx),
          same(fallback));

      // A forced (N+1)th execute at pool 0: gate fails → no cost, no heal.
      final system = CombatSystem(ctx);
      final battle = system.startBattle([owner, enemy]);
      final hp = ctx.components.get<HealthComponent>(owner)!.current;
      system.executeAction(battle, heal);
      expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);
      expect(ctx.components.get<HealthComponent>(owner)!.current, hp);
      system.dispose();
    });

    test('mutation guard: without ConsumableBinder.grant the pool defaults to 0 '
        'and the action is unavailable from turn 1', () {
      final ctx = _ctx();
      final owner = _combatant(ctx, 'player', 10, 10, max: 100);
      final enemy = _combatant(ctx, 'enemy', 1, 50);
      final build = _hung(owner, [_ref(ConsumableIds.healPotion)]);

      // No grant() call.
      expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);

      final heal = _interpreter
          .interpret(build: build, actor: owner, targets: [enemy], context: ctx)
          .single;
      final fallback = AttackAction(
          actor: owner, targets: [enemy], baseDamage: 5, damageStat: 'fist');
      const selector =
          ScoredActionSelector(scorer: ConsumableAwareActionScorer());

      // Even hurt to 10/100 (heal would out-score), the selector cannot
      // offer the heal — its cost is unaffordable and its ResourceAbove
      // gate fails.
      expect(selector.selectAction(owner, [heal, fallback], null, ctx),
          same(fallback));

      final system = CombatSystem(ctx);
      final battle = system.startBattle([owner, enemy]);
      final hpBefore = ctx.components.get<HealthComponent>(owner)!.current;
      system.executeAction(battle, heal); // forced: no-ops
      expect(ctx.components.get<HealthComponent>(owner)!.current, hpBefore);
      expect(ctx.resources.currentOf(owner, _pool(ConsumableIds.healPotion)), 0);
      system.dispose();
    });
  });
}
