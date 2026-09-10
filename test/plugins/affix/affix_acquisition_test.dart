import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:build_engine/item_plugin.dart';
import 'package:test/test.dart';

class _CountingRng extends RngService {
  _CountingRng() : super(1);
  int calls = 0;
  @override
  double nextDouble() {
    calls++;
    return super.nextDouble();
  }
}

PluginContext _ctx({RngService? rng}) {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final r = rng ?? RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: r,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: r),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

AffixResolvedSlot _slot(int pos, String kind, AffixDefinition? d) =>
    AffixResolvedSlot(position: pos, slotKind: kind, affix: d);

void main() {
  test('one AffixAcquisition per non-null slot; empty slot yields nothing', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);

    final resolution = AffixResolution([
      _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
      _slot(1, 'suffix', null),
    ]);
    final out = acquireAffixes(
      resolution: resolution,
      target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
      idSource: AffixAcquisitionIdSource(),
      run: const RunRef(runId: 'run-1', runNumber: 1),
      context: ctx,
    );

    expect(out, hasLength(1));
    expect(out.single.affixId, 'af_keen');
    expect(out.single.stat, 'weapon_stat_bonus');
    expect(out.single.value, 3);
    expect(out.single.category, 'item_prefix');
    expect(out.single.runId, 'run-1');
    expect(ctx.components.get<ItemInstance>(instance)!.statBonuses['blade'], 3);
  });

  test('within one logical run, genuine repeats get distinct affixEventIds', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final source = AffixAcquisitionIdSource();
    const run = RunRef(runId: 'run-1', runNumber: 1);

    List<AffixAcquisition> takeKeen() {
      final instance = ownItem(owner, ItemIds.knife, ctx);
      return acquireAffixes(
        resolution: AffixResolution([
          _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
          _slot(1, 'suffix', null),
        ]),
        target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
        idSource: source,
        run: run,
        context: ctx,
      );
    }

    final first = takeKeen().single.affixEventId;
    final second = takeKeen().single.affixEventId;
    expect(first, isNot(second));
  });

  test('two slots in one call => two distinct affixEventIds (per slot)', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    final out = acquireAffixes(
      resolution: AffixResolution([
        _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
        _slot(1, 'suffix', affixDefinition('af_of_the_ember', ctx)),
      ]),
      target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
      idSource: AffixAcquisitionIdSource(),
      run: const RunRef(runId: 'run-1', runNumber: 1),
      context: ctx,
    );
    expect(out.map((a) => a.affixEventId).toSet(), hasLength(2));
    expect(out.map((a) => a.affixId), ['af_keen', 'af_of_the_ember']);
  });

  test('a failed mechanic application does not advance the id source', () {
    final ctx = _ctx();
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    const run = RunRef(runId: 'run-1', runNumber: 1);

    // The affixEventId a fresh source produces for the first successful
    // acquisition of `af_keen` — without touching the string format.
    String firstIdFrom(AffixAcquisitionIdSource src) {
      final owner = ctx.entities.create();
      final instance = ownItem(owner, ItemIds.knife, ctx);
      return acquireAffixes(
        resolution: AffixResolution([
          _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
          _slot(1, 'suffix', null),
        ]),
        target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
        idSource: src,
        run: run,
        context: ctx,
      ).single.affixEventId;
    }

    final pristine = firstIdFrom(AffixAcquisitionIdSource());

    final afterFailure = AffixAcquisitionIdSource();
    // Heal affix on a character with no HealthComponent -> applyAffixMechanic
    // throws before acquireAffixes reaches idSource.next().
    expect(
      () => acquireAffixes(
        resolution: AffixResolution([
          _slot(0, 'prefix', affixDefinition('af_grounding', ctx)), // heal 12
          _slot(1, 'suffix', null),
        ]),
        target: CharacterTarget(character: ctx.entities.create()),
        idSource: afterFailure,
        run: run,
        context: ctx,
      ),
      throwsArgumentError,
    );

    // The failed call consumed nothing: the source still yields its first id.
    expect(firstIdFrom(afterFailure), pristine);
  });

  test('acquireAffixes consumes no RNG', () {
    final rng = _CountingRng();
    final ctx = _ctx(rng: rng);
    ItemPlugin().initialize(ctx);
    AffixPlugin().initialize(ctx);
    final owner = ctx.entities.create();
    final instance = ownItem(owner, ItemIds.knife, ctx);
    final before = rng.calls;
    acquireAffixes(
      resolution: AffixResolution([
        _slot(0, 'prefix', affixDefinition('af_keen', ctx)),
        _slot(1, 'suffix', null),
      ]),
      target: ItemInstanceTarget(instance: instance, itemId: ItemIds.knife),
      idSource: AffixAcquisitionIdSource(),
      run: const RunRef(runId: 'run-1', runNumber: 1),
      context: ctx,
    );
    expect(rng.calls, before);
  });
}
