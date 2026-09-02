// The harness ActionCompleted subscription attributes a performed action
// to its technique-variant instance. These tests replicate — inline — the
// guard `CombatStage.runFight` adds to its existing
// `events.subscribe<ActionCompleted>` handler; they do not spin up a real
// `CombatStage` (the battle-scope check and `turnsUsed++` are orthogonal
// to attribution and covered by the combat-stage suite).
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/combat_plugin.dart';
import 'package:build_engine/item_plugin.dart';
// `TechniqueUsageComponent` / `recordTechniqueVariantUsage` /
// `techniqueVariantUsage` all come through this barrel (it re-exports
// `technique_usage.dart`) — a direct src import would be `unnecessary_import`.
import 'package:build_engine/technique_plugin.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  final shared = CoreServices(components: components, events: events);
  final c = PluginContext(
    entities: entities, components: components, events: events, rng: rng,
    rules: RuleEngine(
      entities: entities, components: components, events: events,
      rng: rng, shared: shared),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
    shared: shared,
  );
  c.content.loadAll(techniqueContentDefinitions);
  return c;
}

/// The exact three lines `CombatStage.runFight` runs inside its
/// `events.subscribe<ActionCompleted>` handler for events in the battle.
void _recordFromEvent(ActionCompleted e, PluginContext context) {
  final ref = e.action.sourceRef;
  if (ref != null &&
      ref.referenceType == techniqueReferenceType &&
      ref.instanceEntityId != null) {
    recordTechniqueVariantUsage(ref.instanceEntityId!, context);
  }
}

AttackAction _attack(EntityId owner, BuildComponentRef? ref) => AttackAction(
      actor: owner,
      targets: [const EntityId(999)],
      baseDamage: 1,
      damageStat: 'fist',
      sourceRef: ref,
    );

ActionCompleted _completed(EntityId owner, AttackAction action) =>
    ActionCompleted(const EntityId(1), owner, const [EntityId(999)], action);

void main() {
  test('an ActionCompleted for a technique-instance action bumps its usage', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    final instance = mintTechniqueVariant(owner, 'basic_punch', const {}, ctx);

    final sub = ctx.events
        .subscribe<ActionCompleted>((e) => _recordFromEvent(e, ctx));
    final action = _attack(
      owner,
      BuildComponentRef(
        referenceType: techniqueReferenceType,
        contentId: 'basic_punch',
        instanceEntityId: instance,
      ),
    );
    ctx.events.publish(_completed(owner, action));
    ctx.events.publish(_completed(owner, action));
    sub.cancel();

    expect(techniqueVariantUsage(instance, ctx), 2);
  });

  test('a null / non-technique / instance-less sourceRef records nothing', () {
    final ctx = _ctx();
    final owner = ctx.entities.create();
    // A real instance to dangle off the item-typed ref below — proves the
    // guard rejects on `referenceType`, not on a missing entity.
    final instance = mintTechniqueVariant(owner, 'basic_punch', const {}, ctx);

    final sub = ctx.events
        .subscribe<ActionCompleted>((e) => _recordFromEvent(e, ctx));

    // 1. no sourceRef at all.
    ctx.events.publish(_completed(owner, _attack(owner, null)));
    // 2. a non-technique (item) ref, even carrying a valid instance id.
    ctx.events.publish(_completed(
      owner,
      _attack(
        owner,
        BuildComponentRef(
          referenceType: itemReferenceType,
          contentId: 'some_item',
          instanceEntityId: instance,
        ),
      ),
    ));
    // 3. a technique ref with no instance id.
    ctx.events.publish(_completed(
      owner,
      _attack(
        owner,
        const BuildComponentRef(
          referenceType: techniqueReferenceType,
          contentId: 'basic_punch',
        ),
      ),
    ));
    sub.cancel();

    // Reached here without a throw, and nothing was recorded.
    expect(ctx.components.get<TechniqueUsageComponent>(owner), isNull);
    expect(techniqueVariantUsage(instance, ctx), 0);
  });
}
